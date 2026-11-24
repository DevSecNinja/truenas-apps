#!/bin/bash
# Called by .github/workflows/backup-restore-test.yml (backup-restore-test-v5 job).
# End-to-end evidence for the nfrastack/db-backup v5 migration (#80) before any
# service uses it. v5 encrypts with AGE to a public recipient, so the container
# can encrypt but never decrypt. Each run generates a throwaway key pair; the
# real identity never leaves the owner's password manager.
#
# Scenarios (pass names as arguments; default: postgres sqlite):
#
#   postgres     gatus/outline/immich/dawarich pattern: numeric non-root UID,
#                bigint edge values and a foreign key, restored with psql.
#                Also runs once with a wrong password: the failure must show
#                as status=failed in the log (5.0.12 exits 0 even then).
#   sqlite       memos/bitwarden/home-assistant pattern: root, read-only source
#                mount with a live WAL, network none, BLOB byte-for-byte.
#   consistency  v5 dumps PostgreSQL table by table without a snapshot
#                transaction. Writes parent/child rows during the backup and
#                checks that the foreign key still restores.
#
# Every backup scenario checks: exit code 0, exactly one job start and one
# completion in the log (no second run: with MODE=MANUAL the container's own
# service already runs every job once, so `backup-now` must not be passed),
# exactly one *.age artifact, no plaintext dump left behind, the AGE header,
# mode 600, the expected owner, the SHA1 in the JSON sidecar, decryption with
# the identity, and a restore into a fresh database with sentinel checks.
#
# Container logs are written to ${V5_LOG_DIR:-/tmp/db-backup-v5-logs} so the
# workflow can upload them as evidence for the dccd.sh v5 log patterns.
#
# Required host tools: docker, age, age-keygen, zstd, sqlite3, openssl,
# sha1sum.

set -euo pipefail

# --- Image references (kept in sync with services/*/compose.yaml) ------------
# renovate: datasource=docker depName=docker.io/library/postgres
POSTGRES_IMAGE="docker.io/library/postgres:18.3-alpine@sha256:4da1a4828be12604092fa55311276f08f9224a74a62dcb4708bd7439e2a03911"
# renovate: datasource=docker depName=docker.io/nfrastack/db-backup
DB_BACKUP_V5_IMAGE="docker.io/nfrastack/db-backup:5.0.12@sha256:773a7f77e97e48164057ad2637801df7747b790f2b75677a66008259154c10c0"

NETWORK="backup-v5-test-net"
DB_NAME="restore_test"
DB_USER="testuser"
DB_PASS="testpassrestore" # gitleaks:allow — CI-only test credential, not a real secret
PG_SOURCE="backup-v5-pg-source"
PG_RESTORE="backup-v5-pg-restore"
SENTINEL="sentinel_$(date +%s)_$$"
WORK_DIR="$(mktemp -d /tmp/backup-restore-test-v5.XXXXXX)"
LOG_DIR="${V5_LOG_DIR:-/tmp/db-backup-v5-logs}"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
BIGINTS="9223372036854775807,-9223372036854775808,9007199254740993"
WRITER_PID=""
SQLITE_HOLDER_PID=""
# Set by run_backup, check_artifact and restore_postgres; functions report
# through these instead of exit codes so `set -e` is never suspended.
BACKUP_RC=0
DUMP_FILE=""
RESTORE_RESULT=""

_BACKUP_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh disable=SC1091
. "${_BACKUP_TEST_DIR}/lib/log.sh"
# shellcheck disable=SC2034
LOG_TAG="backup-restore-test-v5"

die() {
    log_error "$*"
    exit 1
}

stop_pid() {
    if [ -n "${1}" ] && kill -0 "${1}" 2>/dev/null; then
        kill "${1}" 2>/dev/null || true
        wait "${1}" 2>/dev/null || true
    fi
}

cleanup() {
    stop_pid "${WRITER_PID}"
    stop_pid "${SQLITE_HOLDER_PID}"
    docker rm -f "${PG_SOURCE}" "${PG_RESTORE}" >/dev/null 2>&1 || true
    docker network rm "${NETWORK}" >/dev/null 2>&1 || true
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

pg() {
    docker exec -i -e PGPASSWORD="${DB_PASS}" "${1}" psql -U "${DB_USER}" -d "${DB_NAME}" \
        --set ON_ERROR_STOP=on -q -t -A "${@:2}"
}

start_postgres() {
    docker run -d --name "${1}" --network "${NETWORK}" \
        -e POSTGRES_DB="${DB_NAME}" -e POSTGRES_USER="${DB_USER}" -e POSTGRES_PASSWORD="${DB_PASS}" \
        "${POSTGRES_IMAGE}" >/dev/null
    local attempts=0
    until docker exec "${1}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        [ "${attempts}" -lt 30 ] || die "${1} did not become ready"
        sleep 2
    done
}

# write_config <file> <connection lines> [database profile lines]
# The production db-backup.yml shape: one connection, one job, the AGE
# recipient from the environment, SHA1, zstd and 48-hour retention.
write_config() {
    cat >"${1}" <<YAML
---
log:
  type: console
  colour: false
defaults:
  checksum: sha1
  compression:
    type: zstd
  storage:
    backend: filesystem
    path: /backup
  retention:
    within: 2880m
profiles:
  connections:
    db:
${2}
  databases:
    db:
      connection: db
${3:-}
  encryption:
    age:
      type: age
      recipients:
        - env://DB_BACKUP_AGE_RECIPIENT
jobs:
  - name: db01
    database: db
    encryption: age
    schedule:
      interval: 1440
YAML
}

pg_config() {
    write_config "${1}" "      type: postgres
      host: ${PG_SOURCE}
      port: 5432
      user: ${DB_USER}
      pass: env://DB_PASS" "      include:
        - ${DB_NAME}"
}

# run_backup <name> <backup dir> <config> <db password> [docker run args...]
# Runs the sidecar exactly as Compose will: MODE=MANUAL, no command. Sets
# BACKUP_RC; the log is kept in ${LOG_DIR}/<name>.log.
run_backup() {
    local name="$1" backup_dir="$2" config="$3" pass="$4"
    shift 4
    BACKUP_RC=0
    docker run --rm --name "backup-v5-${name}" \
        -e MODE=MANUAL -e MANUAL_RUN_FOREVER=FALSE -e SETUP_TYPE=MANUAL \
        -e DB_BACKUP_AGE_RECIPIENT="${AGE_RECIPIENT}" -e DB_PASS="${pass}" \
        -v "${config}:/config/db-backup.yml:ro" -v "${backup_dir}:/backup" \
        "$@" "${DB_BACKUP_V5_IMAGE}" >"${LOG_DIR}/${name}.log" 2>&1 || BACKUP_RC=$?
}

# expect_one_successful_run <name> — exit 0, one start, one completion.
expect_one_successful_run() {
    local log="${LOG_DIR}/${1}.log" started completed failed
    if [ "${BACKUP_RC}" -ne 0 ]; then
        cat "${log}" >&2
        die "${1}: backup container exited ${BACKUP_RC}"
    fi
    started="$(grep -c 'job=db01 type=backup status=started' "${log}" || true)"
    completed="$(grep -c 'job=db01 type=backup status=complete ' "${log}" || true)"
    failed="$(grep -c 'status=fail' "${log}" || true)"
    if [ "${started}" != 1 ] || [ "${completed}" != 1 ] || [ "${failed}" != 0 ]; then
        cat "${log}" >&2
        die "${1}: expected one start and one completion, got started=${started} completed=${completed} failed=${failed}"
    fi
}

# check_artifact <backup dir> <expected uid:gid> — sets DUMP_FILE to the
# decrypted, decompressed dump. A root helper container reads the mode and
# owner and hands the files back to the runner user.
check_artifact() {
    local dir="$1" owner="$2" meta files count artifact header sum file matched=0
    # Mode and owner first, as root: the artifact is 600 and the backup
    # directory may belong to root. Then hand everything to the runner user.
    meta="$(docker run --rm --network none -v "${dir}:/backup" --entrypoint /bin/sh "${POSTGRES_IMAGE}" \
        -c "stat -c '%a %u:%g' /backup/*.age; chown -R ${HOST_UID}:${HOST_GID} /backup")"
    files="$(find "${dir}" -path "${dir}/.dbb" -prune -o -type f -print)"
    log_info "artifacts:"$'\n'"${files}"
    count="$(grep -c '\.age$' <<<"${files}" || true)"
    [ "${count}" = 1 ] || die "expected exactly one .age artifact, found ${count}"
    [ "${meta}" = "600 ${owner}" ] || die "artifact mode/owner is '${meta}', expected '600 ${owner}'"
    if grep -Eq '\.(sql|zst|gz|archive)$' <<<"${files}"; then
        die "plaintext dump found next to the encrypted artifact"
    fi
    artifact="$(grep '\.age$' <<<"${files}")"
    case "${artifact}" in
    *.zst.age) ;;
    *) die "unexpected artifact name ${artifact} (expected *.zst.age)" ;;
    esac
    header="$(head -c 21 "${artifact}")"
    [ "${header}" = "age-encryption.org/v1" ] || die "artifact has no AGE header"
    DUMP_FILE="${WORK_DIR}/${artifact##*/}"
    DUMP_FILE="${DUMP_FILE%.zst.age}"
    age -d -i "${WORK_DIR}/identity.txt" -o "${DUMP_FILE}.zst" "${artifact}"
    zstd -q -d "${DUMP_FILE}.zst" -o "${DUMP_FILE}"
    # The JSON sidecar records checksums of the content, not of the ciphertext:
    # accept the SHA1 of the compressed stream or of the plain dump.
    log_info "sidecar ${artifact##*/}.json:"$'\n'"$(<"${artifact}.json")"
    for file in "${DUMP_FILE}.zst" "${DUMP_FILE}" "${artifact}"; do
        sum="$(sha1sum "${file}")"
        sum="${sum%% *}"
        if grep -qs "${sum}" "${artifact}.json"; then
            log_info "SHA1 of ${file##*/} matches the sidecar"
            matched=1
        fi
    done
    [ "${matched}" = 1 ] || die "no SHA1 from ${artifact##*/} matches its JSON sidecar"
}

seed_postgres() {
    pg "${PG_SOURCE}" <<SQL
CREATE TABLE restore_sentinel (id BIGSERIAL PRIMARY KEY, value TEXT NOT NULL, big BIGINT NOT NULL);
INSERT INTO restore_sentinel (value, big) VALUES
  ('${SENTINEL}', 9223372036854775807), ('min', -9223372036854775808), ('js', 9007199254740993);
CREATE TABLE a_parent (id BIGSERIAL PRIMARY KEY, note TEXT NOT NULL);
CREATE TABLE z_child (id BIGSERIAL PRIMARY KEY, parent_id BIGINT NOT NULL REFERENCES a_parent (id));
INSERT INTO a_parent (note) VALUES ('seed');
INSERT INTO z_child (parent_id) VALUES (1);
SQL
}

# restore_postgres — psql DUMP_FILE into a fresh server. Sets RESTORE_RESULT to
# ok, load-failed or orphans. A missing sentinel or bigint drift is fatal.
restore_postgres() {
    local got rc=0
    start_postgres "${PG_RESTORE}"
    docker cp "${DUMP_FILE}" "${PG_RESTORE}:/tmp/restore.sql"
    docker exec -e PGPASSWORD="${DB_PASS}" "${PG_RESTORE}" psql -U "${DB_USER}" -d "${DB_NAME}" \
        --set ON_ERROR_STOP=on -q -f /tmp/restore.sql >/dev/null || rc=$?
    if [ "${rc}" -ne 0 ]; then
        RESTORE_RESULT="load-failed"
        return 0
    fi
    got="$(pg "${PG_RESTORE}" -c "SELECT count(*) FROM restore_sentinel WHERE value = '${SENTINEL}';")"
    [ "${got}" = 1 ] || die "PostgreSQL sentinel missing after restore"
    got="$(pg "${PG_RESTORE}" -c "SELECT string_agg(big::text, ',' ORDER BY id) FROM restore_sentinel;")"
    [ "${got}" = "${BIGINTS}" ] || die "bigint values changed after restore: ${got}"
    got="$(pg "${PG_RESTORE}" -c "SELECT count(*) FROM z_child c LEFT JOIN a_parent p ON p.id = c.parent_id WHERE p.id IS NULL;")"
    if [ "${got}" = 0 ]; then
        RESTORE_RESULT="ok"
    else
        RESTORE_RESULT="orphans"
    fi
}

run_postgres_scenario() {
    log_info "=== v5 PostgreSQL: non-root UID, bigint, foreign key ==="
    local dir="${WORK_DIR}/pgsql" config="${WORK_DIR}/pgsql.yml"
    local -a identity
    mkdir -p "${dir}" "${WORK_DIR}/pgsql-fail"
    start_postgres "${PG_SOURCE}"
    seed_postgres
    pg_config "${config}"
    # Same identity pattern as pocket-id-db-backup: a named user with a fixed UID.
    identity=(
        -e DBBACKUP_USER=cibackup -e DBBACKUP_GROUP=cibackup
        -e CONTAINER_INIT_PRE_COMMAND="addgroup -g ${HOST_GID} cibackup && adduser -D -H -u ${HOST_UID} -G cibackup cibackup"
    )
    run_backup postgres "${dir}" "${config}" "${DB_PASS}" --network "${NETWORK}" "${identity[@]}"
    expect_one_successful_run postgres
    check_artifact "${dir}" "${HOST_UID}:${HOST_GID}"
    restore_postgres
    [ "${RESTORE_RESULT}" = ok ] || die "PostgreSQL restore result: ${RESTORE_RESULT}"

    log_info "Wrong password: the failure must be visible to dccd.sh..."
    run_backup postgres-failure "${WORK_DIR}/pgsql-fail" "${config}" "wrong-password" \
        --network "${NETWORK}" "${identity[@]}"
    grep -q 'job=db01 type=backup status=failed' "${LOG_DIR}/postgres-failure.log" ||
        die "a failed backup logged no 'status=failed' line"
    if [ "${BACKUP_RC}" -eq 0 ]; then
        # 5.0.12: dbb exits 1, but the s6 halt does not pass it to the container.
        echo "::warning title=db-backup v5 exit code::A failed backup exited 0; dccd.sh must detect failures from the log, not the exit code."
    fi
    log_info "failed backup exited ${BACKUP_RC} and logged status=failed"

    docker rm -f "${PG_SOURCE}" "${PG_RESTORE}" >/dev/null
    log_info "v5 PostgreSQL scenario PASSED"
}

run_consistency_scenario() {
    log_info "=== v5 PostgreSQL consistency under concurrent writes ==="
    local dir="${WORK_DIR}/consistency" config="${WORK_DIR}/consistency.yml"
    mkdir -p "${dir}"
    start_postgres "${PG_SOURCE}"
    seed_postgres
    # Enough parent rows that the dump of a_parent takes a while, so new
    # parent/child pairs land between the two table reads.
    pg "${PG_SOURCE}" -c "INSERT INTO a_parent (note) SELECT md5(g::text) FROM generate_series(1, 200000) g;"
    pg_config "${config}"
    (
        while true; do
            docker exec -e PGPASSWORD="${DB_PASS}" "${PG_SOURCE}" psql -U "${DB_USER}" -d "${DB_NAME}" -q -c \
                "WITH p AS (INSERT INTO a_parent (note) VALUES ('live') RETURNING id)
                INSERT INTO z_child (parent_id) SELECT id FROM p;" >/dev/null 2>&1 || true
        done
    ) &
    WRITER_PID=$!
    run_backup consistency "${dir}" "${config}" "${DB_PASS}" --network "${NETWORK}" \
        -e DBBACKUP_USER=root -e DBBACKUP_GROUP=root
    stop_pid "${WRITER_PID}"
    WRITER_PID=""
    expect_one_successful_run consistency
    check_artifact "${dir}" "0:0"
    restore_postgres
    if [ "${RESTORE_RESULT}" != ok ]; then
        echo "::warning title=db-backup v5 consistency::A backup taken during writes restored with result '${RESTORE_RESULT}'. v5 dumps PostgreSQL tables without a snapshot transaction."
        die "consistency scenario FAILED (${RESTORE_RESULT})"
    fi
    docker rm -f "${PG_SOURCE}" "${PG_RESTORE}" >/dev/null
    log_info "v5 consistency scenario PASSED"
}

run_sqlite_scenario() {
    log_info "=== v5 SQLite: root, read-only mount, live WAL, BLOB ==="
    local src="${WORK_DIR}/sqlite_src" dir="${WORK_DIR}/sqlite" config="${WORK_DIR}/sqlite.yml"
    local restored="${WORK_DIR}/restored.db" blob got attempts=0
    mkdir -p "${src}" "${dir}"
    blob="$(openssl rand -hex 128)"
    blob="${blob^^}"
    # Keep a connection open so the -wal file stays un-checkpointed during the
    # backup, the state a running Memos or Home Assistant presents.
    sqlite3 "${src}/${DB_NAME}.db" <<SQL &
.bail on
PRAGMA journal_mode=WAL;
PRAGMA wal_autocheckpoint=0;
CREATE TABLE restore_sentinel (id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT NOT NULL);
INSERT INTO restore_sentinel (value) VALUES ('${SENTINEL}');
CREATE TABLE resource (id INTEGER PRIMARY KEY, filename TEXT NOT NULL, blob BLOB NOT NULL);
INSERT INTO resource (filename, blob) VALUES ('synthetic.bin', X'${blob}');
.shell sleep 120
SQL
    SQLITE_HOLDER_PID=$!
    until [ -s "${src}/${DB_NAME}.db-wal" ]; do
        attempts=$((attempts + 1))
        [ "${attempts}" -lt 50 ] || die "no live -wal file appeared"
        sleep 0.2
    done
    write_config "${config}" "      type: sqlite
      host: /db/${DB_NAME}.db"
    run_backup sqlite "${dir}" "${config}" "" --network none --memory 1024m --pids-limit 100 \
        --security-opt no-new-privileges:true -e DBBACKUP_USER=root -e DBBACKUP_GROUP=root \
        -v "${src}:/db:ro"
    expect_one_successful_run sqlite
    check_artifact "${dir}" "0:0"
    sqlite3 -bail "${restored}" <"${DUMP_FILE}" || die "SQLite dump did not load"
    got="$(sqlite3 "${restored}" 'PRAGMA integrity_check;')"
    [ "${got}" = ok ] || die "SQLite integrity_check failed: ${got}"
    got="$(sqlite3 "${restored}" "SELECT count(*) FROM restore_sentinel WHERE value = '${SENTINEL}';")"
    [ "${got}" = 1 ] || die "SQLite sentinel missing after restore"
    got="$(sqlite3 "${restored}" 'SELECT hex(blob) FROM resource WHERE id = 1;')"
    [ "${got}" = "${blob}" ] || die "SQLite BLOB changed after restore"
    stop_pid "${SQLITE_HOLDER_PID}"
    SQLITE_HOLDER_PID=""
    log_info "v5 SQLite scenario PASSED"
}

mkdir -p "${LOG_DIR}"
age-keygen -o "${WORK_DIR}/identity.txt" 2>/dev/null
AGE_RECIPIENT="$(age-keygen -y "${WORK_DIR}/identity.txt")"
docker network create "${NETWORK}" >/dev/null

scenarios=("$@")
[ "${#scenarios[@]}" -gt 0 ] || scenarios=(postgres sqlite)
for scenario in "${scenarios[@]}"; do
    case "${scenario}" in
    postgres) run_postgres_scenario ;;
    sqlite) run_sqlite_scenario ;;
    consistency) run_consistency_scenario ;;
    *) die "unknown scenario ${scenario}" ;;
    esac
done
log_result "db-backup v5 scenarios passed: ${scenarios[*]}"
