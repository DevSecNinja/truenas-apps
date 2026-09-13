#!/usr/bin/env bats
# Mocked integration coverage for Karakeep host provisioning.

load '../helpers/common'
load '../helpers/mocks'

setup() {
  prep_common_setup
  create_prep_mocks
  printf '%s\n' "existing Karakeep compose content" \
    >"${TEST_REPO_ROOT}/services/karakeep/compose.yaml"
  mkdir -p "${TEST_REPO_ROOT}/services/karakeep/config"
  printf '%s\n' "existing Karakeep config content" \
    >"${TEST_REPO_ROOT}/services/karakeep/config/karakeep.conf"
}

teardown() {
  prep_common_teardown
}

@test "provision_karakeep: creates UID/GID 3130 resources and restores service files without admin membership" {
  run provision_karakeep

  assert_success
  assert_output --partial "Created group svc-app-karakeep with GID 3130"
  assert_output --partial "Created user svc-app-karakeep with UID 3130"
  assert_output --partial "Created dataset tank/services/karakeep"
  assert_output --partial "Restored karakeep files into the new dataset"
  assert_output --partial "karakeep host prerequisites are ready"
  assert_file_exists "${MOCK_STATE}/dataset.exists"
  assert_file_exists "${TEST_REPO_ROOT}/services/karakeep/compose.yaml"
  assert_file_exists \
    "${TEST_REPO_ROOT}/services/karakeep/config/karakeep.conf"

  run cat "${TEST_REPO_ROOT}/services/karakeep/compose.yaml"
  assert_success
  assert_output "existing Karakeep compose content"
  run cat "${TEST_REPO_ROOT}/services/karakeep/config/karakeep.conf"
  assert_success
  assert_output "existing Karakeep config content"

  assert_mock_called_with "midclt" \
    'call group.create {"name":"svc-app-karakeep","gid":3130,"smb":false}'
  assert_mock_called_with "midclt" \
    'call user.create {"username":"svc-app-karakeep","uid":3130,"group":41}'
  assert_mock_called_with "midclt" \
    'call pool.dataset.create {"name":"tank/services/karakeep"}'
  assert_midclt_call_count "user.update" "0"
  assert_file_not_exists "${MOCK_STATE}/admin-member"
  assert_mock_called_with "chown" \
    "truenas_admin:truenas_admin ${TEST_REPO_ROOT}/services/karakeep"
  assert_mock_called_with "chmod" \
    "0770 ${TEST_REPO_ROOT}/services/karakeep"

  run find "${TEST_REPO_ROOT}/services" -maxdepth 1 \
    -name 'karakeep.truenas-prep.*' -print
  assert_success
  assert_output ""
}

@test "provision_karakeep: rerun leaves existing resources unchanged" {
  run provision_karakeep
  assert_success

  run provision_karakeep

  assert_success
  assert_output --partial \
    "Group svc-app-karakeep already exists with GID 3130"
  assert_output --partial \
    "User svc-app-karakeep already exists with UID 3130"
  assert_output --partial \
    "Dataset tank/services/karakeep already exists"
  refute_output --partial "auxiliary member"
  assert_midclt_call_count "group.create" "1"
  assert_midclt_call_count "user.create" "1"
  assert_midclt_call_count "user.update" "0"
  assert_midclt_call_count "pool.dataset.create" "1"
  assert_mock_call_count "chown" "2"
  assert_mock_call_count "chmod" "2"
  assert_file_exists "${TEST_REPO_ROOT}/services/karakeep/compose.yaml"
  assert_file_exists \
    "${TEST_REPO_ROOT}/services/karakeep/config/karakeep.conf"
}
