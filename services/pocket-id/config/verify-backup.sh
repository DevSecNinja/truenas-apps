#!/usr/bin/env bash
set -euo pipefail
upstream_umask=$(umask)
umask 077

fail() {
    printf 'ERROR: Pocket ID backup: %s\n' "$*" >&2
    exit 1
}

[[ "${DBBACKUP_USER:-}" == pocketbackup && "${DBBACKUP_GROUP:-}" == pocketbackup ]] ||
    fail "unexpected backup identity"
as_backup=(sudo -Eu "${DBBACKUP_USER}")
backup_uid=$(id -u "${DBBACKUP_USER}")
backup_gid=$(id -g "${DBBACKUP_USER}")
[[ "${backup_uid}" == 3133 && "${backup_gid}" == 3133 ]] ||
    fail "backup identity must be 3133:3133"
[[ "${DB01_HOST:-}" == /pocket-id-data/pocket-id.db ]] || fail "unexpected source path"
[[ "${DEFAULT_ENCRYPT:-}" == TRUE && -n "${DEFAULT_ENCRYPT_PASSPHRASE:-}" ]] ||
    fail "encryption and a passphrase are required"
[[ "${DEFAULT_COMPRESSION:-}" == ZSTD && "${DEFAULT_CHECKSUM:-}" == SHA1 ]] ||
    fail "ZSTD and SHA1 are required"
[[ "${DEFAULT_CLEANUP_TIME:-}" == 2880 ]] || fail "48-hour retention is required"

for tool in timeout flock sqlite3 gpg zstd sha1sum stat; do
    command -v "${tool}" >/dev/null || fail "missing required tool: ${tool}"
done

# Serialize the existing one-shot job, including output verification.
exec 9>/backup/.pocket-id-backup.lock
flock -n 9 || fail "another backup is already running"
work=$(mktemp -d)
trap 'rm -rf -- "${work}"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
chown "${DBBACKUP_USER}:${DBBACKUP_GROUP}" "${work}"

[[ -f "${DB01_HOST}" && ! -L "${DB01_HOST}" ]] || fail "database is missing or is a symlink"
# A read-only WAL reader needs the live writer's readable WAL/SHM files.
# Check the actual SQLite connection, not just file existence; never use immutable.
source_version=$("${as_backup[@]}" sqlite3 -batch -bail -readonly -cmd '.timeout 5000' \
    "${DB01_HOST}" 'SELECT version FROM schema_migrations WHERE dirty=0;') ||
    fail "source is not initialized/readable; keep the healthy writer and its WAL/SHM available"
[[ "${source_version}" =~ ^[0-9]+$ ]] || fail "source migration state is not ready"

shopt -s nullglob
declare -A previous=()
for file in /backup/sqlite3_pocket-id_*; do
    previous["${file}"]=1
done

status=0
# The upstream root-created SQLite scratch is read by pocketbackup. Preserve
# its original umask; our private verification scratch still uses 077.
(
    umask "${upstream_umask}"
    backup01-now now
) >"${work}/job.log" 2>&1 || status=$?
cat "${work}/job.log"
[[ "${status}" == 0 ]] || fail "upstream job exited ${status}"
[[ "$(grep -c 'Dumping sqlite3 database:' "${work}/job.log" || true)" == 1 ]] ||
    fail "expected exactly one dump"
[[ "$(grep -c 'Backup 01 routines finish time: .* with exit code 0' "${work}/job.log" || true)" == 1 ]] ||
    fail "expected exactly one successful upstream completion"
if grep -Eq 'reported errors|Skipping encryption|Skipping Checksum|Encryption failed|SQLite3 backup failed' "${work}/job.log"; then
    fail "upstream reported an operation failure"
fi

new_files=()
for file in /backup/sqlite3_pocket-id_*; do
    [[ -n "${previous[${file}]:-}" ]] || new_files+=("${file}")
done
[[ "${#new_files[@]}" == 2 ]] || fail "expected exactly one new encrypted/checksum pair"
cipher=
for file in "${new_files[@]}"; do
    [[ -f "${file}" && ! -L "${file}" ]] || fail "output is not a regular file"
    file_mode=$(stat -c '%u:%g:%a' "${file}")
    [[ "${file_mode}" == 3133:3133:600 ]] ||
        fail "output ownership or permissions are incorrect"
    case "${file}" in
    *.sqlite3.zst.gpg) cipher=${file} ;;
    *.sqlite3.zst.gpg.sha1) ;;
    *) fail "unexpected output format" ;;
    esac
done
[[ -n "${cipher}" && -s "${cipher}" && -f "${cipher}.sha1" ]] ||
    fail "encrypted output or checksum is missing"
directory_mode=$(stat -c '%u:%g:%a' /backup)
[[ "${directory_mode}" == 3133:3133:700 ]] ||
    fail "backup directory must be private"
name=${cipher##*/}
[[ "${name}" =~ ^sqlite3_pocket-id_[0-9]{8}-[0-9]{6}\.sqlite3\.zst\.gpg$ ]] ||
    fail "unexpected encrypted artifact name"
for file in "${new_files[@]}"; do
    [[ "${file}" == "${cipher}" || "${file}" == "${cipher}.sha1" ]] ||
        fail "outputs do not form one matching pair"
done
checksum=$(cat "${cipher}.sha1")
[[ "${checksum}" =~ ^[a-fA-F0-9]{40}\ \ ${name//./\\.}$ ]] ||
    fail "checksum must name only this encrypted artifact"
(
    cd /backup
    "${as_backup[@]}" sha1sum -c "${name}.sha1"
) || fail "encrypted artifact checksum failed"

"${as_backup[@]}" mkdir "${work}/gnupg"
printf '%s\n' "${DEFAULT_ENCRYPT_PASSPHRASE}" |
    "${as_backup[@]}" gpg --no-options --homedir "${work}/gnupg" --batch --no-tty \
        --pinentry-mode loopback --passphrase-fd 0 \
        --output "${work}/snapshot.zst" --decrypt "${cipher}" 2>"${work}/decrypt.log" ||
    fail "encrypted artifact cannot be decrypted"
"${as_backup[@]}" zstd -q -d "${work}/snapshot.zst" -o "${work}/snapshot.db" ||
    fail "decrypted artifact is not valid ZSTD"
integrity=$("${as_backup[@]}" sqlite3 -batch -bail "${work}/snapshot.db" 'PRAGMA integrity_check;') ||
    fail "restored SQLite integrity query failed"
[[ "${integrity}" == ok ]] ||
    fail "restored SQLite integrity check failed"
foreign_keys=$("${as_backup[@]}" sqlite3 -batch -bail "${work}/snapshot.db" 'PRAGMA foreign_key_check;') ||
    fail "restored SQLite foreign-key query failed"
[[ -z "${foreign_keys}" ]] ||
    fail "restored SQLite foreign-key check failed"
restored_version=$("${as_backup[@]}" sqlite3 -batch -bail "${work}/snapshot.db" \
    'SELECT version FROM schema_migrations WHERE dirty=0;') || fail "restored migration query failed"
[[ "${restored_version}" == "${source_version}" ]] ||
    fail "restored migration version differs"
key_count=$("${as_backup[@]}" sqlite3 -batch -bail "${work}/snapshot.db" \
    "SELECT count(*) FROM kv WHERE key IN ('jwt_private_key.json','session_key.json') AND length(value)>0;") ||
    fail "restored signing/session key query failed"
[[ "${key_count}" == 2 ]] ||
    fail "restored signing/session keys are missing"
printf 'Pocket ID backup verified: one GPG/ZSTD/SHA1 snapshot, SQLite integrity and keys present\n'
