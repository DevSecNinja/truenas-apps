#!/usr/bin/env bash
# Offline guard tests only: mocked SQLite/GPG/ZSTD are not restore/crypto evidence.

POCKET_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

pocket_require_helpers() {
  bats_require_minimum_version 1.5.0
  local library tool
  for library in bats-support bats-assert bats-file; do
    if [[ ! -f "${POCKET_REPO_ROOT}/tests/libs/${library}/load.bash" ]]; then
      printf 'Missing tests/libs/%s; provision helpers before running offline tests\n' "${library}" >&2
      return 1
    fi
  done
  if ((BASH_VERSINFO[0] < 4)); then
    printf 'verify-backup.sh requires Bash 4 or newer\n' >&2
    return 1
  fi
  for tool in sha1sum sed bash; do
    command -v "${tool}" >/dev/null || return 1
  done
}

pocket_setup() {
  local library tool backup_literal source_literal
  for library in bats-support bats-assert bats-file; do
    load "${POCKET_REPO_ROOT}/tests/libs/${library}/load"
  done
  # Reuse stdout/stderr assertions, not dccd's source/setup or auto-download path.
  load "${POCKET_REPO_ROOT}/tests/dccd/helpers/diagnostics"
  ORIGINAL_PATH="${PATH}"
  ORIGINAL_TMPDIR="${TMPDIR-}"
  ORIGINAL_TMPDIR_SET="${TMPDIR+x}"
  TEST_ROOT="$(mktemp -d "${BATS_TMPDIR}/dccd-test.XXXXXX")"
  MOCK_BIN="${TEST_ROOT}/bin"
  MOCK_LOG="${TEST_ROOT}/calls"
  POCKET_BACKUP="${TEST_ROOT}/backup"
  POCKET_SOURCE="${TEST_ROOT}/source"
  VERIFY_SCRIPT="${TEST_ROOT}/verify-backup.sh"
  export MOCK_LOG POCKET_BACKUP POCKET_SOURCE
  export TMPDIR="${TEST_ROOT}/scratch"
  mkdir -p "${MOCK_BIN}" "${MOCK_LOG}" "${POCKET_BACKUP}" "${POCKET_SOURCE}" "${TMPDIR}"
  touch "${POCKET_SOURCE}/pocket-id.db"
  for tool in id sudo chown timeout flock backup01-now sqlite3 gpg zstd stat; do
    cp "${BATS_TEST_DIRNAME}/helpers/mock-command.bash" "${MOCK_BIN}/${tool}"
    chmod +x "${MOCK_BIN}/${tool}"
  done
  # Only the two mount literals change. Escape for shell AND sed, including
  # BATS_TMPDIR paths containing spaces. Never change SQL or guard expressions.
  backup_literal="$(printf '%q' "${POCKET_BACKUP}" | sed 's/[\\&|]/\\&/g')"
  source_literal="$(printf '%q' "${POCKET_SOURCE}" | sed 's/[\\&|]/\\&/g')"
  sed -e "s|/backup|${backup_literal}|g" \
    -e "s|/pocket-id-data|${source_literal}|g" \
    "${POCKET_REPO_ROOT}/services/pocket-id/config/verify-backup.sh" >"${VERIFY_SCRIPT}"
  export PATH="${MOCK_BIN}:${ORIGINAL_PATH}"
  export DBBACKUP_USER=pocketbackup DBBACKUP_GROUP=pocketbackup
  export DB01_HOST="${POCKET_SOURCE}/pocket-id.db"
  export DEFAULT_ENCRYPT=TRUE DEFAULT_ENCRYPT_PASSPHRASE=synthetic-unit-test-only
  export DEFAULT_COMPRESSION=ZSTD DEFAULT_CHECKSUM=SHA1 DEFAULT_CLEANUP_TIME=2880
  export POCKET_ARTIFACT=sqlite3_pocket-id_20261029-195126.sqlite3.zst.gpg
  export POCKET_EXTRA_ARTIFACT=sqlite3_pocket-id_20261029-195127.sqlite3.zst.gpg
  export POCKET_CASE=success POCKET_LOG_ERROR='reported errors'
}

pocket_teardown() {
  export PATH="${ORIGINAL_PATH}"
  if [[ "${ORIGINAL_TMPDIR_SET}" == x ]]; then
    export TMPDIR="${ORIGINAL_TMPDIR}"
  else
    unset TMPDIR
  fi
  [[ -z "${TEST_ROOT:-}" ]] || rm -rf -- "${TEST_ROOT}"
}

run_verify() {
  run --separate-stderr env LC_ALL=C bash "${VERIFY_SCRIPT}"
}

run_verify_with_umask() {
  # Set the caller's mask in an isolated shell, not in the temporary script copy.
  # shellcheck disable=SC2016
  run --separate-stderr env LC_ALL=C bash -c \
    'umask "$1"; exec bash "$2"' -- "$1" "${VERIFY_SCRIPT}"
}

assert_recorded_umask() {
  assert_file_exists "${MOCK_LOG}/${1}.umask"
  run cat "${MOCK_LOG}/${1}.umask"
  assert_success
  assert_output "$2"
}

assert_verification_umasks_private() {
  local stage private
  private="$(
    umask 077
    umask
  )"
  # chown observes the scratch-setup context; sudo.mkdir observes the GNUPG
  # directory creation. Crypto/SQL mocks observe the later verification context.
  for stage in chown sudo.mkdir gpg zstd sqlite3; do
    assert_recorded_umask "${stage}" "${private}"
  done
}

assert_guard_failure() {
  assert_failure
  assert_stderr --partial 'ERROR: Pocket ID backup:'
  assert_stderr --partial "$1"
  refute_output --partial 'Pocket ID backup verified:'
  refute_output --partial "${DEFAULT_ENCRYPT_PASSPHRASE}"
  refute_stderr --partial "${DEFAULT_ENCRYPT_PASSPHRASE}"
}
