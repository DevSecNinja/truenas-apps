#!/usr/bin/env bats
# Integration tests for gha-renovate-health-check.sh.

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  common_setup

  RENOVATE_HEALTH_SCRIPT="${REPO_ROOT}/scripts/gha-renovate-health-check.sh"
}

teardown() {
  common_teardown
}

mock_gh_response() {
  local exit_code="$1"
  local stdout="${2:-}"
  local stderr="${3:-}"

  printf '%s' "${stdout}" >"${MOCK_LOG}/gh.stdout"
  printf '%s' "${stderr}" >"${MOCK_LOG}/gh.stderr"
  printf '%s' "${exit_code}" >"${MOCK_LOG}/gh.exit"

  cat >"${MOCK_BIN}/gh" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >>"${MOCK_LOG}/gh.calls"
cat "${MOCK_LOG}/gh.stdout"
cat "${MOCK_LOG}/gh.stderr" >&2
exit "$(cat "${MOCK_LOG}/gh.exit")"
MOCK
  chmod +x "${MOCK_BIN}/gh"
}

run_health_check() {
  run env \
    LOG_COLOR=never \
    LOG_JOURNAL=never \
    LOG_TIMESTAMP="2026-01-01 00:00:00" \
    bash "${RENOVATE_HEALTH_SCRIPT}"
}

@test "gha_renovate_health_check: exactly one healthy dashboard succeeds" {
  mock_gh_response 0 \
    '[{"number":208,"title":"Renovate Dashboard","url":"https://github.example/issues/208","body":"All dependencies were looked up successfully."}]'

  run_health_check

  assert_success
  assert_output --partial "Renovate reports no package lookup failures"
  assert_output --partial "https://github.example/issues/208"
  assert_mock_called_with "gh" 'issue list --state open --search "Renovate Dashboard" in:title'
}

@test "gha_renovate_health_check: package lookup failure text fails" {
  mock_gh_response 0 \
    '[{"number":208,"title":"Renovate Dashboard","url":"https://github.example/issues/208","body":"Renovate failed to look up docker.io/example/image."}]'

  run_health_check

  assert_failure
  assert_output --partial "Renovate reports package lookup failures"
  assert_output --partial "https://github.example/issues/208"
}

@test "gha_renovate_health_check: Docker token error fails" {
  mock_gh_response 0 \
    '[{"number":208,"title":"Renovate Dashboard","url":"https://github.example/issues/208","body":"Error obtaining docker token for registry.example."}]'

  run_health_check

  assert_failure
  assert_output --partial "Renovate reports package lookup failures"
}

@test "gha_renovate_health_check: missing dashboard fails" {
  mock_gh_response 0 '[]'

  run_health_check

  assert_failure
  assert_output --partial "Expected one open Renovate Dashboard issue, found 0"
}

@test "gha_renovate_health_check: multiple dashboard results fail" {
  mock_gh_response 0 \
    '[{"number":208,"title":"Renovate Dashboard","url":"https://github.example/issues/208","body":"Healthy."},{"number":209,"title":"Renovate Dashboard","url":"https://github.example/issues/209","body":"Healthy."}]'

  run_health_check

  assert_failure
  assert_output --partial "Expected one open Renovate Dashboard issue, found 2"
}

@test "gha_renovate_health_check: gh command failure propagates" {
  mock_gh_response 42 "" "gh unavailable"

  run_health_check

  assert_failure 42
  assert_output --partial "gh unavailable"
}
