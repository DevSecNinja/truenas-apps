#!/usr/bin/env bats
# Integration tests: server mode deploy

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    create_default_mocks

    # Need real yq for server mode tests
    rm -f "${MOCK_BIN}/yq"
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not available"
    fi
}

teardown() {
    common_teardown
}

@test "server mode: decrypt_sops_files only processes SERVER_APPS" {
    # Set up sops
    SOPS_AGE_KEY_FILE="${BASE_DIR}/age.key"
    touch "${SOPS_AGE_KEY_FILE}"
    mkdir -p "${SOPS_INSTALL_DIR}"
    SOPS_BIN="${SOPS_INSTALL_DIR}/sops-${SOPS_VERSION}"
    cat >"${SOPS_BIN}" <<'MOCK'
#!/bin/bash
if [ "$1" = "-d" ]; then echo "DECRYPTED=1"; exit 0; fi
exit 1
MOCK
    chmod +x "${SOPS_BIN}"

    SERVER_APPS=("app1")
    mkdir -p "${BASE_DIR}/services/app1"
    mkdir -p "${BASE_DIR}/services/app2"
    touch "${BASE_DIR}/services/app1/secret.sops.env"
    touch "${BASE_DIR}/services/app2/secret.sops.env"

    run decrypt_sops_files
    assert_success
    assert_output --partial "Decrypted 1 secret file(s)"
    assert_file_exists "${BASE_DIR}/services/app1/.env"
    assert_file_not_exists "${BASE_DIR}/services/app2/.env"
}

@test "server mode: parse_server_apps populates array" {
    cat >"${BASE_DIR}/servers.yaml" <<'YAML'
---
servers:
  testhost:
    apps:
      - plex
      - sonarr
YAML
    mkdir -p "${BASE_DIR}/services/plex"
    mkdir -p "${BASE_DIR}/services/sonarr"
    SERVER_NAME="testhost"
    parse_server_apps
    [[ "${#SERVER_APPS[@]}" -eq 2 ]]
    [[ "${SERVER_APPS[0]}" == "plex" ]]
    [[ "${SERVER_APPS[1]}" == "sonarr" ]]
}

@test "server mode: compose override files are detected" {
    # Verify compose override pattern is available for server mode
    mkdir -p "${BASE_DIR}/services/adguard"
    touch "${BASE_DIR}/services/adguard/compose.yaml"
    touch "${BASE_DIR}/services/adguard/compose.svlazext.yaml"
    local override="${BASE_DIR}/services/adguard/compose.svlazext.yaml"
    [[ -f "${override}" ]]
}
