#!/usr/bin/env bats
# Unit tests for run_compose_command()
#
# Verifies that:
#   - When SUDO is unset, no sudo prefix and no env assignment are added.
#   - When SUDO is set, sudo is prefixed AND CONFIG_HASH=<value> is passed as
#     a per-command env assignment so it survives sudo's env_reset policy
#     (which is what makes the config.sha256 label recreate-trigger work).
#   - COMPOSE_OPTS word-splits into argv elements.

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
    COMPOSE_OPTS=""
    COMPOSE_PROFILE_ARGS=()
    # Mock both sudo and docker so we can detect which one is invoked
    create_mock "sudo" 0 "sudo-was-called"
    create_mock "docker" 0 "docker-direct"

    CONFIG_HASH="deadbeef" run run_compose_command --version
    assert_success
    assert_output --partial "docker-direct"
    refute_output --partial "sudo-was-called"
}

@test "run_compose_command: passes CONFIG_HASH via sudo when SUDO is set" {
    # shellcheck disable=SC2034  # consumed by run_compose_command via dynamic globals
    SUDO="sudo"
    # shellcheck disable=SC2034
    COMPOSE_OPTS=""
    # shellcheck disable=SC2034
    COMPOSE_PROFILE_ARGS=()
    # Mock sudo to echo all its args so we can inspect the argv it would build.
    create_mock "sudo" 0 ""
    cat >"${MOCK_BIN}/sudo" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@"
MOCK
    chmod +x "${MOCK_BIN}/sudo"

    CONFIG_HASH="265b9bbe" run run_compose_command --project-name foo up
    assert_success
    # The first argv element must be the CONFIG_HASH=<value> env assignment,
    # which sudo treats as a per-command env var that survives env_reset.
    assert_line --index 0 "CONFIG_HASH=265b9bbe"
    assert_line --index 1 "docker"
    assert_line --index 2 "compose"
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
    # Even with CONFIG_HASH unset, the assignment must be emitted (with empty
    # value) so the absence is explicit and the call signature is consistent.
    assert_line --index 0 "CONFIG_HASH="
}
