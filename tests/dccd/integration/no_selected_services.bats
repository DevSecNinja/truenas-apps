#!/usr/bin/env bats
# Mocked deployment flows: an empty service selection must be a side-effect-free skip.

load '../helpers/diagnostics'

setup_file() {
    diagnostics_require_helpers
}

setup() {
    diagnostics_setup
    NO_SELECTION_APP="${BASE_DIR}/services/optional-app"
    mkdir -p "${NO_SELECTION_APP}/config"
    # Model profile-gated apps (e.g. Frigate), not the unprofiled Open Archiver stack.
    # Compose selection is mocked here.
    # This .env is an empty disposable fixture, never the worktree service .env.
    touch "${NO_SELECTION_APP}/compose.yaml" "${NO_SELECTION_APP}/.env" \
        "${NO_SELECTION_APP}/config/settings.conf"
    export CONFIG_HASH=previous-app-hash
    _CONFIG_HASH_ENV_FILE="${BASE_DIR}/previous-app.config-hash.env"
    _DEPLOY_ATTEMPTED=7
    # Leave pulls enabled: the no-selection guard, not NO_PULL, must prevent them.
    NO_PULL=0
    create_mock docker 0 ""
}

teardown() {
    common_teardown
}

deploy_and_assert_no_selection_state() {
    "$@" || return
    # Assert in the same shell as the deploy; BATS run uses a subshell, so
    # checking the parent's counters afterwards would hide an increment.
    assert_equal "${_DEPLOY_ATTEMPTED}" 7 || return
    assert_equal "${_DEPLOY_ERRORS}" 0 || return
    assert_equal "${_DEPLOY_CHANGED}" 0 || return
    assert_equal "${_DEPLOY_UNCHANGED}" 0 || return
    assert_equal "${_DEPLOY_RESTARTED}" 0 || return
    assert_equal "${#_DEPLOY_FAILED_APPS[@]}" 0 || return
    assert_equal "${CONFIG_HASH}" previous-app-hash || return
    assert_equal "${_CONFIG_HASH_ENV_FILE}" "${BASE_DIR}/previous-app.config-hash.env"
}

assert_no_selection_side_effects() {
    local compose_args="$1" expected_calls
    printf -v expected_calls 'compose %s config --quiet\ncompose %s config --services' \
        "${compose_args}" "${compose_args}"
    # An exact two-call log excludes pull/up as well as image snapshots,
    # config-watch rendering and every other unexpected Docker command.
    run get_mock_call_args docker
    assert_success || return
    assert_output "${expected_calls}" || return
    assert_file_exists "${NO_SELECTION_APP}/.env" || return
    assert_size_zero "${NO_SELECTION_APP}/.env" || return
    assert_file_exists "${NO_SELECTION_APP}/config/settings.conf" || return
    assert_size_zero "${NO_SELECTION_APP}/config/settings.conf" || return
    assert_file_not_exists "${NO_SELECTION_APP}/.config-hash.env" || return
    assert_dir_not_exists "${NO_SELECTION_APP}/data" || return
    assert_dir_not_exists "${NO_SELECTION_APP}/backups" || return
    assert_mock_not_called git || return
    assert_mock_not_called sops || return
    assert_mock_not_called yq
}

@test "redeploy_compose_file: optional app with no selected services skips pull, up, config mutation and attempted increment" {
    run deploy_and_assert_no_selection_state redeploy_compose_file "${NO_SELECTION_APP}/compose.yaml"
    assert_success
    assert_output --partial "optional-app: Skipping — no services match active profiles"
    assert_no_selection_side_effects "-f ${NO_SELECTION_APP}/compose.yaml"
}

@test "redeploy_truenas_apps: optional app with no selected services leaves deployment state untouched" {
    TRUENAS=1
    TRUENAS_APPS_BASE="${BASE_DIR}/truenas-config"
    COMPOSE_PROFILE_ARGS=(--profile surveillance)
    local rendered="${TRUENAS_APPS_BASE}/optional-app/versions/1.0/templates/rendered"
    mkdir -p "${rendered}"
    touch "${rendered}/docker-compose.yaml"
    assert_dir_exists "${rendered}"

    run deploy_and_assert_no_selection_state redeploy_truenas_apps
    assert_success
    assert_output --partial "optional-app: Skipping — no services match active profiles"
    assert_no_selection_side_effects \
        "--profile surveillance --project-name ix-optional-app --file ${rendered}/docker-compose.yaml"
}
