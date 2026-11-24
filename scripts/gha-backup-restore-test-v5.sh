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
#   sqlite       memos/bitwarden/home-assistant pattern: root, read-only source
#                mount with a live WAL, network none, BLOB byte-for-byte.
#   consistency  v5 dumps PostgreSQL table by table without a snapshot
#                transaction. Writes parent/child rows during the backup and
#                checks that the foreign key still restores.
#
# Every backup scenario checks: exit code 0, exactly one *.age artifact (one
# run, no loop), no plaintext dump left behind, the AGE header, mode 600, the
# expected owner, the SHA1 in the JSON sidecar, decryption with the identity,
# and a restore into a fresh database with sentinel checks.
#
# Container logs are written to ${V5_LOG_DIR:-/tmp/db-backup-v5-logs} so the
# workflow can upload them as evidence for the dccd.sh v5 log patterns.
#
# Required host tools: docker, age, age-keygen, zstd, sqlite3, openssl.

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

# run_backup <name> <backup dir> <config> [docker run args...]
run_backup() {
    local name="$1" backup_dir="$2" config="$3" rc=0
    shift 3
    docker run --rm --name "backup-v5-${name}" \
        -e MODE=MANUAL -e MANUAL_RUN_FOREVER=FALSE -e SETUP_TYPE=MANUAL \
        -e DB_BACKUP_AGE_RECIPIENT="${AGE_RECIPIENT}" -e DB_PASS="${DB_PASS}" \
        -v "${config}:/config/db-backup.yml:ro" -v "${backup_dir}:/backup" \
        "$@" "${DB_BACKUP_V5_IMAGE}" backup-now >"${LOG_DIR}/${name}.log" 2>&1 || rc=$?
    if [ "${rc}" -ne 0 ]; then
        cat "${LOG_DIR}/${name}.log" >&2
        die "${name}: backup container exited ${rc}"
    fi
}

# check_artifact <backup dir> <expected uid:gid> — prints the path of the
# decrypted, decompressed dump. The file checks run as root in a helper
# container because the artifact belongs to the backup identity (mode 600).
check_artifact() {
    local dir="$1" owner="$2" artifact dump
    docker run --rm --network none -v "${dir}:/backup" --entrypoint /bin/sh \
        -e OWNER="${owner}" -e HOST_UID="${HOST_UID}" -e HOST_GID="${HOST_GID}" \
        "${DB_BACKUP_V5_IMAGE}" -c '
        set -eu
        found=$(find /backup -path /backup/.dbb -prune -o -type f -print)
        printf "artifacts:\n%s\n" "${found}" >&2
        n=$(printf "%s\n" "${found}" | grep -c "\.age$" || true)
        [ "${n}" = 1 ] || { echo "expected exactly one .age artifact, found ${n}" >&2; exit 1; }
        if printf "%s\n" "${found}" | grep -Eq "\.(sql|zst|gz|archive)$"; then
            echo "plaintext dump found next to the encrypted artifact" >&2; exit 1
        fi
        artifact=$(printf "%s\n" "${found}" | grep "\.age$")
        [ "$(head -c 21 "${artifact}")" = "age-encryption.org/v1" ] || { echo "missing AGE header" >&2; exit 1; }
        [ "$(stat -c %a "${artifact}")" = 600 ] || { echo "artifact mode is not 600" >&2; exit 1; }
        [ "$(stat -c %u:%g "${artifact}")" = "${OWNER}" ] || { echo "artifact owner is not ${OWNER}" >&2; exit 1; }
        sum=$(sha1sum "${artifact}" | cut -d" " -f1)
        grep -rqs "${sum}" /backup --include="*.json" || { echo "SHA1 ${sum} not in a JSON sidecar" >&2; exit 1; }
        chown -R "${HOST_UID}:${HOST_GID}" /backup
    ' || die "artifact checks failed in ${dir}"

    artifact="$(find "${dir}" -path "${dir}/.dbb" -prune -o -type f -name '*.age' -print)"
    case "${artifact}" in
    *.zst.age) ;;
    *) die "unexpected artifact name ${artifact} (expected *.zst.age)" ;;
    esac
    dump="${WORK_DIR}/$(basename "${artifact%.zst.age}")"
    age -d -i "${WORK_DIR}/identity.txt" "${artifact}" | zstd -q -d -o "${dump}"
    printf '%s' "${dump}"
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

# restore_postgres <dump> — psql into a fresh server; returns non-zero when the
# load fails or child rows lost their parent. Bigint drift is always fatal.
restore_postgres() {
    local got
    start_postgres "${PG_RESTORE}"
    docker cp "${1}" "${PG_RESTORE}:/tmp/restore.sql"
    docker exec -e PGPASSWORD="${DB_PASS}" "${PG_RESTORE}" psql -U "${DB_USER}" -d "${DB_NAME}" \
        --set ON_ERROR_STOP=on -q -f /tmp/restore.sql >/dev/null || return 1
    got="$(pg "${PG_RESTORE}" -c "SELECT count(*) FROM restore_sentinel WHERE value = '${SENTINEL}';")"
    [ "${got}" = 1 ] || die "PostgreSQL sentinel missing after restore"
    got="$(pg "${PG_RESTORE}" -c "SELECT string_agg(big::text, ',' ORDER BY id) FROM restore_sentinel;")"
    [ "${got}" = "${BIGINTS}" ] || die "bigint values changed after restore: ${got}"
    got="$(pg "${PG_RESTORE}" -c "SELECT count(*) FROM z_child c LEFT JOIN a_parent p ON p.id = c.parent_id WHERE p.id IS NULL;")"
    [ "${got}" = 0 ]
}

run_postgres_scenario() {
    log_info "=== v5 PostgreSQL: non-root UID, bigint, foreign key ==="
    local dir="${WORK_DIR}/pgsql" config="${WORK_DIR}/pgsql.yml" dump
    mkdir -p "${dir}"
    start_postgres "${PG_SOURCE}"
    seed_postgres
    pg_config "${config}"
    # Same identity pattern as pocket-id-db-backup: a named user with a fixed UID.
    run_backup postgres "${dir}" "${config}" --network "${NETWORK}" \
        -e DBBACKUP_USER=cibackup -e DBBACKUP_GROUP=cibackup \
        -e CONTAINER_INIT_PRE_COMMAND="addgroup -g ${HOST_GID} cibackup && adduser -D -H -u ${HOST_UID} -G cibackup cibackup"
    dump="$(check_artifact "${dir}" "${HOST_UID}:${HOST_GID}")"
    restore_postgres "${dump}" || die "PostgreSQL restore or foreign-key check failed"
    docker rm -f "${PG_SOURCE}" "${PG_RESTORE}" >/dev/null
    log_info "v5 PostgreSQL scenario PASSED"
}

run_consistency_scenario() {
    log_info "=== v5 PostgreSQL consistency under concurrent writes ==="
    local dir="${WORK_DIR}/consistency" config="${WORK_DIR}/consistency.yml" dump
    mkdir -p "${dir}"
    start_postgres "${PG_SOURCE}"
    seed_postgres
    # Enough parent rows that the dump of a_parent takes a while, so new
    # parent/child pairs land between the two table reads.
    pg "${PG_SOURCE}" -c "INSERT INTO a_parent (note) SELECT md5(g::text) FROM generate_series(1, 200000) g;"
    pg_config "${config}"
    (
        while true; do
            pg "${PG_SOURCE}" -c "WITH p AS (INSERT INTO a_parent (note) VALUES ('live') RETURNING id)
                INSERT INTO z_child (parent_id) SELECT id FROM p;" >/dev/null 2>&1 || true
        done
    ) &
    WRITER_PID=$!
    run_backup consistency "${dir}" "${config}" --network "${NETWORK}" \
        -e DBBACKUP_USER=root -e DBBACKUP_GROUP=root
    stop_pid "${WRITER_PID}"
    WRITER_PID=""
    dump="$(check_artifact "${dir}" "0:0")"
    if ! restore_postgres "${dump}"; then
        echo "::warning title=db-backup v5 consistency::A backup taken during writes did not restore with intact foreign keys. v5 dumps PostgreSQL tables without a snapshot transaction."
        die "consistency scenario FAILED"
    fi
    docker rm -f "${PG_SOURCE}" "${PG_RESTORE}" >/dev/null
    log_info "v5 consistency scenario PASSED"
}

run_sqlite_scenario() {
    log_info "=== v5 SQLite: root, read-only mount, live WAL, BLOB ==="
    local src="${WORK_DIR}/sqlite_src" dir="${WORK_DIR}/sqlite" config="${WORK_DIR}/sqlite.yml"
    local restored="${WORK_DIR}/restored.db" dump blob attempts=0
    mkdir -p "${src}" "${dir}"
    blob="$(openssl rand -hex 128 | tr '[:lower:]' '[:upper:]')"
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
    run_backup sqlite "${dir}" "${config}" --network none --memory 1024m --pids-limit 100 \
        --security-opt no-new-privileges:true -e DBBACKUP_USER=root -e DBBACKUP_GROUP=root \
        -v "${src}:/db:ro"
    dump="$(check_artifact "${dir}" "0:0")"
    sqlite3 -bail "${restored}" <"${dump}" || die "SQLite dump did not load"
    [ "$(sqlite3 "${restored}" 'PRAGMA integrity_check;')" = ok ] || die "SQLite integrity_check failed"
    [ "$(sqlite3 "${restored}" "SELECT count(*) FROM restore_sentinel WHERE value = '${SENTINEL}';")" = 1 ] ||
        die "SQLite sentinel missing after restore"
    [ "$(sqlite3 "${restored}" 'SELECT hex(blob) FROM resource WHERE id = 1;')" = "${blob}" ] ||
        die "SQLite BLOB changed after restore"
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
