#!/usr/bin/env bats
# Offline integration coverage; helper libraries must already be bootstrapped.

load '../../libs/bats-support/load'
load '../../libs/bats-assert/load'
load '../../libs/bats-file/load'

bats_require_minimum_version 1.5.0

setup_file() {
  export VALIDATOR_SCRIPT
  VALIDATOR_SCRIPT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)/scripts/validate-server-apps.sh"
  assert_file_exists "${VALIDATOR_SCRIPT}"
}

setup() {
  TEST_TMPDIR="$(mktemp -d "${BATS_TMPDIR}/dccd-test.XXXXXX")"
  local mock_bin="${TEST_TMPDIR}/bin"
  mkdir -p "${mock_bin}" "${TEST_TMPDIR}/fixture cwd with spaces"
  cd "${TEST_TMPDIR}/fixture cwd with spaces"
  export FIXTURE_CWD="${PWD}"
  export MOCK_MISE_CALLED="${TEST_TMPDIR}/mise.called"
  export MOCK_YQ_STDOUT="" MOCK_MISE_STDERR="" MOCK_MISE_STATUS=0
  export LC_ALL=C
  export PATH="${mock_bin}:${PATH}"
  touch servers.yaml

  # This is the only external dependency mocked: never invoke real mise/yq.
  # Check individual arguments (not $*) so quoting regressions cannot pass.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'expected=(exec -- yq -r ".servers[].apps // [] | .[]" servers.yaml)' \
    'if [[ "$PWD" != "$FIXTURE_CWD" || "$#" -ne "${#expected[@]}" ]]; then' \
    '  printf "%s\n" "mock mise: unexpected cwd or argument count" >&2' \
    '  exit 97' \
    'fi' \
    'for arg in "${expected[@]}"; do' \
    '  if [[ "$1" != "$arg" ]]; then' \
    '    printf "mock mise: expected <%s>, got <%s>\n" "$arg" "$1" >&2' \
    '    exit 97' \
    '  fi' \
    '  shift' \
    'done' \
    'touch "${MOCK_MISE_CALLED}"' \
    'printf "%s" "${MOCK_YQ_STDOUT}"' \
    'printf "%s" "${MOCK_MISE_STDERR}" >&2' \
    'exit "${MOCK_MISE_STATUS}"' >"${mock_bin}/mise"
  chmod +x "${mock_bin}/mise"
}

teardown() {
  cd "${BATS_TEST_DIRNAME}"
  if [[ -n "${TEST_TMPDIR:-}" ]]; then
    rm -rf -- "${TEST_TMPDIR}"
  fi
}

run_validator() {
  rm -f -- "${MOCK_MISE_CALLED}"
  run --separate-stderr "$@" bash "${VALIDATOR_SCRIPT}"
  # Also proves the mock was called with the exact argv, even on empty input.
  assert_file_exists "${MOCK_MISE_CALLED}"
}

@test "validate_server_apps: accepts multiple apps and duplicate entries" {
  mkdir -p services/alpha services/beta
  MOCK_YQ_STDOUT=$'beta\nalpha\nbeta\nalpha\n'

  run_validator

  assert_success
  assert_output ""
  assert_equal "${stderr}" ""
}

@test "validate_server_apps: accepts an empty app list without a services directory" {
  assert_dir_not_exists services

  run_validator

  assert_success
  assert_output ""
  assert_equal "${stderr}" ""
}

@test "validate_server_apps: rejects a missing directory with the exact diagnostic" {
  mkdir services
  # An ordinary file must not satisfy the directory check.
  touch services/missing
  assert_file_exists services/missing
  MOCK_YQ_STDOUT=$'missing\n'

  run_validator

  assert_failure 1
  assert_output ""
  assert_equal "${stderr}" "ERROR: App 'missing' in servers.yaml has no services/missing/ directory"
}

@test "validate_server_apps: checks a missing directory after a valid sorted entry" {
  mkdir -p services/a-valid
  MOCK_YQ_STDOUT=$'a-valid\nz-missing\n'

  run_validator

  assert_failure 1
  assert_output ""
  assert_equal "${stderr}" "ERROR: App 'z-missing' in servers.yaml has no services/z-missing/ directory"
}

@test "validate_server_apps: treats spaces apostrophes and wildcards literally" {
  local app="app's space"
  mkdir -p "services/${app}"
  assert_dir_exists "services/${app}"
  MOCK_YQ_STDOUT="${app}"$'\n'

  run_validator

  assert_success
  assert_output ""
  assert_equal "${stderr}" ""

  # Never create '*' on NTFS; only emit it from the mocked yq.
  mkdir services/foo-one
  assert_dir_exists services/foo-one
  MOCK_YQ_STDOUT=$'foo-*\n'

  run_validator

  assert_failure 1
  assert_output ""
  assert_equal "${stderr}" "ERROR: App 'foo-*' in servers.yaml has no services/foo-*/ directory"
}

@test "validate_server_apps: strips carriage returns from CRLF yq output" {
  mkdir -p services/alpha services/beta
  MOCK_YQ_STDOUT=$'beta\r\nalpha\r\nbeta\r\n'

  run_validator

  assert_success
  assert_output ""
  assert_equal "${stderr}" ""
}

@test "validate_server_apps: propagates a mise failure without stdout" {
  MOCK_MISE_STATUS=127
  MOCK_MISE_STDERR=$'mise: yq unavailable\n'

  run_validator -127

  assert_failure 127
  assert_output ""
  assert_equal "${stderr}" "mise: yq unavailable"
}

@test "validate_server_apps: preserves a yq failure despite valid stdout via pipefail" {
  mkdir -p services/alpha
  MOCK_YQ_STDOUT=$'alpha\n'
  MOCK_MISE_STATUS=42
  MOCK_MISE_STDERR=$'yq: failed to parse servers.yaml\n'

  run_validator

  assert_failure 42
  assert_output ""
  assert_equal "${stderr}" "yq: failed to parse servers.yaml"
}
