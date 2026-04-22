#!/usr/bin/env bats
# Unit tests for parse_server_apps()
# These tests need REAL yq on PATH (not mocked)

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup

    # Remove yq mock — parse_server_apps needs real yq
    rm -f "${MOCK_BIN}/yq"

    # Verify yq is available
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not available"
    fi
}

teardown() {
    common_teardown
}

# Helper: write a minimal servers.yaml
_write_servers_yaml() {
    cat >"${BASE_DIR}/servers.yaml" <<'YAML'
---
servers:
  svlazext:
    apps:
      - traefik-forward-auth
      - adguard
      - traefik
  empty-server:
    apps: []
  no-apps-server:
    description: "Has no apps key"
YAML
}

@test "parse_server_apps: requires yq on PATH" {
    # Hide real yq
    local save_path="${PATH}"
    export PATH="${MOCK_BIN}"
    SERVER_NAME="svlazext"
    run parse_server_apps
    assert_failure
    assert_output --partial "yq is required"
    export PATH="${save_path}"
}

@test "parse_server_apps: fails when servers.yaml missing" {
    SERVER_NAME="svlazext"
    run parse_server_apps
    assert_failure
    assert_output --partial "servers.yaml not found"
}

@test "parse_server_apps: fails for unknown server" {
    _write_servers_yaml
    SERVER_NAME="nonexistent"
    run parse_server_apps
    assert_failure
    assert_output --partial "not found in"
    assert_output --partial "Available servers"
}

@test "parse_server_apps: populates SERVER_APPS for valid server" {
    _write_servers_yaml
    SERVER_NAME="svlazext"
    # Create the service directories
    mkdir -p "${BASE_DIR}/services/traefik-forward-auth"
    mkdir -p "${BASE_DIR}/services/adguard"
    mkdir -p "${BASE_DIR}/services/traefik"
    parse_server_apps
    [[ "${#SERVER_APPS[@]}" -eq 3 ]]
}

@test "parse_server_apps: moves traefik to end" {
    _write_servers_yaml
    SERVER_NAME="svlazext"
    mkdir -p "${BASE_DIR}/services/traefik-forward-auth"
    mkdir -p "${BASE_DIR}/services/adguard"
    mkdir -p "${BASE_DIR}/services/traefik"
    parse_server_apps
    [[ "${SERVER_APPS[-1]}" == "traefik" ]]
}

@test "parse_server_apps: fails when app directory missing" {
    _write_servers_yaml
    SERVER_NAME="svlazext"
    # Don't create directories
    run parse_server_apps
    assert_failure
    assert_output --partial "does not exist"
}

@test "parse_server_apps: handles server with no apps key" {
    _write_servers_yaml
    SERVER_NAME="no-apps-server"
    run parse_server_apps
    assert_success
    assert_output --partial "deploying all apps"
}

@test "parse_server_apps: fails for empty apps list" {
    _write_servers_yaml
    SERVER_NAME="empty-server"
    run parse_server_apps
    assert_failure
    assert_output --partial "empty apps list"
}
