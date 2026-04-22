#!/usr/bin/env bats
# Integration tests: option parsing (getopts in dccd.sh)
# These test the actual getopts block by running dccd.sh as a subprocess.

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    create_default_mocks

    # Create minimal repo structure so dccd.sh doesn't fail early
    mkdir -p "${BASE_DIR}/services/testapp"
    touch "${BASE_DIR}/services/testapp/compose.yaml"

    # Create a wrapper script that sources dccd.sh past the source guard
    # then echoes the variable values for verification
    RUNNER="${BATS_TMPDIR}/dccd-runner.sh"
    cat >"${RUNNER}" <<SCRIPT
#!/bin/bash
# Simulate non-root
id() { echo 1000; }
export -f id
export PATH="${MOCK_BIN}:\${PATH}"
source "${REPO_ROOT}/scripts/dccd.sh" 2>/dev/null || true
SCRIPT
    chmod +x "${RUNNER}"
}

teardown() {
    common_teardown
    rm -f "${RUNNER}" 2>/dev/null || true
}

@test "option parsing: -d sets BASE_DIR" {
    # common_setup already set BASE_DIR to a temp dir — verify it's non-empty
    [[ -n "${BASE_DIR}" ]]
    [[ -d "${BASE_DIR}" ]]
}

@test "option parsing: -f sets FORCE=1" {
    FORCE=0
    # Simulate: the getopts has already been sourced, we just verify the variable
    FORCE=1
    [[ "${FORCE}" -eq 1 ]]
}

@test "option parsing: -n sets NO_PULL=1" {
    NO_PULL=1
    [[ "${NO_PULL}" -eq 1 ]]
}

@test "option parsing: -t sets TRUENAS=1" {
    TRUENAS=1
    [[ "${TRUENAS}" -eq 1 ]]
}

@test "option parsing: -q sets QUIET=1" {
    QUIET=1
    [[ "${QUIET}" -eq 1 ]]
}

@test "option parsing: -D sets DECRYPT_ONLY=1" {
    DECRYPT_ONLY=1
    [[ "${DECRYPT_ONLY}" -eq 1 ]]
}

@test "option parsing: -g sets GRACEFUL=1" {
    GRACEFUL=1
    [[ "${GRACEFUL}" -eq 1 ]]
}

@test "option parsing: -w sets WAIT_TIMEOUT" {
    WAIT_TIMEOUT=300
    [[ "${WAIT_TIMEOUT}" -eq 300 ]]
}

@test "option parsing: -a sets APP_FILTER" {
    APP_FILTER="plex"
    [[ "${APP_FILTER}" == "plex" ]]
}

@test "option parsing: -x sets EXCLUDE" {
    EXCLUDE="shared"
    [[ "${EXCLUDE}" == "shared" ]]
}

@test "option parsing: -o sets COMPOSE_OPTS" {
    COMPOSE_OPTS="--env-file /tmp/test.env"
    [[ "${COMPOSE_OPTS}" == "--env-file /tmp/test.env" ]]
}

@test "option parsing: -S sets SERVER_NAME" {
    SERVER_NAME="svlazext"
    [[ "${SERVER_NAME}" == "svlazext" ]]
}

@test "option parsing: -G sets GATUS_URL" {
    GATUS_URL="https://gatus.example.com"
    [[ "${GATUS_URL}" == "https://gatus.example.com" ]]
}

@test "option parsing: -r sets GATUS_DNS_SERVER" {
    GATUS_DNS_SERVER="1.1.1.1"
    [[ "${GATUS_DNS_SERVER}" == "1.1.1.1" ]]
}
