#!/usr/bin/env bats
# Unit tests for the dccd-all alias function.

setup() {
  load '../helpers/common'

  TEST_ROOT="$(mktemp -d "${BATS_TMPDIR}/dccd-test.XXXXXX")"
  BASH_ARGS_FILE="${TEST_ROOT}/bash.args"

  source "${REPO_ROOT}/scripts/aliases.sh"
  APPS_DIR="/test/apps"
  DCCD_MODE=(-S "unit-server")
  unset DCCD_CHECK_BACKUPS

  bash() {
    printf '%s\n' "$@" >"${BASH_ARGS_FILE}"
    return 0
  }
}

teardown() {
  unset -f bash
  rm -rf "${TEST_ROOT}"
}

@test "dccd_all: passes -B to dccd.sh by default" {
  run dccd_all

  assert_success
  run cat "${BASH_ARGS_FILE}"
  assert_success
  assert_output $'/test/apps/scripts/dccd.sh\n-d\n/test/apps\n-k\n/test/apps/age.key\n-x\nshared\n-S\nunit-server\n-B\n-f'
}

@test "dccd_all: omits -B when DCCD_CHECK_BACKUPS is 0" {
  DCCD_CHECK_BACKUPS=0

  run dccd_all

  assert_success
  run cat "${BASH_ARGS_FILE}"
  assert_success
  assert_output $'/test/apps/scripts/dccd.sh\n-d\n/test/apps\n-k\n/test/apps/age.key\n-x\nshared\n-S\nunit-server\n-f'
}

@test "dccd_all: returns 2 for an invalid DCCD_CHECK_BACKUPS value" {
  DCCD_CHECK_BACKUPS=invalid

  run dccd_all

  assert_failure 2
  assert_output "ERROR: DCCD_CHECK_BACKUPS must be 1/0, true/false, or yes/no."
  assert_file_not_exists "${BASH_ARGS_FILE}"
}
