#!/usr/bin/env bats
# Integration tests: traefik ordering in parse_server_apps()

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup

    # Need real yq
    rm -f "${MOCK_BIN}/yq"
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not available"
    fi
}

teardown() {
    common_teardown
}

@test "traefik ordering: traefik is last even when listed first" {
    cat >"${BASE_DIR}/servers.yaml" <<'YAML'
---
servers:
  test:
    apps:
      - traefik
      - adguard
      - plex
YAML
    mkdir -p "${BASE_DIR}/services/traefik"
    mkdir -p "${BASE_DIR}/services/adguard"
    mkdir -p "${BASE_DIR}/services/plex"
    SERVER_NAME="test"
    parse_server_apps
    [[ "${SERVER_APPS[-1]}" == "traefik" ]]
    [[ "${SERVER_APPS[0]}" == "adguard" ]]
}

@test "traefik ordering: order preserved when no traefik" {
    cat >"${BASE_DIR}/servers.yaml" <<'YAML'
---
servers:
  test:
    apps:
      - plex
      - adguard
YAML
    mkdir -p "${BASE_DIR}/services/plex"
    mkdir -p "${BASE_DIR}/services/adguard"
    SERVER_NAME="test"
    parse_server_apps
    [[ "${SERVER_APPS[0]}" == "plex" ]]
    [[ "${SERVER_APPS[1]}" == "adguard" ]]
}

@test "traefik ordering: works with traefik as only app" {
    cat >"${BASE_DIR}/servers.yaml" <<'YAML'
---
servers:
  test:
    apps:
      - traefik
YAML
    mkdir -p "${BASE_DIR}/services/traefik"
    SERVER_NAME="test"
    parse_server_apps
    [[ "${#SERVER_APPS[@]}" -eq 1 ]]
    [[ "${SERVER_APPS[0]}" == "traefik" ]]
}
