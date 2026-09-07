#!/usr/bin/env bats
# Mocked integration coverage for Dawarich host provisioning.

load '../helpers/common'
load '../helpers/mocks'

setup() {
  prep_common_setup
  create_prep_mocks
  printf '%s\n' "existing compose content" \
    >"${TEST_REPO_ROOT}/services/dawarich/compose.yaml"
}

teardown() {
  prep_common_teardown
}

@test "provision_dawarich: creates the service account, membership, and dataset" {
  run provision_dawarich

  assert_success
  assert_output --partial "Created group svc-app-dawarich with GID 3128"
  assert_output --partial "Created user svc-app-dawarich with UID 3128"
  assert_output --partial "Created dataset tank/services/dawarich"
  assert_output --partial "dawarich host prerequisites are ready"
  assert_file_exists "${MOCK_STATE}/dataset.exists"
  assert_file_exists \
    "${TEST_REPO_ROOT}/services/dawarich/compose.yaml"
  assert_mock_called_with "midclt" "call group.create"
  assert_mock_called_with "midclt" "call user.create"
  assert_mock_called_with "midclt" "call user.update 7"
  assert_mock_called_with "midclt" "call pool.dataset.create"
  assert_mock_called_with "chown" \
    "truenas_admin:truenas_admin ${TEST_REPO_ROOT}/services/dawarich"
  assert_mock_called_with "chmod" \
    "0770 ${TEST_REPO_ROOT}/services/dawarich"
}

@test "provision_dawarich: rerun leaves existing resources unchanged" {
  run provision_dawarich
  assert_success

  run provision_dawarich

  assert_success
  assert_output --partial \
    "Group svc-app-dawarich already exists with GID 3128"
  assert_output --partial \
    "User svc-app-dawarich already exists with UID 3128"
  assert_output --partial \
    "truenas_admin is already an auxiliary member of svc-app-dawarich"
  assert_output --partial \
    "Dataset tank/services/dawarich already exists"
  assert_midclt_call_count "group.create" "1"
  assert_midclt_call_count "user.create" "1"
  assert_midclt_call_count "user.update" "1"
  assert_midclt_call_count "pool.dataset.create" "1"
  assert_mock_call_count "chown" "2"
  assert_mock_call_count "chmod" "2"
}

@test "provision_dawarich: rejects a GID assigned to another group" {
  touch "${MOCK_STATE}/gid-collision"

  run provision_dawarich

  assert_failure
  assert_output --partial \
    "GID 3128 is already assigned to group legacy-group"
  assert_midclt_call_count "group.create" "0"
  assert_midclt_call_count "user.create" "0"
  assert_midclt_call_count "pool.dataset.create" "0"
}

@test "provision_dawarich: rejects a UID assigned to another user" {
  touch "${MOCK_STATE}/group.exists" "${MOCK_STATE}/uid-collision"

  run provision_dawarich

  assert_failure
  assert_output --partial \
    "UID 3128 is already assigned to user legacy-user"
  assert_midclt_call_count "group.create" "0"
  assert_midclt_call_count "user.create" "0"
  assert_midclt_call_count "pool.dataset.create" "0"
}

@test "provision_dawarich: restores staged files when dataset creation fails" {
  touch "${MOCK_STATE}/group.exists" "${MOCK_STATE}/user.exists" \
    "${MOCK_STATE}/admin-member" "${MOCK_STATE}/dataset-create-fails"

  run provision_dawarich

  assert_failure
  assert_output --partial \
    "Failed to create dataset tank/services/dawarich; restored the service directory"
  assert_dir_exists "${TEST_REPO_ROOT}/services/dawarich"
  assert_file_exists \
    "${TEST_REPO_ROOT}/services/dawarich/compose.yaml"
  assert_file_not_exists "${MOCK_STATE}/dataset.exists"
  run find "${TEST_REPO_ROOT}/services" -maxdepth 1 \
    -name 'dawarich.truenas-prep.*' -print
  assert_success
  assert_output ""
  assert_midclt_call_count "pool.dataset.create" "1"
  assert_mock_call_count "chown" "0"
  assert_mock_call_count "chmod" "0"
}
