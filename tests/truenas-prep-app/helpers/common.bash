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
    "${TEST_REPO_ROOT}/services/dawarich"

  ORIGINAL_PATH="${PATH}"
  export MOCK_BIN MOCK_LOG MOCK_STATE TEST_REPO_ROOT
  export PATH="${MOCK_BIN}:${PATH}"
  export LOG_COLOR=never LOG_JOURNAL=never
  export LOG_TIMESTAMP="2026-09-07 07:28:02"

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

provision_dawarich() {
  load_app_config "dawarich"
  require_command jq
  require_command midclt
  require_command zfs
  load_accounts
  ensure_group
  ensure_user
  ensure_admin_membership
  ensure_dataset
  log_result "${APP_NAME} host prerequisites are ready"
}
