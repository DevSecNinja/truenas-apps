#!/usr/bin/env bats
# Integration tests: TrueNAS deploy mode

load '../helpers/diagnostics'

setup_file() {
    diagnostics_require_helpers
}

setup() {
    diagnostics_setup
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

@test "redeploy_truenas_apps: unenrolled Open Archiver skips Docker and preserves runtime paths and deployment state" {
    local candidate_dir="${BASE_DIR}/services/open-archiver"
    TRUENAS_APPS_BASE="${BASE_DIR}/truenas-config"
    mkdir -p "${candidate_dir}" "${TRUENAS_APPS_BASE}"
    # Copy only the tracked Compose file, never env files or runtime content.
    # Without Custom App enrollment, even this unprofiled stack must not be parsed.
    cp "${REPO_ROOT}/services/open-archiver/compose.yaml" "${candidate_dir}/compose.yaml"
    assert_file_exists "${candidate_dir}/compose.yaml"
    assert_dir_not_exists "${TRUENAS_APPS_BASE}/open-archiver/versions"
    unset COMPOSE_PROFILES
    COMPOSE_PROFILE_ARGS=()
    NO_PULL=0
    _DEPLOY_ATTEMPTED=7
    export CONFIG_HASH=previous-app-hash
    _CONFIG_HASH_ENV_FILE="${BASE_DIR}/previous-app.config-hash.env"
    create_mock mount 1 ""

    # Call directly: checking counters after BATS run would inspect the parent
    # shell's unchanged state rather than the deployment's state.
    redeploy_truenas_apps || return
    assert_equal "${_DEPLOY_ATTEMPTED}" 7
    assert_equal "${_DEPLOY_ERRORS}" 0
    assert_equal "${_DEPLOY_CHANGED}" 0
    assert_equal "${_DEPLOY_UNCHANGED}" 0
    assert_equal "${_DEPLOY_RESTARTED}" 0
    assert_equal "${#_DEPLOY_FAILED_APPS[@]}" 0
    assert_equal "${CONFIG_HASH}" previous-app-hash
    assert_equal "${_CONFIG_HASH_ENV_FILE}" "${BASE_DIR}/previous-app.config-hash.env"
    # No config/selection call is allowed, not merely no pull/up.
    assert_mock_not_called docker
    assert_mock_not_called mount
    assert_mock_not_called sudo
    assert_mock_not_called yq
    assert_mock_not_called sops
    assert_mock_not_called git
    assert_dir_not_exists "${TRUENAS_APPS_BASE}/open-archiver"
    assert_dir_not_exists "${candidate_dir}/config"
    assert_dir_not_exists "${candidate_dir}/data"
    assert_dir_not_exists "${candidate_dir}/backups"
    assert_file_not_exists "${candidate_dir}/.env"
    assert_file_not_exists "${candidate_dir}/.config-hash.env"
    assert_files_equal "${REPO_ROOT}/services/open-archiver/compose.yaml" "${candidate_dir}/compose.yaml"
}

prepare_failed_truenas_deploy() {
    local app="$1" message="$2" state="$3"
    NO_PULL=1
    TRUENAS_APPS_BASE="${BASE_DIR}/truenas-config"
    local rendered="${TRUENAS_APPS_BASE}/${app#_}/versions/1.0/templates/rendered"
    mkdir -p "${BASE_DIR}/services/${app}" "${rendered}"
    touch "${BASE_DIR}/services/${app}/compose.yaml" "${rendered}/docker-compose.yaml"
    # Validation, services, before snapshot, up, diagnostic list/inspect/logs,
    # after snapshot. A log-read failure must not mask the deployment failure.
    create_sequential_mock docker '0:' '0:web' '0:' "17:${message}" \
        '0:fixture-container' "0:${state}" '44:logs unavailable' '0:'
}

deploy_truenas_and_check_failure() {
    redeploy_truenas_apps || return
    assert_equal "${_DEPLOY_ERRORS}" 1 || return
    assert_equal "${#_DEPLOY_FAILED_APPS[@]}" 1 || return
    assert_equal "${_DEPLOY_FAILED_APPS[0]}" "$1"
}

@test "redeploy_truenas_apps: real error survives hidden stdout and project log failure" {
    local message='invalid mount config: bind source path does not exist'
    prepare_failed_truenas_deploy karakeep "${message}" 'status=running health=unhealthy'
    run --separate-stderr deploy_truenas_and_check_failure karakeep
    assert_success
    refute_output --partial "${message}"
    assert_stderr --partial 'Docker Compose failed (exit 17)'
    assert_stderr --partial "${message}"
    assert_stderr --partial 'karakeep deployment failed'
    refute_stderr --partial 'timed out'
    refute_stderr --partial 'readiness timeout'
    assert_stderr --partial 'health=unhealthy'
    assert_stderr --partial 'unable to read container logs'
    assert_mock_called_with docker 'label=com.docker.compose.project=ix-karakeep'
}

@test "redeploy_truenas_apps: bootstrap reports captured foreground failure on stderr" {
    local message='bootstrap failed: synthetic configuration error'
    prepare_failed_truenas_deploy _bootstrap "${message}" 'status=exited exit_code=0 health=not-configured'
    run --separate-stderr deploy_truenas_and_check_failure _bootstrap
    assert_success
    refute_output --partial "${message}"
    assert_stderr --partial '_bootstrap: Docker Compose failed'
    assert_stderr --partial "${message}"
    assert_stderr --partial 'health=not-configured'
    assert_mock_called_with docker 'up --build --abort-on-container-exit'
    assert_mock_called_with docker 'label=com.docker.compose.project=ix-bootstrap'
}
