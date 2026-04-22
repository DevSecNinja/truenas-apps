#!/usr/bin/env bats
# Integration tests: decrypt-only mode

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    create_default_mocks

    # Set up sops binary and age key
    SOPS_AGE_KEY_FILE="${BASE_DIR}/age.key"
    touch "${SOPS_AGE_KEY_FILE}"
    mkdir -p "${SOPS_INSTALL_DIR}"
    SOPS_BIN="${SOPS_INSTALL_DIR}/sops-${SOPS_VERSION}"
    cat >"${SOPS_BIN}" <<'MOCK'
#!/bin/bash
if [ "$1" = "-d" ]; then
    echo "DECRYPTED=true"
    exit 0
fi
exit 1
MOCK
    chmod +x "${SOPS_BIN}"
}

teardown() {
    common_teardown
}

@test "decrypt-only: decrypt_sops_files creates .env files" {
    mkdir -p "${BASE_DIR}/services/app1"
    touch "${BASE_DIR}/services/app1/secret.sops.env"
    decrypt_sops_files
    assert_file_exists "${BASE_DIR}/services/app1/.env"
    run cat "${BASE_DIR}/services/app1/.env"
    assert_output --partial "DECRYPTED=true"
}
