#!/usr/bin/env bats
# Unit tests for run_compose_command()
#
# Verifies that:
#   - When SUDO is unset, no sudo prefix is added.
#   - When SUDO is set, sudo is the first argv element.
#   - In both cases the compose invocation is wrapped in `env CONFIG_HASH=...`
#     so the value reaches docker compose for ${CONFIG_HASH:-} interpolation
#     in compose labels (config.sha256 recreate triggers). This sidesteps
#     sudoers SETENV restrictions on TrueNAS-style hosts.

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
}

teardown() {
    common_teardown
}

@test "run_compose_command: no SUDO prefix when SUDO is empty; env wrapper present" {
    SUDO=""
    # shellcheck disable=SC2034
    COMPOSE_OPTS=""
    # shellcheck disable=SC2034
    COMPOSE_PROFILE_ARGS=()
    # Mock env so we can capture the argv it sees and confirm sudo is NOT in it.
    cat >"${MOCK_BIN}/env" <<'MOCK'
#!/bin/bash
printf 'env-args:%s\n' "$@"
MOCK
    chmod +x "${MOCK_BIN}/env"
    create_mock "sudo" 0 "sudo-was-called"

    CONFIG_HASH="deadbeef" run run_compose_command --version
    assert_success
    refute_output --partial "sudo-was-called"
    assert_line --index 0 "env-args:CONFIG_HASH=deadbeef"
}

@test "run_compose_command: passes CONFIG_HASH via env wrapper when SUDO is set" {
    # shellcheck disable=SC2034  # consumed by run_compose_command via dynamic globals
    SUDO="sudo"
    # shellcheck disable=SC2034
    COMPOSE_OPTS=""
    # shellcheck disable=SC2034
    COMPOSE_PROFILE_ARGS=()
    # Mock sudo to echo all its args so we can inspect the argv it would build.
    cat >"${MOCK_BIN}/sudo" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@"
MOCK
    chmod +x "${MOCK_BIN}/sudo"

    CONFIG_HASH="265b9bbe" run run_compose_command --project-name foo up
    assert_success
    # `env CONFIG_HASH=value` runs `env` as the command, so sudoers SETENV
    # restrictions don't apply (it's argv to env, not a sudo-level env override).
    assert_line --index 0 "env"
    assert_line --index 1 "CONFIG_HASH=265b9bbe"
    assert_line --index 2 "docker"
    assert_line --index 3 "compose"
}

@test "run_compose_command: passes empty CONFIG_HASH when var is unset" {
    # shellcheck disable=SC2034  # consumed by run_compose_command via dynamic globals
    SUDO="sudo"
    # shellcheck disable=SC2034
    COMPOSE_OPTS=""
    # shellcheck disable=SC2034
    COMPOSE_PROFILE_ARGS=()
    cat >"${MOCK_BIN}/sudo" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@"
MOCK
    chmod +x "${MOCK_BIN}/sudo"

    unset CONFIG_HASH
    run run_compose_command up
    assert_success
    # Even with CONFIG_HASH unset, the wrapper must be emitted with empty value
    # so the call signature stays consistent.
    assert_line --index 0 "env"
    assert_line --index 1 "CONFIG_HASH="
}
