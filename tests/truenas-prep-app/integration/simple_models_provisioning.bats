#!/usr/bin/env bats
# Representative flows for the expanded simple-model registry, not one file per app.

load '../helpers/common'
load '../helpers/mocks'

setup_file() {
  require_test_jq
}

setup() {
  prep_common_setup
  create_prep_mocks
  mkdir -p "${TEST_REPO_ROOT}/services/traefik" \
    "${TEST_REPO_ROOT}/services/outline"
}

teardown() {
  prep_common_teardown
}

assert_simple_model_provisioned() {
  local app="$1" account_id="$2"

  run provision_app "${app}" </dev/null

  assert_success
  assert_output --partial "Created group svc-app-${app} with GID ${account_id}"
  assert_output --partial "Created user svc-app-${app} with UID ${account_id}"
  assert_output --partial "Created dataset tank/services/${app}"
  assert_output --partial "${app} host prerequisites are ready"
  assert_mock_called_with "midclt" \
    "call group.create {\"name\":\"svc-app-${app}\",\"gid\":${account_id},\"smb\":false}"
  assert_mock_called_with "midclt" \
    "call user.create {\"username\":\"svc-app-${app}\",\"uid\":${account_id},\"group\":41}"
  assert_mock_called_with "midclt" \
    "call pool.dataset.create {\"name\":\"tank/services/${app}\"}"
  assert_midclt_call_count "group.create" "1"
  assert_midclt_call_count "user.create" "1"
  assert_midclt_call_count "user.update" "0"
  assert_midclt_call_count "pool.dataset.create" "1"
  assert_file_exists "${MOCK_STATE}/group.exists"
  assert_file_exists "${MOCK_STATE}/user.exists"
  assert_file_exists "${MOCK_STATE}/dataset.exists"
  assert_file_not_exists "${MOCK_STATE}/admin-member"
  assert_dir_exists "${TEST_REPO_ROOT}/services/${app}"
  assert_mock_called_with "chown" \
    "truenas_admin:truenas_admin ${TEST_REPO_ROOT}/services/${app}"
  assert_mock_called_with "chmod" \
    "0770 ${TEST_REPO_ROOT}/services/${app}"
}

@test "provision_app: Traefik provisions the lower-bound UID/GID 3100 without admin membership" {
  assert_simple_model_provisioned "traefik" "3100"
}

@test "provision_app: Outline provisions host UID/GID 3120 without substituting its image-internal UID" {
  assert_simple_model_provisioned "outline" "3120"
}
