#!/usr/bin/env bats
# Coverage for the declarative TrueNAS application registry.

load '../helpers/common'

setup_file() {
  require_test_yq
}

setup() {
  prep_common_setup
}

teardown() {
  prep_common_teardown
}

@test "load_app_config: loads the Dawarich account from the registry" {
  run load_app_config_values "dawarich"

  assert_success
  assert_output "dawarich|svc-app-dawarich|3128|true"
}

@test "load_app_config: preserves false for Memos admin membership" {
  run load_app_config_values "memos"

  assert_success
  assert_output "memos|svc-app-memos|3129|false"
}

@test "load_app_config: rejects an unsupported app" {
  run load_app_config "not-registered"

  assert_failure
  assert_output --partial "Unsupported app: not-registered"
}

@test "load_app_config: rejects an invalid app name before querying the registry" {
  run load_app_config "../memos"

  assert_failure
  assert_output --partial "Invalid app name: ../memos"
}

@test "load_app_config: rejects an account name that does not match the app" {
  write_test_app_manifest "dawarich" "svc-app-wrong" "3128" "true"

  run load_app_config "dawarich"

  assert_failure
  assert_output --partial \
    "Invalid account_name for dawarich: expected svc-app-dawarich"
}

@test "load_app_config: rejects a non-integer account ID" {
  write_test_app_manifest "dawarich" "svc-app-dawarich" "not-an-id" "true"

  run load_app_config "dawarich"

  assert_failure
  assert_output --partial \
    "Invalid account_id for dawarich: expected an integer"
}

@test "load_app_config: rejects an account ID outside the service range" {
  write_test_app_manifest "dawarich" "svc-app-dawarich" "3200" "true"

  run load_app_config "dawarich"

  assert_failure
  assert_output --partial \
    "Invalid account_id for dawarich: expected a value from 3100 to 3199"
}

@test "load_app_config: rejects a non-boolean admin membership value" {
  write_test_app_manifest "memos" "svc-app-memos" "3129" "yes"

  run load_app_config "memos"

  assert_failure
  assert_output --partial \
    "Invalid admin_group_member for memos: expected true or false"
}

@test "list_supported_apps: lists both registry keys" {
  run list_supported_apps

  assert_success
  assert_line "  dawarich"
  assert_line "  memos"
}
