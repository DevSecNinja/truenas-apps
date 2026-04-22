#!/usr/bin/env bats
# Unit tests for remove_compose_project()

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    create_default_mocks
}

teardown() {
    common_teardown
}

@test "remove_compose_project: handles no containers found" {
    create_mock "docker" 0 ""
    run remove_compose_project "test-project"
    assert_success
    assert_output --partial "No containers found"
}

@test "remove_compose_project: stops and removes containers" {
    # First docker call returns container IDs, rest succeed
    create_sequential_mock "docker" "0:abc123" "0:" "0:" "0:" "0:"
    run remove_compose_project "test-project"
    assert_success
    assert_output --partial "Stopping and removing"
}

@test "remove_compose_project: removes project networks" {
    create_sequential_mock "docker" "0:abc123" "0:" "0:" "0:net123" "0:"
    run remove_compose_project "test-project"
    assert_success
    assert_output --partial "Removing networks"
}

@test "remove_compose_project: reports cleanup complete" {
    create_sequential_mock "docker" "0:abc123" "0:" "0:" "0:" "0:"
    run remove_compose_project "test-project"
    assert_success
    assert_output --partial "cleaned up"
}
