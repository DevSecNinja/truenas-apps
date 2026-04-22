#!/usr/bin/env bats
# Integration tests: TrueNAS deploy mode

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    create_default_mocks
    TRUENAS=1
}

teardown() {
    common_teardown
}

@test "truenas mode: cleanup_orphaned_projects uses ix- prefix" {
    create_mock "docker" 0 ""
    run cleanup_orphaned_projects "${BASE_DIR}" "plex"
    assert_success
    assert_output --partial "ix-plex"
}

@test "truenas mode: ix- prefix strips leading underscore" {
    TRUENAS=1
    create_mock "docker" 0 ""
    run cleanup_orphaned_projects "${BASE_DIR}" "_bootstrap"
    assert_success
    assert_output --partial "ix-bootstrap"
}

@test "truenas mode: TRUENAS_APPS_BASE is set" {
    [[ "${TRUENAS_APPS_BASE}" == "/mnt/.ix-apps/app_configs" ]]
}

@test "truenas mode: cleanup preserves apps with compose files" {
    mkdir -p "${BASE_DIR}/services/plex"
    touch "${BASE_DIR}/services/plex/compose.yaml"
    run cleanup_orphaned_projects "${BASE_DIR}" "plex"
    assert_success
    refute_output --partial "tearing down"
}

@test "truenas mode: redeploy_truenas_apps function exists" {
    # Verify the function was loaded via source guard
    run type redeploy_truenas_apps
    assert_success
    assert_output --partial "function"
}
