#!/usr/bin/env bash
# Installed under each command name in the isolated PATH. No runtime/network.
set -euo pipefail

command_name=${0##*/}
touch "${MOCK_LOG}/${command_name}.called"
umask >"${MOCK_LOG}/${command_name}.umask"
unexpected() {
  printf 'Unexpected invocation of mock %s\n' "${command_name}" >&2
  exit 90
}

write_pair() {
  local name="$1"
  printf '%s\n' 'synthetic ciphertext; not encrypted data' >"${POCKET_BACKUP}/${name}"
  (cd "${POCKET_BACKUP}" && sha1sum "${name}" >"${name}.sha1")
}

case "${command_name}" in
id)
  [[ $# == 2 && $2 == pocketbackup && ($1 == -u || $1 == -g) ]] || unexpected
  printf '3133\n'
  ;;
sudo)
  [[ $# -ge 3 && $1 == -Eu && $2 == pocketbackup ]] || unexpected
  shift 2
  umask >"${MOCK_LOG}/sudo.${1}.umask"
  case "$1" in sqlite3 | sha1sum | mkdir | gpg | zstd) exec "$@" ;; *) unexpected ;; esac
  ;;
chown)
  [[ $# == 2 && $1 == pocketbackup:pocketbackup && $2 == "${TMPDIR}/"* ]] || unexpected
  ;;
flock)
  [[ "$*" == '-n 9' ]] || unexpected
  ;;
timeout)
  # The guard checks availability; actual lifecycle/locking is parent-tested.
  unexpected
  ;;
backup01-now)
  [[ "$*" == now ]] || unexpected
  if [[ "${POCKET_CASE}" != no-output ]]; then
    write_pair "${POCKET_ARTIFACT}"
    case "${POCKET_CASE}" in
    duplicate-pair) write_pair "${POCKET_EXTRA_ARTIFACT}" ;;
    bad-checksum) printf 'tampered ciphertext\n' >"${POCKET_BACKUP}/${POCKET_ARTIFACT}" ;;
    wrong-manifest-name)
      # Use a real digest but deliberately name a different artifact.
      digest="$(sha1sum "${POCKET_BACKUP}/${POCKET_ARTIFACT}")"
      printf '%s  other.sqlite3.zst.gpg\n' "${digest%% *}" >"${POCKET_BACKUP}/${POCKET_ARTIFACT}.sha1"
      ;;
    *) ;;
    esac
  fi
  if [[ "${POCKET_CASE}" != missing-dump ]]; then
    printf 'Dumping sqlite3 database: synthetic-source\n'
  fi
  if [[ "${POCKET_CASE}" == duplicate-dump ]]; then
    printf 'Dumping sqlite3 database: synthetic-source\n'
  fi
  if [[ "${POCKET_CASE}" != missing-completion ]]; then
    printf 'Backup 01 routines finish time: synthetic-time with exit code 0\n'
  fi
  if [[ "${POCKET_CASE}" == duplicate-completion ]]; then
    printf 'Backup 01 routines finish time: synthetic-time with exit code 0\n'
  fi
  if [[ "${POCKET_CASE}" == error-log ]]; then
    printf '%s\n' "${POCKET_LOG_ERROR}"
  fi
  if [[ "${POCKET_CASE}" == job-exit ]]; then exit 23; fi
  ;;
stat)
  [[ $# == 3 && $1 == -c && $2 == '%u:%g:%a' ]] || unexpected
  case "$3" in
  "${POCKET_BACKUP}")
    if [[ "${POCKET_CASE}" == directory-mode ]]; then
      printf '3133:3133:755\n'
    else
      printf '3133:3133:700\n'
    fi
    ;;
  "${POCKET_BACKUP}"/sqlite3_pocket-id_*)
    if [[ "${POCKET_CASE}" == output-mode ]]; then
      printf '3133:3133:644\n'
    else
      printf '3133:3133:600\n'
    fi
    ;;
  *) unexpected ;;
  esac
  ;;
gpg)
  output='' input='' passphrase_fd=''
  while (($#)); do
    case "$1" in
    --no-options | --batch | --no-tty) shift ;;
    --homedir)
      [[ $2 == "${TMPDIR}/"* && -d $2 ]] || unexpected
      shift 2
      ;;
    --pinentry-mode)
      [[ $2 == loopback ]] || unexpected
      shift 2
      ;;
    --passphrase-fd)
      passphrase_fd=$2
      shift 2
      ;;
    --output)
      output=$2
      shift 2
      ;;
    --decrypt)
      input=$2
      shift 2
      ;;
    *) unexpected ;;
    esac
  done
  [[ "${passphrase_fd}" == 0 && "${output}" == "${TMPDIR}/"* && "${input}" == "${POCKET_BACKUP}/"* ]] || unexpected
  IFS= read -r passphrase
  [[ "${passphrase}" == "${DEFAULT_ENCRYPT_PASSPHRASE}" ]] || unexpected
  unset passphrase
  if [[ "${POCKET_CASE}" == decrypt-fail ]]; then exit 41; fi
  cp "${input}" "${output}"
  ;;
zstd)
  [[ $# == 5 && $1 == -q && $2 == -d && $4 == -o ]] || unexpected
  [[ $3 == "${TMPDIR}/"* && $5 == "${TMPDIR}/"* ]] || unexpected
  if [[ "${POCKET_CASE}" == decompress-fail ]]; then exit 42; fi
  cp "$3" "$5"
  ;;
sqlite3)
  arguments=("$@")
  database=${arguments[$# - 2]}
  sql=${!#}
  if [[ "${database}" == "${DB01_HOST}" ]]; then
    [[ $# == 7 && $1 == -batch && $2 == -bail && $3 == -readonly &&
      $4 == -cmd && $5 == '.timeout 5000' &&
      "${sql}" == 'SELECT version FROM schema_migrations WHERE dirty=0;' ]] || unexpected
    touch "${MOCK_LOG}/source.called"
    if [[ "${POCKET_CASE}" == source-open ]]; then exit 31; fi
    if [[ "${POCKET_CASE}" != source-unready ]]; then printf '20261029\n'; fi
    exit 0
  fi
  [[ $# == 4 && $1 == -batch && $2 == -bail &&
    "${database}" == "${TMPDIR}/"* && -s "${database}" ]] || unexpected
  case "${sql}" in
  'PRAGMA integrity_check;')
    touch "${MOCK_LOG}/integrity.called"
    if [[ "${POCKET_CASE}" == integrity-sql-error ]]; then exit 43; fi
    if [[ "${POCKET_CASE}" == integrity-fail ]]; then printf 'synthetic corruption\n'; else printf 'ok\n'; fi
    ;;
  'PRAGMA foreign_key_check;')
    touch "${MOCK_LOG}/foreign-key.called"
    # Crucial regression: nonzero exit with EMPTY stdout must not mean success.
    if [[ "${POCKET_CASE}" == fk-sql-error ]]; then exit 44; fi
    if [[ "${POCKET_CASE}" == fk-violation ]]; then printf 'synthetic_table|2|parent|0\n'; fi
    ;;
  'SELECT version FROM schema_migrations WHERE dirty=0;')
    touch "${MOCK_LOG}/migration.called"
    if [[ "${POCKET_CASE}" == missing-schema ]]; then
      printf 'Error: no such table: schema_migrations\n' >&2
      exit 45
    fi
    if [[ "${POCKET_CASE}" == migration-mismatch ]]; then printf '20261030\n'; else printf '20261029\n'; fi
    ;;
  "SELECT count(*) FROM kv WHERE key IN ('jwt_private_key.json','session_key.json') AND length(value)>0;")
    touch "${MOCK_LOG}/keys.called"
    if [[ "${POCKET_CASE}" == missing-keys ]]; then printf '1\n'; else printf '2\n'; fi
    ;;
  *) unexpected ;;
  esac
  ;;
*) unexpected ;;
esac
