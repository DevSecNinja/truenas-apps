#!/usr/bin/env bash
# Shared setup and workflow helpers for truenas-prep-app.sh tests.

TEST_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

load "${TEST_PROJECT_ROOT}/tests/libs/bats-support/load"
load "${TEST_PROJECT_ROOT}/tests/libs/bats-assert/load"
load "${TEST_PROJECT_ROOT}/tests/libs/bats-file/load"

prep_common_setup() {
  TEST_TMPDIR="$(mktemp -d "${BATS_TMPDIR}/dccd-test.XXXXXX")"
  MOCK_BIN="${TEST_TMPDIR}/bin"
  MOCK_LOG="${TEST_TMPDIR}/log"
  MOCK_STATE="${TEST_TMPDIR}/state"
  TEST_REPO_ROOT="${TEST_TMPDIR}/repo"
  mkdir -p "${MOCK_BIN}" "${MOCK_LOG}" "${MOCK_STATE}" \
    "${TEST_REPO_ROOT}/services/dawarich" \
    "${TEST_REPO_ROOT}/services/memos"
  cp "${TEST_PROJECT_ROOT}/truenas-apps.yaml" \
    "${TEST_REPO_ROOT}/truenas-apps.yaml"

  ORIGINAL_PATH="${PATH}"
  export MOCK_BIN MOCK_LOG MOCK_STATE TEST_REPO_ROOT
  export PATH="${MOCK_BIN}:${PATH}"
  export LOG_COLOR=never LOG_JOURNAL=never
  export LOG_TIMESTAMP="2026-09-07 07:28:02"
  unset MOCK_APP_NAME MOCK_ACCOUNT_NAME MOCK_ACCOUNT_ID

  # shellcheck source=../../../scripts/truenas-prep-app.sh disable=SC1091
  source "${TEST_PROJECT_ROOT}/scripts/truenas-prep-app.sh"
  set +euo pipefail

  export REPO_ROOT="${TEST_REPO_ROOT}"
  export ADMIN_USER="truenas_admin"
}

prep_common_teardown() {
  PATH="${ORIGINAL_PATH}"
  export PATH
  rm -rf "${TEST_TMPDIR}"
}

require_test_yq() {
  if ! command -v yq >/dev/null 2>&1; then
    printf '%s\n' \
      "yq is required; run this suite with: mise exec -- bats tests/truenas-prep-app" \
      >&2
    return 1
  fi
}

write_test_app_manifest() {
  local app_name="$1"
  local account_name="$2"
  local account_id="$3"
  local admin_group_member="$4"

  printf '%s\n' \
    "---" \
    "apps:" \
    "  ${app_name}:" \
    "    account_name: ${account_name}" \
    "    account_id: ${account_id}" \
    "    admin_group_member: ${admin_group_member}" \
    >"${TEST_REPO_ROOT}/truenas-apps.yaml"
}

load_app_config_values() {
  load_app_config "$1"
  # Assigned dynamically by load_app_config from the test manifest.
  # shellcheck disable=SC2153
  printf '%s|%s|%s|%s\n' \
    "${APP_NAME}" "${ACCOUNT_NAME}" "${ACCOUNT_ID}" "${ADMIN_GROUP_MEMBER}"
}

provision_app() {
  require_command yq
  require_command jq
  require_command midclt
  require_command zfs
  load_app_config "$1"

  export MOCK_APP_NAME="${APP_NAME}"
  export MOCK_ACCOUNT_NAME="${ACCOUNT_NAME}"
  export MOCK_ACCOUNT_ID="${ACCOUNT_ID}"

  load_accounts
  ensure_group
  ensure_user
  ensure_admin_membership
  ensure_dataset
  log_result "${APP_NAME} host prerequisites are ready"
}

provision_dawarich() {
  provision_app "dawarich"
}

provision_memos() {
  provision_app "memos"
}
