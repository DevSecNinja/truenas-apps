#!/usr/bin/env bats
# Unit tests for cleanup_orphaned_projects()

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    create_default_mocks
}

teardown() {
    common_teardown
}

@test "cleanup_orphaned_projects: returns when before_apps empty" {
    run cleanup_orphaned_projects "${BASE_DIR}" ""
    assert_success
    assert_output ""
}

@test "cleanup_orphaned_projects: skips apps that still have compose files" {
    mkdir -p "${BASE_DIR}/services/existingapp"
    touch "${BASE_DIR}/services/existingapp/compose.yaml"
    run cleanup_orphaned_projects "${BASE_DIR}" "existingapp"
    assert_success
    refute_output --partial "tearing down"
}

@test "cleanup_orphaned_projects: tears down removed apps" {
    # app1 directory doesn't exist anymore (was removed)
    create_mock "docker" 0 ""
    run cleanup_orphaned_projects "${BASE_DIR}" "app1"
    assert_success
    assert_output --partial "Detected removed service 'app1'"
}

@test "cleanup_orphaned_projects: uses ix- prefix in TrueNAS mode" {
    TRUENAS=1
    create_mock "docker" 0 ""
    run cleanup_orphaned_projects "${BASE_DIR}" "plex"
    assert_success
    assert_output --partial "ix-plex"
}

@test "cleanup_orphaned_projects: handles compose.yml variant" {
    mkdir -p "${BASE_DIR}/services/ymlapp"
    touch "${BASE_DIR}/services/ymlapp/compose.yml"
    run cleanup_orphaned_projects "${BASE_DIR}" "ymlapp"
    assert_success
    refute_output --partial "tearing down"
}

@test "cleanup_orphaned_projects: handles docker-compose.yaml variant" {
    mkdir -p "${BASE_DIR}/services/dcapp"
    touch "${BASE_DIR}/services/dcapp/docker-compose.yaml"
    run cleanup_orphaned_projects "${BASE_DIR}" "dcapp"
    assert_success
    refute_output --partial "tearing down"
}

@test "cleanup_orphaned_projects: handles multiple apps mixed" {
    mkdir -p "${BASE_DIR}/services/kept"
    touch "${BASE_DIR}/services/kept/compose.yaml"
    # "removed" has no directory
    create_mock "docker" 0 ""
    run cleanup_orphaned_projects "${BASE_DIR}" $'kept\nremoved'
    assert_success
    refute_output --partial "Detected removed service 'kept'"
    assert_output --partial "Detected removed service 'removed'"
}

@test "cleanup_orphaned_projects: skips empty lines" {
    run cleanup_orphaned_projects "${BASE_DIR}" $'\n\n'
    assert_success
    assert_output ""
}
