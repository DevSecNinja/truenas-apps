#!/usr/bin/env bats
# Mocked integration coverage for Memos host provisioning.

load '../helpers/common'
load '../helpers/mocks'

setup_file() {
  require_test_yq
}

setup() {
  prep_common_setup
  create_prep_mocks
  printf '%s\n' "existing compose content" \
    >"${TEST_REPO_ROOT}/services/memos/compose.yaml"
}

teardown() {
  prep_common_teardown
}

@test "provision_memos: creates UID/GID 3129 and skips admin membership" {
  run provision_memos

  assert_success
  assert_output --partial "Created group svc-app-memos with GID 3129"
  assert_output --partial "Created user svc-app-memos with UID 3129"
  assert_output --partial "Created dataset tank/services/memos"
  assert_output --partial "memos host prerequisites are ready"
  assert_file_exists "${MOCK_STATE}/dataset.exists"
  assert_file_exists "${TEST_REPO_ROOT}/services/memos/compose.yaml"
  assert_file_not_exists "${MOCK_STATE}/admin-member"
  assert_mock_called_with "midclt" \
    'call group.create {"name":"svc-app-memos","gid":3129,"smb":false}'
  assert_mock_called_with "midclt" \
    'call user.create {"username":"svc-app-memos","uid":3129,"group":41}'
  assert_midclt_call_count "user.update" "0"
  assert_mock_called_with "midclt" \
    'call pool.dataset.create {"name":"tank/services/memos"}'
  assert_mock_called_with "zfs" "list -H -o name tank/services/memos"
  assert_mock_called_with "chown" \
    "truenas_admin:truenas_admin ${TEST_REPO_ROOT}/services/memos"
  assert_mock_called_with "chmod" \
    "0770 ${TEST_REPO_ROOT}/services/memos"
}
