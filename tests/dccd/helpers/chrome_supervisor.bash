#!/usr/bin/env bash
# Offline setup for Chrome supervisor and Compose contract tests.

chrome_supervisor_setup_file() {
  local root library
  root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  # Check before loading common.bash so its auto-installer cannot go online.
  for library in bats-support bats-assert bats-file; do
    if [[ ! -f "${root}/tests/libs/${library}/load.bash" ]]; then
      printf 'Missing tests/libs/%s; provision with mise exec -- bash tests/setup_libs.sh before running offline tests\n' "${library}" >&2
      return 1
    fi
  done
}

chrome_supervisor_setup() {
  bats_require_minimum_version 1.5.0
  load '../helpers/common'
  # Reuse the assertion libraries, but do not source dccd.sh or set log globals.
  TEST_TMPDIR="$(mktemp -d "${BATS_TMPDIR}/dccd-test.XXXXXX")"
  MOCK_BIN="${TEST_TMPDIR}/bin"
  mkdir -p "${MOCK_BIN}"
  CHROME_SUPERVISOR_ORIGINAL_PATH="${PATH}"
  export TEST_TMPDIR MOCK_BIN
  export PATH="${MOCK_BIN}:${PATH}" LC_ALL=C
}

chrome_supervisor_teardown() {
  export PATH="${CHROME_SUPERVISOR_ORIGINAL_PATH}"
  rm -rf "${TEST_TMPDIR}"
}

# bats-assert's output matching also provides useful diffs for BATS' separate
# stderr capture without merging the streams back together.
assert_stderr() {
  # shellcheck disable=SC2034
  local output="${stderr}"
  assert_output "$@"
}

refute_stderr() {
  # shellcheck disable=SC2034
  local output="${stderr}"
  refute_output "$@"
}
