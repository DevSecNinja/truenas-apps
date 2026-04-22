#!/usr/bin/env bats
# Unit tests for decrypt_sops_files. Only exercises branches that don't
# actually invoke the SOPS binary (no-ops + missing key errors). The happy
# path is covered by integration tests.

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() {
    common_setup
    mkdir -p "${BASE_DIR}/services"
}
teardown() { common_teardown; }

@test "decrypt_sops_files: no-op when services dir does not exist" {
    rm -rf "${BASE_DIR}/services"
    run decrypt_sops_files
    assert_success
}

@test "decrypt_sops_files: logs and returns when no sops files found" {
    run decrypt_sops_files
    assert_success
    assert_output --partial "No *.sops.env files found"
}

@test "decrypt_sops_files: exits with error when Age key is not set" {
    mkdir -p "${BASE_DIR}/services/plex"
    printf 'encrypted\n' >"${BASE_DIR}/services/plex/secret.sops.env"
    SOPS_AGE_KEY_FILE=""

    run decrypt_sops_files
    assert_failure
    assert_output --partial "SOPS_AGE_KEY_FILE is not set"
}

@test "decrypt_sops_files: exits with error when Age key file does not exist" {
    mkdir -p "${BASE_DIR}/services/plex"
    printf 'encrypted\n' >"${BASE_DIR}/services/plex/secret.sops.env"
    SOPS_AGE_KEY_FILE="${TEST_TMPDIR}/nonexistent.key"

    run decrypt_sops_files
    assert_failure
    assert_output --partial "SOPS Age key file not found"
}

@test "decrypt_sops_files: skips server-specific files in non-server mode" {
    mkdir -p "${BASE_DIR}/services/plex"
    printf 'x\n' >"${BASE_DIR}/services/plex/secret.otherserver.sops.env"
    # No secret.sops.env exists → ends up with zero files after filtering.
    SOPS_AGE_KEY_FILE="${TEST_TMPDIR}/age.key"
    printf 'k\n' >"${SOPS_AGE_KEY_FILE}"

    # With only server-specific files, all are filtered out; we never reach
    # sops invocation. But we don't actually check a specific message here —
    # instead we just ensure no decrypt attempts occur (no .env created).
    run decrypt_sops_files
    assert_success
    assert_file_not_exists "${BASE_DIR}/services/plex/.env"
}
