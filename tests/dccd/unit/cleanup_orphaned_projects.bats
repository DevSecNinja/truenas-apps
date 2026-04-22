#!/usr/bin/env bats
# Unit tests for cleanup_orphaned_projects.

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() {
    common_setup
    mkdir -p "${BASE_DIR}/services"
}
teardown() { common_teardown; }

@test "cleanup_orphaned_projects: no-op when before_apps is empty" {
    create_mock docker 0 ""

    run cleanup_orphaned_projects "${BASE_DIR}" ""
    assert_success
    # docker should never be called.
    [ "$(mock_call_count docker)" = "0" ]
}

@test "cleanup_orphaned_projects: skips apps whose compose.yaml still exists" {
    mkdir -p "${BASE_DIR}/services/plex"
    touch "${BASE_DIR}/services/plex/compose.yaml"
    create_mock docker 0 ""

    run cleanup_orphaned_projects "${BASE_DIR}" "plex"
    assert_success
    [ "$(mock_call_count docker)" = "0" ]
}

@test "cleanup_orphaned_projects: tears down apps whose compose file was removed" {
    # "plex" is reported as existing before the pull but no compose.yaml now.
    # remove_compose_project will call `docker ps -aq …` — mock empty to
    # take the "no containers found" path and exit cleanly.
    create_mock docker 0 ""

    run cleanup_orphaned_projects "${BASE_DIR}" "plex"
    assert_success
    assert_output --partial "Detected removed service 'plex'"
    # Tear-down path must be invoked.
    assert_output --partial "No containers found for project 'plex'"
}

@test "cleanup_orphaned_projects: uses ix- prefix in TrueNAS mode" {
    TRUENAS=1
    create_mock docker 0 ""

    run cleanup_orphaned_projects "${BASE_DIR}" "foo"
    assert_success
    assert_output --partial "tearing down project 'ix-foo'"
}

@test "cleanup_orphaned_projects: handles multiple removed apps" {
    create_mock docker 0 ""

    run cleanup_orphaned_projects "${BASE_DIR}" "$(printf 'a\nb\nc\n')"
    assert_success
    assert_output --partial "Detected removed service 'a'"
    assert_output --partial "Detected removed service 'b'"
    assert_output --partial "Detected removed service 'c'"
}
