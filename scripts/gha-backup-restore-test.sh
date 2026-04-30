#!/bin/bash
# Called by .github/workflows/backup-restore-test.yml (backup-restore-test job).
# Spins up ephemeral Docker containers to perform end-to-end backup/restore
# cycles for every database type used in this repository:
#
#   * PostgreSQL (pgsql)  — used by gatus, immich, outline
#   * MongoDB    (mongo)  — used by unifi
#   * SQLite     (sqlite3) — used by home-assistant
#
# Each scenario validates that:
#
#   1. tiredofit/db-backup can produce an encrypted, ZSTD-compressed dump
#      using the same settings as production services.
#   2. The dump can be decrypted with gpg and decompressed with zstd.
#   3. The dump structure is valid (DB-specific header / format check).
#   4. The dump restores cleanly into a fresh database instance.
#   5. The restored data matches the original (sentinel row verification).
#
# Images are intentionally kept in sync with services/*/compose.yaml so that
# the test exercises the exact same backup toolchain used in production.
#
# Required host tools: docker, gpg, zstd, sqlite3
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed

set -euo pipefail

# --- Image references (kept in sync with services/*/compose.yaml) ----------------
# renovate: datasource=docker depName=docker.io/library/postgres
POSTGRES_IMAGE="docker.io/library/postgres:18.3-alpine@sha256:4da1a4828be12604092fa55311276f08f9224a74a62dcb4708bd7439e2a03911"
# renovate: datasource=docker depName=docker.io/library/mongo
MONGO_IMAGE="docker.io/library/mongo:8.2.6@sha256:eea8506335198f8b359865b32004036310854a935fbd317083817c614152818f"
# renovate: datasource=docker depName=docker.io/tiredofit/db-backup
DB_BACKUP_IMAGE="docker.io/tiredofit/db-backup:4.1.100@sha256:78e3cb669ee9648c1a4ab7e8421c6e89d01b659bfa5963f7611a2347b2009eab"

# --- Test parameters ---------------------------------------------------------

NETWORK="backup-test-net"
DB_NAME="restore_test"
DB_USER="testuser"
DB_PASS="testpassrestore" # gitleaks:allow — CI-only test credential, not a real secret

# Per-scenario container names. Tracked here so the cleanup trap can remove
# them all even if a scenario aborts halfway through.
PG_SOURCE="backup-test-pg-source"
PG_RESTORE="backup-test-pg-restore"
MONGO_SOURCE="backup-test-mongo-source"
MONGO_RESTORE="backup-test-mongo-restore"

# Unique sentinel value written before backup and verified after restore.
# If it survives the full cycle the pipeline is working correctly.
SENTINEL="sentinel_$(date +%s)_$$"

# Temporary directory for backup files; removed by the cleanup trap.
WORK_DIR="$(mktemp -d /tmp/backup-restore-test.XXXXXX)"

# Passphrase for the test backup (strength does not matter here).
ENC_PASSPHRASE="ci_test_enc_key" # gitleaks:allow — CI-only test credential, not a real secret

# UID/GID for the backup container so it writes files as the current user.
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# --- Helpers -----------------------------------------------------------------

_BACKUP_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh disable=SC1091
. "${_BACKUP_TEST_DIR}/lib/log.sh"
# shellcheck disable=SC2034
LOG_TAG="backup-restore-test"

die() {
    log_error "$*"
    exit 1
}

cleanup() {
    log_state "Cleaning up containers, network, and temp files..."
    docker rm -f \
        "${PG_SOURCE}" "${PG_RESTORE}" \
        "${MONGO_SOURCE}" "${MONGO_RESTORE}" \
        2>/dev/null || true
    docker network rm "${NETWORK}" 2>/dev/null || true
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

wait_for_postgres() {
    local container="$1"
    local attempts=0
    local max=30
    log_state "Waiting for PostgreSQL in ${container} to become ready"
    until docker exec "${container}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        [ "${attempts}" -ge "${max}" ] && die "${container} did not become ready after ${max} attempts"
        sleep 2
    done
    log_info "${container} is ready"
}

wait_for_mongo() {
    local container="$1"
    local attempts=0
    local max=30
    log_state "Waiting for MongoDB in ${container} to become ready"
    # mongosh is shipped in the official mongo image. Authenticate against the
    # admin DB to be sure user provisioning has finished, not just the daemon.
    until docker exec "${container}" mongosh \
        --quiet \
        --username "${DB_USER}" \
        --password "${DB_PASS}" \
        --authenticationDatabase admin \
        --eval "db.adminCommand('ping')" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        [ "${attempts}" -ge "${max}" ] && die "${container} did not become ready after ${max} attempts"
        sleep 2
    done
    log_info "${container} is ready"
}

# Decrypt a tiredofit/db-backup output file and decompress the resulting
# zstd payload. Echoes the absolute path of the final plain dump file.
# Decrypt a tiredofit/db-backup output file and decompress the resulting
# payload. The compressor depends on the database engine: pgsql/sqlite3 use
# zstd (`DEFAULT_COMPRESSION=ZSTD`), but mongo always uses gzip because the
# sidecar invokes `mongodump --gzip` regardless of the compression default.
# Echoes the absolute path of the final plain dump file.
decrypt_and_decompress() {
    local enc_file="$1"
    local compressed="${enc_file%.gpg}"
    local dump_file

    # NOTE: this function returns the dump path on stdout, so all log output
    # must go to stderr to avoid polluting the captured value.
    log_state "Decrypting ${enc_file} with gpg" >&2
    gpg --batch --passphrase "${ENC_PASSPHRASE}" \
        --output "${compressed}" --decrypt "${enc_file}" >/dev/null 2>&1

    case "${compressed}" in
    *.zst)
        dump_file="${compressed%.zst}"
        log_state "Decompressing ${compressed} with zstd" >&2
        zstd -df "${compressed}" -o "${dump_file}" >/dev/null
        ;;
    *.gz)
        dump_file="${compressed%.gz}"
        log_state "Decompressing ${compressed} with gzip" >&2
        gunzip -c "${compressed}" >"${dump_file}"
        ;;
    *)
        die "Unrecognised compression suffix on '${compressed}' (expected .zst or .gz)"
        ;;
    esac

    printf '%s' "${dump_file}"
}

# Locate the encrypted backup file under a directory. tiredofit/db-backup
# always names dumps `<type>_<container>_<db>_<date>.<fmt>.zst.gpg`, plus a
# `latest-…` symlink (which `-type f` skips). Echoes the absolute path of the
# real backup file, or exits non-zero if none is found.
find_backup_file() {
    local dir="$1"
    local files=()
    # SC2312: pipefail is active; find returns 0 even with no results.
    # shellcheck disable=SC2312
    mapfile -t files < <(find "${dir}" -name "*.gpg" -type f | sort)
    [ "${#files[@]}" -gt 0 ] || die "No *.gpg backup file found under ${dir}"
    printf '%s' "${files[0]}"
}

# --- Scenario 1: PostgreSQL --------------------------------------------------

run_postgres_scenario() {
    log_rule STATE "PostgreSQL backup/restore cycle"

    local backup_dir="${WORK_DIR}/pgsql"
    mkdir -p "${backup_dir}"

    log_state "Starting source PostgreSQL (${PG_SOURCE})"
    docker run -d \
        --name "${PG_SOURCE}" \
        --network "${NETWORK}" \
        -e POSTGRES_DB="${DB_NAME}" \
        -e POSTGRES_USER="${DB_USER}" \
        -e POSTGRES_PASSWORD="${DB_PASS}" \
        "${POSTGRES_IMAGE}" >/dev/null

    wait_for_postgres "${PG_SOURCE}"

    log_state "Inserting sentinel row"
    docker exec -i -e PGPASSWORD="${DB_PASS}" "${PG_SOURCE}" psql \
        -U "${DB_USER}" -d "${DB_NAME}" >/dev/null <<SQL
CREATE TABLE restore_sentinel (id SERIAL PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO restore_sentinel (value) VALUES ('${SENTINEL}');
SQL

    log_state "Running tiredofit/db-backup (pgsql)"
    docker run --rm \
        --network "${NETWORK}" \
        -e USER_DBBACKUP="${HOST_UID}" \
        -e GROUP_DBBACKUP="${HOST_GID}" \
        -e CONTAINER_NAME="backup-test-pg-backup" \
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
        -e DB01_HOST="${PG_SOURCE}" \
        -e DB01_NAME="${DB_NAME}" \
        -e DB01_USER="${DB_USER}" \
        -e DB01_PORT=5432 \
        -e DB01_PASS="${DB_PASS}" \
        -v "${backup_dir}:/backup" \
        "${DB_BACKUP_IMAGE}" \
        backup-now >/dev/null

    local enc_file dump_file
    enc_file="$(find_backup_file "${backup_dir}")"
    log_info "Backup file: ${enc_file}"
    dump_file="$(decrypt_and_decompress "${enc_file}")"
    log_info "Dump ready: ${dump_file}"

    log_state "Verifying plain-text pg_dump structure"
    grep -q '^-- PostgreSQL database dump' "${dump_file}" ||
        die "dump file does not contain the expected PostgreSQL dump header"
    grep -q 'restore_sentinel' "${dump_file}" ||
        die "dump file does not reference the expected sentinel table"

    log_state "Starting restore-target PostgreSQL (${PG_RESTORE})"
    docker run -d \
        --name "${PG_RESTORE}" \
        --network "${NETWORK}" \
        -e POSTGRES_DB="${DB_NAME}" \
        -e POSTGRES_USER="${DB_USER}" \
        -e POSTGRES_PASSWORD="${DB_PASS}" \
        "${POSTGRES_IMAGE}" >/dev/null

    wait_for_postgres "${PG_RESTORE}"

    log_state "Restoring dump with psql"
    docker cp "${dump_file}" "${PG_RESTORE}:/tmp/restore.sql"
    docker exec -e PGPASSWORD="${DB_PASS}" "${PG_RESTORE}" psql \
        -U "${DB_USER}" -d "${DB_NAME}" \
        --set ON_ERROR_STOP=on \
        -f /tmp/restore.sql >/dev/null

    log_state "Verifying sentinel row in restored database"
    local restored
    restored=$(docker exec -e PGPASSWORD="${DB_PASS}" "${PG_RESTORE}" psql \
        -U "${DB_USER}" -d "${DB_NAME}" -t -A -c \
        "SELECT COUNT(*) FROM restore_sentinel WHERE value = '${SENTINEL}';")
    [ "${restored}" = "1" ] ||
        die "PostgreSQL sentinel mismatch after restore (expected 1, got '${restored}')"

    docker rm -f "${PG_SOURCE}" "${PG_RESTORE}" >/dev/null 2>&1 || true

    log_result "PostgreSQL scenario PASSED"
}

# --- Scenario 2: MongoDB -----------------------------------------------------

run_mongo_scenario() {
    log_rule STATE "MongoDB backup/restore cycle"

    local backup_dir="${WORK_DIR}/mongo"
    mkdir -p "${backup_dir}"

    log_state "Starting source MongoDB (${MONGO_SOURCE})"
    docker run -d \
        --name "${MONGO_SOURCE}" \
        --network "${NETWORK}" \
        -e MONGO_INITDB_ROOT_USERNAME="${DB_USER}" \
        -e MONGO_INITDB_ROOT_PASSWORD="${DB_PASS}" \
        "${MONGO_IMAGE}" >/dev/null

    wait_for_mongo "${MONGO_SOURCE}"

    log_state "Inserting sentinel document"
    docker exec -i "${MONGO_SOURCE}" mongosh \
        --quiet \
        --username "${DB_USER}" \
        --password "${DB_PASS}" \
        --authenticationDatabase admin \
        "${DB_NAME}" >/dev/null <<JS
db.restore_sentinel.insertOne({ value: "${SENTINEL}" });
JS

    log_state "Running tiredofit/db-backup (mongo)"
    docker run --rm \
        --network "${NETWORK}" \
        -e USER_DBBACKUP="${HOST_UID}" \
        -e GROUP_DBBACKUP="${HOST_GID}" \
        -e CONTAINER_NAME="backup-test-mongo-backup" \
        -e CONTAINER_ENABLE_MONITORING=FALSE \
        -e CONTAINER_ENABLE_SCHEDULING=FALSE \
        -e MODE=MANUAL \
        -e MANUAL_RUN_FOREVER=FALSE \
        -e ENABLE_NOTIFICATIONS=FALSE \
        -e DEFAULT_CHECKSUM=SHA1 \
        -e DEFAULT_COMPRESSION=ZSTD \
        -e DEFAULT_ENCRYPT=TRUE \
        -e DEFAULT_ENCRYPT_PASSPHRASE="${ENC_PASSPHRASE}" \
        -e DB01_TYPE=mongo \
        -e DB01_HOST="${MONGO_SOURCE}" \
        -e DB01_NAME="${DB_NAME}" \
        -e DB01_USER="${DB_USER}" \
        -e DB01_PORT=27017 \
        -e DB01_PASS="${DB_PASS}" \
        -e DB01_AUTH=admin \
        -v "${backup_dir}:/backup" \
        "${DB_BACKUP_IMAGE}" \
        backup-now >/dev/null

    local enc_file dump_file
    enc_file="$(find_backup_file "${backup_dir}")"
    log_info "Backup file: ${enc_file}"
    dump_file="$(decrypt_and_decompress "${enc_file}")"
    log_info "Dump ready: ${dump_file}"

    log_state "Verifying mongodump archive header"
    # mongodump --archive files start with the magic bytes "8199e26d" (LE) per
    # the BSON archive format spec. Check the magic to ensure the file is a
    # well-formed mongodump archive and not a partial / corrupt download.
    local magic
    magic=$(head -c 4 "${dump_file}" | od -An -tx1 | tr -d ' \n')
    [ "${magic}" = "6de29981" ] ||
        die "dump file does not have a valid mongodump archive header (got '${magic}')"

    log_state "Starting restore-target MongoDB (${MONGO_RESTORE})"
    docker run -d \
        --name "${MONGO_RESTORE}" \
        --network "${NETWORK}" \
        -e MONGO_INITDB_ROOT_USERNAME="${DB_USER}" \
        -e MONGO_INITDB_ROOT_PASSWORD="${DB_PASS}" \
        "${MONGO_IMAGE}" >/dev/null

    wait_for_mongo "${MONGO_RESTORE}"

    log_state "Restoring dump with mongorestore"
    docker cp "${dump_file}" "${MONGO_RESTORE}:/tmp/restore.archive"
    docker exec "${MONGO_RESTORE}" mongorestore \
        --username "${DB_USER}" \
        --password "${DB_PASS}" \
        --authenticationDatabase admin \
        --drop \
        --archive=/tmp/restore.archive >/dev/null 2>&1

    log_state "Verifying sentinel document in restored database"
    local restored
    restored=$(docker exec "${MONGO_RESTORE}" mongosh \
        --quiet \
        --username "${DB_USER}" \
        --password "${DB_PASS}" \
        --authenticationDatabase admin \
        "${DB_NAME}" \
        --eval "db.restore_sentinel.countDocuments({ value: '${SENTINEL}' })" |
        tr -d '[:space:]')
    [ "${restored}" = "1" ] ||
        die "MongoDB sentinel mismatch after restore (expected 1, got '${restored}')"

    docker rm -f "${MONGO_SOURCE}" "${MONGO_RESTORE}" >/dev/null 2>&1 || true

    log_result "MongoDB scenario PASSED"
}

# --- Scenario 3: SQLite ------------------------------------------------------

run_sqlite_scenario() {
    log_rule STATE "SQLite backup/restore cycle"

    local src_dir="${WORK_DIR}/sqlite_src"
    local backup_dir="${WORK_DIR}/sqlite_backup"
    local restore_dir="${WORK_DIR}/sqlite_restore"
    mkdir -p "${src_dir}" "${backup_dir}" "${restore_dir}"

    local src_db="${src_dir}/${DB_NAME}.db"
    log_state "Creating source SQLite database with sentinel"
    sqlite3 "${src_db}" <<SQL
CREATE TABLE restore_sentinel (id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT NOT NULL);
INSERT INTO restore_sentinel (value) VALUES ('${SENTINEL}');
SQL

    log_state "Running tiredofit/db-backup (sqlite3)"
    # SQLite doesn't need a server; mount the db read-only into the backup
    # container, mirroring the home-assistant compose setup.
    docker run --rm \
        --network none \
        -e USER_DBBACKUP="${HOST_UID}" \
        -e GROUP_DBBACKUP="${HOST_GID}" \
        -e CONTAINER_NAME="backup-test-sqlite-backup" \
        -e CONTAINER_ENABLE_MONITORING=FALSE \
        -e CONTAINER_ENABLE_SCHEDULING=FALSE \
        -e MODE=MANUAL \
        -e MANUAL_RUN_FOREVER=FALSE \
        -e ENABLE_NOTIFICATIONS=FALSE \
        -e DEFAULT_CHECKSUM=SHA1 \
        -e DEFAULT_COMPRESSION=ZSTD \
        -e DEFAULT_ENCRYPT=TRUE \
        -e DEFAULT_ENCRYPT_PASSPHRASE="${ENC_PASSPHRASE}" \
        -e DB01_TYPE=sqlite3 \
        -e DB01_HOST="/db/${DB_NAME}.db" \
        -v "${src_dir}:/db:ro" \
        -v "${backup_dir}:/backup" \
        "${DB_BACKUP_IMAGE}" \
        backup-now >/dev/null

    local enc_file dump_file
    enc_file="$(find_backup_file "${backup_dir}")"
    log_info "Backup file: ${enc_file}"
    dump_file="$(decrypt_and_decompress "${enc_file}")"
    log_info "Dump ready: ${dump_file}"

    log_state "Verifying SQLite backup magic bytes"
    # tiredofit/db-backup for sqlite3 uses the SQLite Online Backup API
    # (sqlite3 .backup), producing a *binary* SQLite database file — not a
    # plain-text .dump. Validate by checking the SQLite file magic header
    # ("SQLite format 3\0", per https://www.sqlite.org/fileformat.html).
    local magic
    magic=$(head -c 15 "${dump_file}")
    [ "${magic}" = "SQLite format 3" ] ||
        die "dump file does not have a valid SQLite database header"

    log_state "Restoring dump into a fresh SQLite database"
    local restore_db="${restore_dir}/${DB_NAME}.db"
    cp "${dump_file}" "${restore_db}"
    # Sanity-check the copied file with PRAGMA integrity_check.
    local integrity
    integrity=$(sqlite3 "${restore_db}" "PRAGMA integrity_check;")
    [ "${integrity}" = "ok" ] ||
        die "restored SQLite db failed integrity_check (got '${integrity}')"

    log_state "Verifying sentinel row in restored database"
    local restored
    restored=$(sqlite3 "${restore_db}" \
        "SELECT COUNT(*) FROM restore_sentinel WHERE value = '${SENTINEL}';")
    [ "${restored}" = "1" ] ||
        die "SQLite sentinel mismatch after restore (expected 1, got '${restored}')"

    log_result "SQLite scenario PASSED"
}

# --- Run all scenarios -------------------------------------------------------

log_state "Creating Docker test network"
docker network create "${NETWORK}" >/dev/null

run_postgres_scenario
run_mongo_scenario
run_sqlite_scenario

log_banner "Backup/restore cycle PASSED for pgsql, mongo, and sqlite3" RESULT
