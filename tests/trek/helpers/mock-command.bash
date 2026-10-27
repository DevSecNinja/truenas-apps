#!/usr/bin/env bash
# PATH dispatcher. Mock protocol violations use 97, distinct from injected errors.
# Validators check arguments/data flow, not real cryptography or SQLite behavior.
set -euo pipefail

command_name="${0##*/}"
bad_call() {
  printf 'Unexpected TREK mock invocation: %s\n' "${command_name}" >&2
  exit 97
}

"${REAL_TOUCH}" "${MOCK_LOG}/${command_name}"

case "${TREK_MOCK_CONTEXT}:${command_name}" in
init:mkdir)
  [[ "$*" == '-p /data/app /data/uploads' ]] || bad_call
  exit 0
  ;;
init:chown)
  [[ "$*" == '-R 3134:3134 /data/app /data/uploads' ]] || bad_call
  exit 0
  ;;
init:chmod)
  case "$*" in
  '-R u=rwX,g=,o= /data/app /data/uploads' | '700 /data') exit 0 ;;
  *) bad_call ;;
  esac
  ;;
identity:grep)
  [[ "$*" == "-q ^trekbackup: /etc/group" ]] || bad_call
  [[ "${IDENTITY_EXISTS}" == true ]]
  exit
  ;;
identity:id)
  case "$*" in
  trekbackup) [[ "${IDENTITY_EXISTS}" == true ]] ;;
  '-u trekbackup') printf '%s\n' "${IDENTITY_UID}" ;;
  '-g trekbackup') printf '%s\n' "${IDENTITY_GID}" ;;
  *) bad_call ;;
  esac
  exit
  ;;
identity:addgroup)
  [[ "$*" == '-g 3134 trekbackup' ]] || bad_call
  exit 0
  ;;
identity:adduser)
  [[ "$*" == '-D -H -u 3134 -G trekbackup trekbackup' ]] || bad_call
  exit 0
  ;;
*) ;;
esac

[[ "${TREK_MOCK_CONTEXT}" == backup ]] || bad_call
dump="${BACKUP_ROOT}/sqlite3_travel_current.sqlite3.zst.gpg"

case "${command_name}" in
timeout)
  [[ $# == 5 && "$1" == --signal=TERM && "$2" == --kill-after=10s &&
    "$3" == 300s && "$4" == backup01-now && "$5" == now ]] || bad_call
  if [[ "${BACKUP_SCENARIO}" == timeout ]]; then
    printf '%s\n' 'mock upstream timed out' >&2
    exit 124
  fi
  shift 3
  exec "$@"
  ;;
touch)
  [[ $# == 1 && "$1" == "${WORK_ROOT}/"*/started ]] || bad_call
  # Deterministic -newer comparisons without sleeps or filesystem clock races.
  exec "${REAL_TOUCH}" -t 200001010000 "$1"
  ;;
find)
  [[ $# == 6 && "$1" == /backup && "$2" == -type && "$3" == f &&
    "$4" == -newer && "$5" == "${WORK_ROOT}/"*/started && "$6" == -print ]] || bad_call
  shift
  # The only path substitution: execute the unmodified production script.
  exec "${REAL_FIND}" "${BACKUP_ROOT}" "$@"
  ;;
backup01-now)
  [[ "$*" == now ]] || bad_call
  current_umask="$(umask)"
  [[ "${current_umask}" == 0022 ]] || bad_call
  "${REAL_TOUCH}" "${MOCK_LOG}/upstream-umask-022"
  case "${BACKUP_SCENARIO}" in
  no-dump) exit 0 ;;
  upstream-failure) exit 23 ;;
  empty-dump) "${REAL_TOUCH}" "${dump}" ;;
  *) cp "${FIXTURE_DIR}/dump.txt" "${dump}" ;;
  esac
  case "${BACKUP_SCENARIO}" in
  missing-sha1) ;;
  wrong-sidecar-name)
    cp "${FIXTURE_DIR}/sidecar.txt" "${BACKUP_ROOT}/sqlite3_travel_other.sqlite3.zst.gpg.sha1"
    ;;
  *) cp "${FIXTURE_DIR}/sidecar.txt" "${dump}.sha1" ;;
  esac
  case "${BACKUP_SCENARIO}" in
  multiple-dumps | multiple-pairs)
    cp "${dump}" "${BACKUP_ROOT}/sqlite3_travel_second.sqlite3.zst.gpg"
    if [[ "${BACKUP_SCENARIO}" == multiple-pairs ]]; then
      cp "${dump}.sha1" "${BACKUP_ROOT}/sqlite3_travel_second.sqlite3.zst.gpg.sha1"
    fi
    ;;
  multiple-sidecars)
    cp "${dump}.sha1" "${BACKUP_ROOT}/sqlite3_travel_second.sqlite3.zst.gpg.sha1"
    ;;
  plaintext) cp "${FIXTURE_DIR}/dump.txt" "${BACKUP_ROOT}/sqlite3_travel_current.sqlite3" ;;
  compressed-plaintext) cp "${FIXTURE_DIR}/dump.txt" "${BACKUP_ROOT}/sqlite3_travel_current.sqlite3.zst" ;;
  unexpected-output) cp "${FIXTURE_DIR}/dump.txt" "${BACKUP_ROOT}/partial.tmp" ;;
  *) ;;
  esac
  ;;
sha1sum)
  sidecar_content="$(cat "${dump}.sha1")"
  [[ "$*" == '--check sqlite3_travel_current.sqlite3.zst.gpg.sha1' &&
    "${PWD}" == "${BACKUP_ROOT}" &&
    "${sidecar_content}" == 'test-only SHA1 sidecar' ]] || bad_call
  if [[ "${BACKUP_SCENARIO}" == checksum-failure ]]; then
    printf '%s\n' 'mock SHA1 mismatch' >&2
    exit 31
  fi
  printf '%s\n' 'sqlite3_travel_current.sqlite3.zst.gpg: OK'
  ;;
gpg)
  # Nine arguments; never accept a passphrase on the command line.
  [[ $# == 9 && "$1" == --batch && "$2" == --homedir &&
    "$3" == "${WORK_ROOT}/"*/gnupg && -d "$3" &&
    "$4" == --pinentry-mode && "$5" == loopback &&
    "$6" == --passphrase-fd && "$7" == 0 &&
    "$8" == --decrypt && "$9" == "${dump}" ]] || bad_call
  passphrase_input="$(cat)"
  dump_content="$(cat "${dump}")"
  current_umask="$(umask)"
  private_home="$("${REAL_FIND}" "$3" -prune -perm 0700 -print)"
  [[ "${passphrase_input}" == "${DEFAULT_ENCRYPT_PASSPHRASE}" &&
    "${dump_content}" == 'test-only encrypted dump' ]] || bad_call
  [[ "${current_umask}" == 0077 && "${private_home}" == "$3" ]] || bad_call
  "${REAL_TOUCH}" "${MOCK_LOG}/verification-umask-077"
  # Exercise removal of nonempty GnuPG state on success AND failure.
  mkdir -p "$3/private-keys-v1.d"
  cp "${FIXTURE_DIR}/dump.txt" "$3/private-keys-v1.d/test-state"
  printf '%s\n' 'test-only zstd stream'
  if [[ "${BACKUP_SCENARIO}" == gpg-failure ]]; then
    printf '%s\n' 'mock GPG failure' >&2
    exit 32
  fi
  ;;
zstd)
  compressed_input="$(cat)"
  [[ "$*" == '--decompress --stdout' && "${compressed_input}" == 'test-only zstd stream' ]] || bad_call
  printf '%s\n' 'test-only restored SQLite'
  if [[ "${BACKUP_SCENARIO}" == zstd-failure ]]; then
    printf '%s\n' 'mock ZSTD failure' >&2
    exit 33
  fi
  ;;
sqlite3)
  [[ $# == 2 && "$1" == "${WORK_ROOT}/"*/restored.sqlite3 ]] || bad_call
  restored_content="$(cat "$1")"
  private_restored="$("${REAL_FIND}" "$1" -prune -perm 0600 -print)"
  [[ "${restored_content}" == 'test-only restored SQLite' && "${private_restored}" == "$1" ]] || bad_call
  case "$2" in
  'PRAGMA quick_check;')
    "${REAL_TOUCH}" "${MOCK_LOG}/sqlite-integrity"
    case "${BACKUP_SCENARIO}" in
    integrity-error) exit 34 ;;
    integrity-error-with-output)
      printf '%s\n' ok
      exit 34
      ;;
    integrity-failure) printf '%s\n' 'database disk image is malformed' ;;
    *) printf '%s\n' ok ;;
    esac
    ;;
  "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('users','trips');")
    "${REAL_TOUCH}" "${MOCK_LOG}/sqlite-schema"
    case "${BACKUP_SCENARIO}" in
    schema-error) exit 35 ;;
    schema-error-with-output)
      printf '%s\n' 2
      exit 35
      ;;
    schema-failure) printf '%s\n' 1 ;;
    *) printf '%s\n' 2 ;;
    esac
    ;;
  *) bad_call ;;
  esac
  ;;
*) bad_call ;;
esac
