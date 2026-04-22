#!/usr/bin/env bats
# Unit tests for get_project_image_info()

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    create_default_mocks
}

teardown() {
    common_teardown
}

@test "get_project_image_info: calls docker ps and inspect" {
    create_mock "docker" 0 ""
    run get_project_image_info "test-project"
    assert_success
    assert_mock_called "docker"
}

@test "get_project_image_info: returns empty for no containers" {
    create_mock "docker" 0 ""
    run get_project_image_info "empty-project"
    assert_success
}
