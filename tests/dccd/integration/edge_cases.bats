#!/usr/bin/env bats
# Integration tests: edge cases and error handling

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    create_default_mocks
}

teardown() {
    common_teardown
}

@test "edge case: empty services directory" {
    # services dir exists but is empty
    run decrypt_sops_files
    assert_success
    assert_output --partial "No *.sops.env files found"
}

@test "edge case: log_message handles empty string" {
    run log_message ""
    assert_success
}

@test "edge case: url_encode_simple handles empty string" {
    run url_encode_simple ""
    assert_success
    assert_output ""
}

@test "edge case: cleanup with single empty line" {
    run cleanup_orphaned_projects "${BASE_DIR}" ""
    assert_success
}

@test "edge case: remove_compose_project with special chars in name" {
    create_mock "docker" 0 ""
    run remove_compose_project "my-app_v2"
    assert_success
    assert_output --partial "No containers found for project 'my-app_v2'"
}

@test "edge case: log_image_changes with multiline before empty after" {
    # This shouldn't normally happen but tests resilience
    run log_image_changes "testapp" "web=nginx:1.0" ""
    assert_success
}

@test "edge case: _handle_gatus_exit function exists" {
    run type _handle_gatus_exit
    assert_success
    assert_output --partial "function"
}

@test "edge case: usage function exists and shows help" {
    run usage
    assert_failure  # usage calls exit 1
    assert_output --partial "Usage:"
    assert_output --partial "-d <path>"
}
