#!/usr/bin/env bash
# Do not trust v4's exit code alone: it can report success without a dump.
set -Eeuo pipefail
umask 077

fail() {
    printf 'ERROR: TREK backup: %s\n' "${1}" >&2
    exit 1
}

case "${DEFAULT_ENCRYPT_PASSPHRASE:-}" in
"" | GENERATE | CHANGE_ME) fail "a populated encryption passphrase is required" ;;
*) ;;
esac

work="$(mktemp -d "${TMPDIR:-/tmp}/trek-backup.XXXXXX")"
cleanup() {
    rm -f -- "${work}/started" "${work}/outputs" "${work}/restored.sqlite3"
    # GnuPG owns files beneath this private, per-run temporary directory.
    rm -rf -- "${work}/gnupg"
    rmdir -- "${work}"
}
trap cleanup EXIT
trap 'printf "ERROR: TREK backup or verification command failed\n" >&2' ERR
touch "${work}/started"

(
    # v4 creates SQLite scratch as root, then reads it as the backup user.
    # Its private temporary directory protects that intermediate file.
    umask 022
    timeout --signal=TERM --kill-after=10s 300s backup01-now now
)

find /backup -type f -newer "${work}/started" -print >"${work}/outputs"
dumps=()
checksums=()
while IFS= read -r output; do
    if [[ "${output}" =~ /sqlite3_travel_[^/]+\.sqlite3\.zst\.gpg$ ]]; then
        dumps+=("${output}")
    elif [[ "${output}" =~ /sqlite3_travel_[^/]+\.sqlite3\.zst\.gpg\.sha1$ ]]; then
        checksums+=("${output}")
    fi
done <"${work}/outputs"
[[ ${#dumps[@]} -eq 1 && ${#checksums[@]} -eq 1 ]] ||
    fail "expected exactly one new encrypted dump and one SHA1 sidecar"
dump="${dumps[0]}"
[[ "${checksums[0]}" == "${dump}.sha1" && -s "${dump}" ]] ||
    fail "dump and checksum do not form a nonempty output pair"
output_count="$(wc -l <"${work}/outputs")"
[[ "${output_count}" -eq 2 ]] ||
    fail "unexpected output files; inspect for incomplete or unencrypted backups"

(
    cd "$(dirname "${dump}")"
    sha1sum --check "$(basename "${dump}").sha1"
)
mkdir -m 700 "${work}/gnupg"
printf '%s\n' "${DEFAULT_ENCRYPT_PASSPHRASE}" |
    gpg --batch --homedir "${work}/gnupg" --pinentry-mode loopback \
        --passphrase-fd 0 --decrypt "${dump}" |
    zstd --decompress --stdout >"${work}/restored.sqlite3"
integrity="$(sqlite3 "${work}/restored.sqlite3" 'PRAGMA quick_check;')"
[[ "${integrity}" == "ok" ]] ||
    fail "restored SQLite integrity check failed"
tables="$(sqlite3 "${work}/restored.sqlite3" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('users','trips');")"
[[ "${tables}" == "2" ]] ||
    fail "restored database is missing TREK tables"

printf '%s\n' 'TREK encrypted backup verified: SHA1, GPG, ZSTD, SQLite integrity and schema.'
