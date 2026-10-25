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

@test "cleanup_orphaned_projects: retires exactly eight ix- projects while retaining state and Plex" {
    local app command_name state_file
    local before_apps="plex"
    local expected_calls=""
    local -a retired_apps=(bazarr lidarr prowlarr qbittorrent radarr sabnzbd sonarr spottarr)
    local -a docker_responses=()
    local -a host_commands=(midclt zfs userdel groupdel usermod groupmod)
    local -a retained_files=(data/state.db backups/archive config/local.conf .env .config-hash.env)

    TRUENAS=1
    TRUENAS_APPS_BASE="${BASE_DIR}/host/app_configs"
    for command_name in "${host_commands[@]}"; do
        create_mock "${command_name}" 1 "Unexpected host-management call"
    done

    # Everything below is synthetic and lives in common_setup's temp tree.
    # Retired directories remain on disk, but no longer contain Compose files.
    for app in "${retired_apps[@]}" plex media photos; do
        mkdir -p "${BASE_DIR}/services/${app}"/{data,backups,config} \
            "${TRUENAS_APPS_BASE}/${app}"
        for state_file in "${retained_files[@]}"; do
            touch "${BASE_DIR}/services/${app}/${state_file}"
        done
        touch "${TRUENAS_APPS_BASE}/${app}/metadata.json"
    done
    touch "${BASE_DIR}/services/plex/compose.yaml"

    for app in "${retired_apps[@]}"; do
        before_apps+=$'\n'"${app}"
        # Include two containers to exercise intentional ID word splitting.
        docker_responses+=("0:${app}-main ${app}-sidecar" "0:" "0:" "0:${app}-network" "0:")
        expected_calls+="ps -aq --filter label=com.docker.compose.project=ix-${app}"$'\n'
        expected_calls+="stop ${app}-main ${app}-sidecar"$'\n'
        expected_calls+="rm -f ${app}-main ${app}-sidecar"$'\n'
        expected_calls+="network ls --filter label=com.docker.compose.project=ix-${app} -q"$'\n'
        expected_calls+="network rm ${app}-network"$'\n'
    done
    create_sequential_mock "docker" "${docker_responses[@]}"

    run cleanup_orphaned_projects "${BASE_DIR}" "${before_apps}"

    assert_success
    for app in "${retired_apps[@]}"; do
        assert_output --partial "Detected removed service '${app}' — tearing down project 'ix-${app}'"
        assert_output --partial "Project 'ix-${app}' cleaned up"
    done
    refute_output --partial "ix-plex"
    refute_output --partial "Detected removed service 'plex'"

    # Exact call equality excludes Plex, volume removal, prune, and unrelated
    # projects, and proves stop/rm/network removal rather than just discovery.
    assert_mock_called "docker"
    run get_mock_call_args "docker"
    assert_success
    assert_output "${expected_calls%$'\n'}"
    for command_name in "${host_commands[@]}" sudo; do
        assert_mock_not_called "${command_name}"
    done

    for app in "${retired_apps[@]}" plex media photos; do
        assert_dir_exists "${BASE_DIR}/services/${app}"
        for state_file in "${retained_files[@]}"; do
            assert_file_exists "${BASE_DIR}/services/${app}/${state_file}"
        done
        assert_dir_exists "${TRUENAS_APPS_BASE}/${app}"
        assert_file_exists "${TRUENAS_APPS_BASE}/${app}/metadata.json"
    done
    assert_file_exists "${BASE_DIR}/services/plex/compose.yaml"
}
