#!/usr/bin/env bats
# Unit tests for parse_server_apps.

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() {
    common_setup

    # Build a fake repo layout used by most tests in this file.
    mkdir -p "${BASE_DIR}/services/plex"
    mkdir -p "${BASE_DIR}/services/traefik"
    mkdir -p "${BASE_DIR}/services/adguard"
    cat >"${BASE_DIR}/servers.yaml" <<YAML
servers:
  svlazext:
    apps:
      - plex
      - traefik
      - adguard
  empty-server:
    apps: []
  no-apps-server: {}
YAML
}
teardown() { common_teardown; }

@test "parse_server_apps: exits with error when yq is missing" {
    # Remove yq from PATH by unsetting it (not on MOCK_BIN by default; but
    # system may have it). Reset PATH to exclude it.
    PATH="${MOCK_BIN}"
    SERVER_NAME="svlazext"

    run parse_server_apps
    assert_failure
    assert_output --partial "yq is required"
}

@test "parse_server_apps: exits when servers.yaml is missing" {
    create_mock yq 0 "svlazext"
    rm "${BASE_DIR}/servers.yaml"
    SERVER_NAME="svlazext"

    run parse_server_apps
    assert_failure
    assert_output --partial "servers.yaml not found"
}

@test "parse_server_apps: exits when server not found in servers.yaml" {
    # Real yq is available in PATH in CI; use it so yq query returns empty.
    PATH="${ORIG_PATH}"
    SERVER_NAME="does-not-exist"

    run parse_server_apps
    assert_failure
    assert_output --partial "Server 'does-not-exist' not found"
}

@test "parse_server_apps: populates SERVER_APPS for valid server" {
    PATH="${ORIG_PATH}"
    SERVER_NAME="svlazext"

    parse_server_apps
    # At least 3 entries expected.
    [ "${#SERVER_APPS[@]}" -eq 3 ]
}

@test "parse_server_apps: moves traefik to the end of the list" {
    PATH="${ORIG_PATH}"
    SERVER_NAME="svlazext"

    parse_server_apps
    # Last element must be traefik for correct external-network ordering.
    [ "${SERVER_APPS[-1]}" = "traefik" ]
}

@test "parse_server_apps: returns without populating when server has no apps key" {
    PATH="${ORIG_PATH}"
    SERVER_NAME="no-apps-server"

    parse_server_apps
    [ "${#SERVER_APPS[@]}" -eq 0 ]
}

@test "parse_server_apps: exits when server has empty apps list" {
    PATH="${ORIG_PATH}"
    SERVER_NAME="empty-server"

    run parse_server_apps
    assert_failure
    assert_output --partial "empty apps list"
}

@test "parse_server_apps: exits when an assigned app has no services/ directory" {
    PATH="${ORIG_PATH}"
    SERVER_NAME="svlazext"
    rm -rf "${BASE_DIR}/services/plex"

    run parse_server_apps
    assert_failure
    assert_output --partial "services/plex/ does not exist"
}
