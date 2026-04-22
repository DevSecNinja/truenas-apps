#!/usr/bin/env bats
# Integration tests: remove mode (-R flag)

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    create_default_mocks
}

teardown() {
    common_teardown
}

@test "remove mode: remove_compose_project cleans up containers and networks" {
    create_sequential_mock "docker" "0:container1" "0:" "0:" "0:net1" "0:"
    run remove_compose_project "test-app"
    assert_success
    assert_output --partial "Stopping and removing"
    assert_output --partial "cleaned up"
}

@test "remove mode: handles no running containers gracefully" {
    create_mock "docker" 0 ""
    run remove_compose_project "nonexistent"
    assert_success
    assert_output --partial "No containers found"
}

@test "remove mode: docker stop failures don't prevent cleanup" {
    # First call returns containers, stop fails, rm succeeds, network check returns empty
    create_sequential_mock "docker" "0:abc123" "1:" "0:" "0:"
    run remove_compose_project "test-app"
    assert_success
    assert_output --partial "cleaned up"
}

@test "remove mode: cleans up networks after containers" {
    create_sequential_mock "docker" "0:abc123" "0:" "0:" "0:netid" "0:"
    run remove_compose_project "test-app"
    assert_success
    assert_output --partial "Removing networks"
}
