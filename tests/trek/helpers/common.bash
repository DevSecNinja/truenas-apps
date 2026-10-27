#!/usr/bin/env bash
# Offline helpers: deliberately do not auto-download missing BATS libraries.

TREK_HELPER_DIR="${BASH_SOURCE[0]%/*}"
TREK_REPO_ROOT="$(cd "${TREK_HELPER_DIR}/../../.." && pwd)"
load "${TREK_REPO_ROOT}/tests/libs/bats-support/load"
load "${TREK_REPO_ROOT}/tests/libs/bats-assert/load"
load "${TREK_REPO_ROOT}/tests/libs/bats-file/load"

trek_setup_file() {
  if ((BASH_VERSINFO[0] < 3)); then
    printf '%s\n' 'TREK backup tests require Bash 3+.' >&2
    return 1
  fi
}

trek_setup() {
  TEST_ROOT="$(mktemp -d "${BATS_TMPDIR}/dccd-test.XXXXXX")"
  ORIGINAL_PATH="${PATH}"
  MOCK_BIN="${TEST_ROOT}/bin"
  MOCK_LOG="${TEST_ROOT}/log"
  BACKUP_ROOT="${TEST_ROOT}/backup files"
  WORK_ROOT="${TEST_ROOT}/work"
  FIXTURE_DIR="${TREK_REPO_ROOT}/tests/trek/fixtures"
  TREK_COMPOSE="${TREK_REPO_ROOT}/services/trek/compose.yaml"
  TREK_BACKUP="${TREK_REPO_ROOT}/services/trek/config/backup.sh"
  REAL_FIND="$(command -v find)"
  REAL_TOUCH="$(command -v touch)"
  REAL_SH="$(command -v sh)"
  mkdir -p "${MOCK_BIN}" "${MOCK_LOG}" "${BACKUP_ROOT}" "${WORK_ROOT}"
  cp "${TREK_REPO_ROOT}/tests/trek/helpers/mock-command.bash" "${TEST_ROOT}/mock-command"
  chmod +x "${TEST_ROOT}/mock-command"
  export MOCK_BIN MOCK_LOG BACKUP_ROOT WORK_ROOT FIXTURE_DIR REAL_FIND REAL_TOUCH
  # Prepend mocks only in the child under test, not in BATS's own helper processes.
  export BACKUP_SCENARIO=success TREK_MOCK_CONTEXT=backup
  export DEFAULT_ENCRYPT_PASSPHRASE=trek-test-only-passphrase
  # Fail rather than accidentally contacting a daemon, network, or secret store.
  trek_mock docker curl wget git sudo sops op dig logger
}

trek_teardown() {
  export PATH="${ORIGINAL_PATH}"
  rm -rf -- "${TEST_ROOT}"
}

trek_mock() {
  local command_name
  for command_name in "$@"; do
    ln -s "${TEST_ROOT}/mock-command" "${MOCK_BIN}/${command_name}"
  done
}

trek_backup_setup() {
  trek_setup
  trek_mock timeout backup01-now find touch sha1sum gpg zstd sqlite3
  # Old outputs must neither count as new nor be removed by cleanup.
  cp "${FIXTURE_DIR}/dump.txt" "${BACKUP_ROOT}/sqlite3_travel_old.sqlite3.zst.gpg"
  cp "${FIXTURE_DIR}/sidecar.txt" "${BACKUP_ROOT}/sqlite3_travel_old.sqlite3.zst.gpg.sha1"
  "${REAL_TOUCH}" -t 199901010000 "${BACKUP_ROOT}"/*
}

run_backup() {
  # No inherited startup hooks, credentials, GNUPGHOME, or real output paths.
  local -a passphrase=()
  if [[ "${DEFAULT_ENCRYPT_PASSPHRASE+x}" == x ]]; then
    passphrase=("DEFAULT_ENCRYPT_PASSPHRASE=${DEFAULT_ENCRYPT_PASSPHRASE}")
  fi
  run env -i PATH="${MOCK_BIN}:${ORIGINAL_PATH}" HOME="${TEST_ROOT}" TMPDIR="${WORK_ROOT}" \
    MOCK_LOG="${MOCK_LOG}" BACKUP_ROOT="${BACKUP_ROOT}" WORK_ROOT="${WORK_ROOT}" \
    FIXTURE_DIR="${FIXTURE_DIR}" REAL_FIND="${REAL_FIND}" REAL_TOUCH="${REAL_TOUCH}" \
    TREK_MOCK_CONTEXT=backup BACKUP_SCENARIO="${BACKUP_SCENARIO}" \
    "${passphrase[@]}" "${BASH}" "${TREK_BACKUP}"
}

assert_called() {
  assert_file_exists "${MOCK_LOG}/${1}"
}

assert_not_called() {
  assert_file_not_exists "${MOCK_LOG}/${1}"
}

assert_backup_cleaned() {
  assert_dir_exists "${WORK_ROOT}"
  run "${REAL_FIND}" "${WORK_ROOT}" -mindepth 1 -print
  assert_success
  assert_output ""
  assert_file_exists "${BACKUP_ROOT}/sqlite3_travel_old.sqlite3.zst.gpg"
  assert_file_exists "${BACKUP_ROOT}/sqlite3_travel_old.sqlite3.zst.gpg.sha1"
}

assert_backup_rejected() {
  assert_failure
  refute_output --partial 'TREK encrypted backup verified:'
  refute_output --partial 'Unexpected TREK mock invocation:'
  assert_output --partial "${1}"
  assert_backup_cleaned
}

assert_compose_value() {
  run yq -r "${1}" "${TREK_COMPOSE}"
  assert_success
  assert_output "${2}"
}

run_trek_init() {
  local omitted="${1:-}" assignment
  local -a inputs=()
  for assignment in \
    'DOMAINNAME=example.invalid' \
    'ENCRYPTION_KEY=0000000000000000000000000000000000000000000000000000000000000000' \
    'DB_ENC_PASSPHRASE=trek-test-only-passphrase' \
    'OIDC_CLIENT_ID=trek-test-client' \
    'OIDC_CLIENT_SECRET=trek-test-only-client-secret'; do
    if [[ "${assignment%%=*}" != "${omitted}" ]]; then
      inputs+=("${assignment}")
    elif (($# == 2)); then
      inputs+=("${omitted}=${2}")
    fi
  done
  run env -i PATH="${MOCK_BIN}:${ORIGINAL_PATH}" HOME="${TEST_ROOT}" \
    MOCK_LOG="${MOCK_LOG}" REAL_TOUCH="${REAL_TOUCH}" TREK_MOCK_CONTEXT=init \
    "${inputs[@]}" "${REAL_SH}" -ec "${TREK_INIT_COMMAND//\$\$/\$}"
}

assert_init_untouched() {
  assert_not_called mkdir
  assert_not_called chown
  assert_not_called chmod
}

run_backup_identity() {
  run env -i PATH="${MOCK_BIN}:${ORIGINAL_PATH}" HOME="${TEST_ROOT}" \
    MOCK_LOG="${MOCK_LOG}" REAL_TOUCH="${REAL_TOUCH}" TREK_MOCK_CONTEXT=identity \
    IDENTITY_EXISTS="${1}" IDENTITY_UID="${2}" IDENTITY_GID="${3}" \
    "${REAL_SH}" -ec "${TREK_IDENTITY_COMMAND//\$\$/\$}"
}

assert_no_trek_yaml() {
  assert_file_exists "${1}"
  # Recursive descent including mapping keys, ignoring YAML comments.
  run yq -r '... | select(tag == "!!str") |
    select(test("(?i)(^|[^a-z0-9])trek([^a-z0-9]|$)"))' "${1}"
  assert_success
  assert_output ""
}

active_trek_conf() {
  # Only Unbound .conf files, never env/secret files.
  local active
  active="$(sed 's/#.*$//' "${1}")" || return
  grep -niE '(^|[^a-z0-9])trek([^a-z0-9]|$)' <<<"${active}"
}
