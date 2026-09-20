#!/usr/bin/env bats
# Mocked integration coverage for changedetection host provisioning.

load '../helpers/common'
load '../helpers/mocks'

setup_file() {
  require_test_jq
}

setup() {
  prep_common_setup
  create_prep_mocks
  mkdir -p "${TEST_REPO_ROOT}/services/changedetection/config"
  printf '%s\n' "existing changedetection compose content" \
    >"${TEST_REPO_ROOT}/services/changedetection/compose.yaml"
  printf '%s\n' "existing changedetection config content" \
    >"${TEST_REPO_ROOT}/services/changedetection/config/fixture.conf"
}

teardown() {
  prep_common_teardown
}

assert_changedetection_files_preserved() {
  assert_dir_exists "${TEST_REPO_ROOT}/services/changedetection/config"
  assert_file_exists "${TEST_REPO_ROOT}/services/changedetection/compose.yaml"
  assert_file_exists \
    "${TEST_REPO_ROOT}/services/changedetection/config/fixture.conf"

  run cat "${TEST_REPO_ROOT}/services/changedetection/compose.yaml"
  assert_success
  assert_output "existing changedetection compose content"
  run cat "${TEST_REPO_ROOT}/services/changedetection/config/fixture.conf"
  assert_success
  assert_output "existing changedetection config content"

  run find "${TEST_REPO_ROOT}/services" -maxdepth 1 \
    -name 'changedetection.truenas-prep.*' -print
  assert_success
  assert_output ""
}

@test "provision_app: changedetection creates UID/GID 3131 resources and restores files without admin membership" {
  run provision_app "changedetection"

  assert_success
  assert_output --partial "Created group svc-app-changedetection with GID 3131"
  assert_output --partial "Created user svc-app-changedetection with UID 3131"
  assert_output --partial "Created dataset tank/services/changedetection"
  assert_output --partial "Restored changedetection files into the new dataset"
  assert_output --partial "changedetection host prerequisites are ready"
  refute_output --partial "Added truenas_admin"
  assert_file_exists "${MOCK_STATE}/group.exists"
  assert_file_exists "${MOCK_STATE}/user.exists"
  assert_file_exists "${MOCK_STATE}/dataset.exists"
  assert_file_not_exists "${MOCK_STATE}/admin-member"
  assert_mock_called_with "midclt" \
    'call group.create {"name":"svc-app-changedetection","gid":3131,"smb":false}'
  assert_mock_called_with "midclt" \
    'call user.create {"username":"svc-app-changedetection","uid":3131,"group":41}'
  assert_mock_called_with "midclt" \
    'call pool.dataset.create {"name":"tank/services/changedetection"}'
  assert_midclt_call_count "group.create" "1"
  assert_midclt_call_count "user.create" "1"
  assert_midclt_call_count "user.update" "0"
  assert_midclt_call_count "pool.dataset.create" "1"
  assert_mock_called_with "docker" \
    "ps --quiet --filter label=com.docker.compose.project=changedetection"
  assert_mock_called_with "zfs" "list -H -o name tank/services/changedetection"
  assert_mock_called_with "chown" \
    "truenas_admin:truenas_admin ${TEST_REPO_ROOT}/services/changedetection"
  assert_mock_called_with "chmod" \
    "0770 ${TEST_REPO_ROOT}/services/changedetection"
  assert_changedetection_files_preserved
}

@test "provision_app: changedetection rerun reuses resources and never adds admin membership" {
  run provision_app "changedetection"
  assert_success

  run provision_app "changedetection"

  assert_success
  assert_output --partial \
    "Group svc-app-changedetection already exists with GID 3131"
  assert_output --partial \
    "User svc-app-changedetection already exists with UID 3131"
  assert_output --partial "Dataset tank/services/changedetection already exists"
  assert_output --partial "changedetection host prerequisites are ready"
  refute_output --partial "Staged existing changedetection files"
  refute_output --partial "Added truenas_admin"
  assert_midclt_call_count "group.create" "1"
  assert_midclt_call_count "user.create" "1"
  assert_midclt_call_count "user.update" "0"
  assert_midclt_call_count "pool.dataset.create" "1"
  assert_mock_call_count "docker" "1"
  assert_mock_call_count "chown" "2"
  assert_mock_call_count "chmod" "2"
  assert_file_not_exists "${MOCK_STATE}/admin-member"
  assert_changedetection_files_preserved
}

@test "provision_app: changedetection restores staged files when dataset creation fails" {
  touch "${MOCK_STATE}/group.exists" "${MOCK_STATE}/user.exists" \
    "${MOCK_STATE}/dataset-create-fails"

  run provision_app "changedetection"

  assert_failure
  assert_output --partial \
    "Failed to create dataset tank/services/changedetection; restored the service directory"
  refute_output --partial "changedetection host prerequisites are ready"
  assert_midclt_call_count "group.create" "0"
  assert_midclt_call_count "user.create" "0"
  assert_midclt_call_count "user.update" "0"
  assert_midclt_call_count "pool.dataset.create" "1"
  assert_file_not_exists "${MOCK_STATE}/dataset.exists"
  assert_file_not_exists "${MOCK_STATE}/admin-member"
  assert_mock_call_count "chown" "0"
  assert_mock_call_count "chmod" "0"
  assert_changedetection_files_preserved
}

@test "provision_app: changedetection refuses to move files while its containers are running" {
  touch "${MOCK_STATE}/group.exists" "${MOCK_STATE}/user.exists" \
    "${MOCK_STATE}/app-running"

  run provision_app "changedetection"

  assert_failure
  assert_output --partial \
    "App changedetection is running; stop it before creating its dataset"
  refute_output --partial "Staged existing changedetection files"
  refute_output --partial "changedetection host prerequisites are ready"
  assert_mock_called_with "docker" \
    "ps --quiet --filter label=com.docker.compose.project=changedetection"
  assert_midclt_call_count "group.create" "0"
  assert_midclt_call_count "user.create" "0"
  assert_midclt_call_count "user.update" "0"
  assert_midclt_call_count "pool.dataset.create" "0"
  assert_file_not_exists "${MOCK_STATE}/dataset.exists"
  assert_file_not_exists "${MOCK_STATE}/admin-member"
  assert_mock_call_count "chown" "0"
  assert_mock_call_count "chmod" "0"
  assert_changedetection_files_preserved
}
