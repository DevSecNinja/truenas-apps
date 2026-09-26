#!/usr/bin/env bash
# Thin wrapper around the existing framework; no runtime or template engine.

diagnostics_require_helpers() {
  bats_require_minimum_version 1.5.0
  local root library
  root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  for library in bats-support bats-assert bats-file; do
    if [[ ! -f "${root}/tests/libs/${library}/load.bash" ]]; then
      printf 'Missing tests/libs/%s; provision test helpers before running offline tests\n' "${library}" >&2
      return 1
    fi
  done
}

diagnostics_setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  common_setup
  create_default_mocks
  export LOG_COLOR=never LOG_JOURNAL=never LOG_FORMAT=text LOG_LEVEL=INFO
  export LOG_TO_STDIO=1 LOG_TIMESTAMP=regression
  unset LOG_FILE LOG_FILE_MAX_BYTES LOG_FILE_TTL_DAYS
  # shellcheck disable=SC2034
  _CONFIG_HASH_ENV_FILE=''
}

# Use bats-assert's matchers without merging BATS' separate stdout/stderr.
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
