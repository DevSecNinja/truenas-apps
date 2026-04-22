#!/usr/bin/env bats
# Unit tests for decrypt_sops_files()

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup

    # Set up age key file
    SOPS_AGE_KEY_FILE="${BASE_DIR}/age.key"
    touch "${SOPS_AGE_KEY_FILE}"

    # Create SOPS binary stub
    mkdir -p "${SOPS_INSTALL_DIR}"
    SOPS_BIN="${SOPS_INSTALL_DIR}/sops-${SOPS_VERSION}"
    cat >"${SOPS_BIN}" <<'MOCK'
#!/bin/bash
# Fake sops -d: echo the file content as "decrypted"
if [ "$1" = "-d" ]; then
    echo "DECRYPTED_KEY=value"
    exit 0
fi
exit 1
MOCK
    chmod +x "${SOPS_BIN}"
}

teardown() {
    common_teardown
}

@test "decrypt_sops_files: returns early when services dir missing" {
    rmdir "${BASE_DIR}/services"
    run decrypt_sops_files
    assert_success
}

@test "decrypt_sops_files: returns early when no sops files found" {
    mkdir -p "${BASE_DIR}/services/testapp"
    run decrypt_sops_files
    assert_success
    assert_output --partial "No *.sops.env files found"
}

@test "decrypt_sops_files: fails when SOPS_AGE_KEY_FILE not set" {
    mkdir -p "${BASE_DIR}/services/testapp"
    touch "${BASE_DIR}/services/testapp/secret.sops.env"
    SOPS_AGE_KEY_FILE=""
    run decrypt_sops_files
    assert_failure
    assert_output --partial "SOPS_AGE_KEY_FILE is not set"
}

@test "decrypt_sops_files: fails when age key file missing" {
    mkdir -p "${BASE_DIR}/services/testapp"
    touch "${BASE_DIR}/services/testapp/secret.sops.env"
    SOPS_AGE_KEY_FILE="${BASE_DIR}/nonexistent.key"
    run decrypt_sops_files
    assert_failure
    assert_output --partial "Age key file not found"
}

@test "decrypt_sops_files: decrypts all sops files" {
    mkdir -p "${BASE_DIR}/services/app1"
    mkdir -p "${BASE_DIR}/services/app2"
    touch "${BASE_DIR}/services/app1/secret.sops.env"
    touch "${BASE_DIR}/services/app2/secret.sops.env"
    run decrypt_sops_files
    assert_success
    assert_output --partial "Decrypted 2 secret file(s)"
}

@test "decrypt_sops_files: creates .env from secret.sops.env" {
    mkdir -p "${BASE_DIR}/services/testapp"
    touch "${BASE_DIR}/services/testapp/secret.sops.env"
    decrypt_sops_files
    assert_file_exists "${BASE_DIR}/services/testapp/.env"
}

@test "decrypt_sops_files: sets 600 permissions on .env" {
    mkdir -p "${BASE_DIR}/services/testapp"
    touch "${BASE_DIR}/services/testapp/secret.sops.env"
    decrypt_sops_files
    local perms
    perms=$(stat -c '%a' "${BASE_DIR}/services/testapp/.env")
    [[ "${perms}" == "600" ]]
}

@test "decrypt_sops_files: skips config/data/backups directories" {
    mkdir -p "${BASE_DIR}/services/testapp/config"
    mkdir -p "${BASE_DIR}/services/testapp/data"
    mkdir -p "${BASE_DIR}/services/testapp/backups"
    touch "${BASE_DIR}/services/testapp/config/secret.sops.env"
    touch "${BASE_DIR}/services/testapp/data/secret.sops.env"
    touch "${BASE_DIR}/services/testapp/backups/secret.sops.env"
    run decrypt_sops_files
    assert_success
    assert_output --partial "No *.sops.env files found"
}

@test "decrypt_sops_files: server mode only decrypts assigned apps" {
    SERVER_APPS=("app1")
    mkdir -p "${BASE_DIR}/services/app1"
    mkdir -p "${BASE_DIR}/services/app2"
    touch "${BASE_DIR}/services/app1/secret.sops.env"
    touch "${BASE_DIR}/services/app2/secret.sops.env"
    run decrypt_sops_files
    assert_success
    assert_output --partial "Decrypted 1 secret file(s)"
}

@test "decrypt_sops_files: server mode prefers server-specific secret file" {
    SERVER_NAME="svlazext"
    SERVER_APPS=("app1")
    mkdir -p "${BASE_DIR}/services/app1"
    touch "${BASE_DIR}/services/app1/secret.sops.env"
    touch "${BASE_DIR}/services/app1/secret.svlazext.sops.env"
    run decrypt_sops_files
    assert_success
    assert_output --partial "Skipping base secret.sops.env"
    assert_output --partial "Decrypted 1 secret file(s)"
}

@test "decrypt_sops_files: server mode skips other server files" {
    SERVER_NAME="svlazext"
    SERVER_APPS=("app1")
    mkdir -p "${BASE_DIR}/services/app1"
    touch "${BASE_DIR}/services/app1/secret.sops.env"
    touch "${BASE_DIR}/services/app1/secret.other-server.sops.env"
    run decrypt_sops_files
    assert_success
    assert_output --partial "Skipping secret.other-server.sops.env"
}
