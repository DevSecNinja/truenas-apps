#!/usr/bin/env bats
# Unit tests for run_compose_command()
#
# Verifies that:
#   - When SUDO is unset, no sudo prefix is added.
#   - When SUDO is set, sudo is the first argv element.
#   - When _CONFIG_HASH_ENV_FILE is set, --env-file flags are appended so
#     compose can interpolate ${CONFIG_HASH:-} in labels. This avoids passing
#     CONFIG_HASH through sudo's environment, which sudoers SETENV restrictions
#     on TrueNAS-style hosts would block (causing a password prompt).

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
}

teardown() {
    common_teardown
}

@test "run_compose_command: no SUDO prefix when SUDO is empty" {
    SUDO=""
    # shellcheck disable=SC2034
    COMPOSE_OPTS=""
    # shellcheck disable=SC2034
    COMPOSE_PROFILE_ARGS=()
    # shellcheck disable=SC2034
    _CONFIG_HASH_ENV_FILE=""
    cat >"${MOCK_BIN}/docker" <<'MOCK'
#!/bin/bash
printf 'docker-args:%s\n' "$@"
MOCK
    chmod +x "${MOCK_BIN}/docker"
    create_mock "sudo" 0 "sudo-was-called"

    run run_compose_command --version
    assert_success
    refute_output --partial "sudo-was-called"
    assert_line --index 0 "docker-args:compose --version"
}

@test "run_compose_command: prepends sudo when SUDO is set" {
    # shellcheck disable=SC2034  # consumed by run_compose_command via dynamic globals
    SUDO="sudo"
    # shellcheck disable=SC2034
    COMPOSE_OPTS=""
    # shellcheck disable=SC2034
    COMPOSE_PROFILE_ARGS=()
    # shellcheck disable=SC2034
    _CONFIG_HASH_ENV_FILE=""
    cat >"${MOCK_BIN}/sudo" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@"
MOCK
    chmod +x "${MOCK_BIN}/sudo"

    run run_compose_command --project-name foo up
    assert_success
    # No `env VAR=...` wrapping — sudoers SETENV restrictions on TrueNAS-style
    # hosts would block that. CONFIG_HASH is passed via --env-file instead
    # (when _CONFIG_HASH_ENV_FILE is set, see other tests).
    assert_line --index 0 "docker"
    assert_line --index 1 "compose"
}

@test "run_compose_command: appends --env-file for hash file only when no .env exists" {
    # shellcheck disable=SC2034
    SUDO=""
    # shellcheck disable=SC2034
    COMPOSE_OPTS=""
    # shellcheck disable=SC2034
    COMPOSE_PROFILE_ARGS=()
    local app_dir="${BATS_TEST_TMPDIR}/app-no-env"
    mkdir -p "${app_dir}"
    printf 'CONFIG_HASH=abc123\n' >"${app_dir}/.config-hash.env"
    # shellcheck disable=SC2034
    _CONFIG_HASH_ENV_FILE="${app_dir}/.config-hash.env"
    cat >"${MOCK_BIN}/docker" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@"
MOCK
    chmod +x "${MOCK_BIN}/docker"

    run run_compose_command up -d
    assert_success
    assert_line --index 0 "compose"
    assert_line --index 1 "--env-file"
    assert_line --index 2 "${app_dir}/.config-hash.env"
    # No --env-file for .env (it does not exist)
    refute_output --partial "${app_dir}/.env"
}

@test "run_compose_command: appends both --env-file flags when .env and hash file exist" {
    # shellcheck disable=SC2034
    SUDO=""
    # shellcheck disable=SC2034
    COMPOSE_OPTS=""
    # shellcheck disable=SC2034
    COMPOSE_PROFILE_ARGS=()
    local app_dir="${BATS_TEST_TMPDIR}/app-with-env"
    mkdir -p "${app_dir}"
    printf 'SECRET=value\n' >"${app_dir}/.env"
    printf 'CONFIG_HASH=abc123\n' >"${app_dir}/.config-hash.env"
    # shellcheck disable=SC2034
    _CONFIG_HASH_ENV_FILE="${app_dir}/.config-hash.env"
    cat >"${MOCK_BIN}/docker" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@"
MOCK
    chmod +x "${MOCK_BIN}/docker"

    run run_compose_command up -d
    assert_success
    assert_line --index 0 "compose"
    # .env comes first, hash file second (later wins on key conflicts)
    assert_line --index 1 "--env-file"
    assert_line --index 2 "${app_dir}/.env"
    assert_line --index 3 "--env-file"
    assert_line --index 4 "${app_dir}/.config-hash.env"
}

@test "run_compose_command: no --env-file when _CONFIG_HASH_ENV_FILE is unset" {
    # shellcheck disable=SC2034
    SUDO=""
    # shellcheck disable=SC2034
    COMPOSE_OPTS=""
    # shellcheck disable=SC2034
    COMPOSE_PROFILE_ARGS=()
    unset _CONFIG_HASH_ENV_FILE
    cat >"${MOCK_BIN}/docker" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@"
MOCK
    chmod +x "${MOCK_BIN}/docker"

    run run_compose_command --version
    assert_success
    refute_output --partial "--env-file"
}
