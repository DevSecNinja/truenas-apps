#!/usr/bin/env bats
# Integration tests: orphan cleanup

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    create_default_mocks
}

teardown() {
    common_teardown
}

@test "orphan cleanup: removes project for deleted app" {
    # app1 was in before list but directory is gone
    create_mock "docker" 0 ""
    run cleanup_orphaned_projects "${BASE_DIR}" "app1"
    assert_success
    assert_output --partial "Detected removed service 'app1'"
}

@test "orphan cleanup: uses ix- prefix for TrueNAS" {
    TRUENAS=1
    create_mock "docker" 0 ""
    run cleanup_orphaned_projects "${BASE_DIR}" "plex"
    assert_success
    assert_output --partial "project 'ix-plex'"
}

@test "orphan cleanup: leaves existing apps alone" {
    mkdir -p "${BASE_DIR}/services/kept"
    touch "${BASE_DIR}/services/kept/compose.yaml"
    mkdir -p "${BASE_DIR}/services/removed"
    # Don't create compose.yaml for removed

    create_mock "docker" 0 ""
    run cleanup_orphaned_projects "${BASE_DIR}" $'kept\nremoved'
    refute_output --partial "Detected removed service 'kept'"
    assert_output --partial "Detected removed service 'removed'"
}

@test "orphan cleanup: calls remove_compose_project for each orphan" {
    create_mock "docker" 0 ""
    run cleanup_orphaned_projects "${BASE_DIR}" $'gone1\ngone2'
    assert_output --partial "Detected removed service 'gone1'"
    assert_output --partial "Detected removed service 'gone2'"
}
