#!/bin/bash
# Called by .github/workflows/backup-restore-test.yml (backup-restore-test job).
# Spins up ephemeral Docker containers to perform a full end-to-end
# PostgreSQL backup/restore cycle, validating that:
#
#   1. tiredofit/db-backup can produce an encrypted, ZSTD-compressed dump
#      using the same settings as production services.
#   2. The dump can be decrypted with openssl and decompressed with zstd.
#   3. pg_restore --list succeeds (structural integrity check).
#   4. The dump restores cleanly into a fresh PostgreSQL instance.
#   5. The restored data matches the original (sentinel row verification).
#
# Images are intentionally kept in sync with services/*/compose.yaml so that
# the test exercises the exact same backup toolchain used in production.
#
# Required host tools: docker, openssl, zstd, pg_restore (postgresql-client)
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed

set -euo pipefail

# --- Image references (kept in sync with services/*/compose.yaml) ----------------
# renovate: datasource=docker depName=docker.io/library/postgres
POSTGRES_IMAGE="docker.io/library/postgres:18.3-alpine@sha256:4da1a4828be12604092fa55311276f08f9224a74a62dcb4708bd7439e2a03911"
# renovate: datasource=docker depName=docker.io/tiredofit/db-backup
DB_BACKUP_IMAGE="docker.io/tiredofit/db-backup:4.1.100@sha256:78e3cb669ee9648c1a4ab7e8421c6e89d01b659bfa5963f7611a2347b2009eab"

# --- Test parameters ---------------------------------------------------------

NETWORK="backup-test-net"
SOURCE_DB="backup-test-source"
RESTORE_DB="backup-test-restore"
DB_NAME="restore_test"
DB_USER="testuser"
DB_PASS="testpassrestore" # gitleaks:allow — CI-only test credential, not a real secret

# Unique sentinel value written before backup and verified after restore.
# If it survives the full cycle the pipeline is working correctly.
SENTINEL="sentinel_$(date +%s)_$$"

# Temporary directory for backup files; removed by the cleanup trap.
WORK_DIR="$(mktemp -d /tmp/backup-restore-test.XXXXXX)"

# Passphrase for the test backup (strength does not matter here).
ENC_PASSPHRASE="ci_test_enc_key" # gitleaks:allow — CI-only test credential, not a real secret

# --- Helpers -----------------------------------------------------------------

log() { printf '[backup-restore-test] %s\n' "$*"; }
die() {
    log "ERROR: $*"
    exit 1
}

cleanup() {
    log "Cleaning up containers, network, and temp files..."
    docker rm -f "${SOURCE_DB}" "${RESTORE_DB}" 2>/dev/null || true
    docker network rm "${NETWORK}" 2>/dev/null || true
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

wait_for_postgres() {
    local container="$1"
    local attempts=0
    local max=30
    log "Waiting for PostgreSQL in ${container} to become ready..."
    until docker exec "${container}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        [ "${attempts}" -ge "${max}" ] && die "${container} did not become ready after ${max} attempts"
        sleep 2
    done
    log "${container} is ready"
}

# --- Step 1: Create test network ---------------------------------------------

log "Creating Docker test network..."
docker network create "${NETWORK}"

# --- Step 2: Start source PostgreSQL -----------------------------------------

log "Starting source database (${SOURCE_DB})..."
docker run -d \
    --name "${SOURCE_DB}" \
    --network "${NETWORK}" \
    -e POSTGRES_DB="${DB_NAME}" \
    -e POSTGRES_USER="${DB_USER}" \
    -e POSTGRES_PASSWORD="${DB_PASS}" \
    "${POSTGRES_IMAGE}"

wait_for_postgres "${SOURCE_DB}"

# --- Step 3: Insert sentinel data --------------------------------------------

log "Inserting sentinel data..."
docker exec -e PGPASSWORD="${DB_PASS}" "${SOURCE_DB}" psql \
    -U "${DB_USER}" -d "${DB_NAME}" <<SQL
CREATE TABLE restore_sentinel (id SERIAL PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO restore_sentinel (value) VALUES ('${SENTINEL}');
SQL

INSERTED=$(docker exec -e PGPASSWORD="${DB_PASS}" "${SOURCE_DB}" psql \
    -U "${DB_USER}" -d "${DB_NAME}" -t -A -c \
    "SELECT COUNT(*) FROM restore_sentinel WHERE value = '${SENTINEL}';")
[ "${INSERTED}" = "1" ] || die "Sentinel insert failed (got count='${INSERTED}')"
log "Sentinel '${SENTINEL}' inserted successfully"

# --- Step 4: Backup ----------------------------------------------------------

log "Running tiredofit/db-backup to produce an encrypted dump..."
docker run --rm \
    --network "${NETWORK}" \
    -e USER_DBBACKUP=0 \
    -e GROUP_DBBACKUP=0 \
    -e CONTAINER_NAME="backup-test-backup" \
    -e CONTAINER_ENABLE_MONITORING=FALSE \
    -e CONTAINER_ENABLE_SCHEDULING=FALSE \
    -e MODE=MANUAL \
    -e MANUAL_RUN_FOREVER=FALSE \
    -e ENABLE_NOTIFICATIONS=FALSE \
    -e DEFAULT_CHECKSUM=SHA1 \
    -e DEFAULT_COMPRESSION=ZSTD \
    -e DEFAULT_ENCRYPT=TRUE \
    -e DEFAULT_ENCRYPT_PASSPHRASE="${ENC_PASSPHRASE}" \
    -e DB01_TYPE=pgsql \
    -e DB01_HOST="${SOURCE_DB}" \
    -e DB01_NAME="${DB_NAME}" \
    -e DB01_USER="${DB_USER}" \
    -e DB01_PORT=5432 \
    -e DB01_PASS="${DB_PASS}" \
    -v "${WORK_DIR}:/backup" \
    "${DB_BACKUP_IMAGE}" \
    backup-now

# --- Step 5: Verify backup file created --------------------------------------

# SC2312: pipefail is active; find returns 0 even with no results.
# shellcheck disable=SC2312
mapfile -t ENC_FILES < <(find "${WORK_DIR}" -name "*.enc" -type f | sort)
[ "${#ENC_FILES[@]}" -gt 0 ] || die "No encrypted backup file found in ${WORK_DIR} — backup may have failed"
ENC_FILE="${ENC_FILES[0]}"
log "Backup file: ${ENC_FILE}"

# --- Step 6: Decrypt ---------------------------------------------------------

log "Decrypting backup with openssl..."
ZST_FILE="${ENC_FILE%.enc}"
openssl enc -d -aes-256-cbc -pbkdf2 \
    -in "${ENC_FILE}" \
    -out "${ZST_FILE}" \
    -pass "pass:${ENC_PASSPHRASE}"

# --- Step 7: Decompress ------------------------------------------------------

log "Decompressing backup with zstd..."
DUMP_FILE="${ZST_FILE%.zst}"
zstd -d "${ZST_FILE}" -o "${DUMP_FILE}"
log "Dump ready: ${DUMP_FILE}"

# --- Step 8: Structural integrity check --------------------------------------

log "Verifying dump structure with pg_restore --list..."
pg_restore --list "${DUMP_FILE}" >/dev/null ||
    die "pg_restore --list failed — dump is not a valid pg_restore archive"

# --- Step 9: Start restore-target database -----------------------------------

log "Starting restore-target database (${RESTORE_DB})..."
docker run -d \
    --name "${RESTORE_DB}" \
    --network "${NETWORK}" \
    -e POSTGRES_DB="${DB_NAME}" \
    -e POSTGRES_USER="${DB_USER}" \
    -e POSTGRES_PASSWORD="${DB_PASS}" \
    "${POSTGRES_IMAGE}"

wait_for_postgres "${RESTORE_DB}"

# --- Step 10: Restore --------------------------------------------------------

log "Copying dump into restore container..."
docker cp "${DUMP_FILE}" "${RESTORE_DB}:/tmp/restore.dump"

log "Restoring dump with pg_restore..."
docker exec -e PGPASSWORD="${DB_PASS}" "${RESTORE_DB}" pg_restore \
    -U "${DB_USER}" -d "${DB_NAME}" \
    --clean --if-exists \
    /tmp/restore.dump

# --- Step 11: Verify sentinel data after restore -----------------------------

log "Verifying sentinel data in restored database..."
RESTORED=$(docker exec -e PGPASSWORD="${DB_PASS}" "${RESTORE_DB}" psql \
    -U "${DB_USER}" -d "${DB_NAME}" -t -A -c \
    "SELECT COUNT(*) FROM restore_sentinel WHERE value = '${SENTINEL}';")
[ "${RESTORED}" = "1" ] ||
    die "Sentinel mismatch after restore (expected 1, got '${RESTORED}')"

log "SUCCESS: Full backup/restore cycle passed — sentinel data verified after restore"
