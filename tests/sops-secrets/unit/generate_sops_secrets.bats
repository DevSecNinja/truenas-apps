#!/usr/bin/env bats
# Unit tests for generate-sops-secrets.sh with mise/SOPS mocked.

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    sops_secrets_setup
    create_mise_mock
    create_od_mock
}

teardown() {
    sops_secrets_teardown
}

@test "generate-sops-secrets: fills all requested GENERATE values with correctly sized hex" {
    run run_generator FIRST=16 SECOND=24

    assert_success
    run grep -Eq '^FIRST=[0-9a-f]{32}$' "${PLAINTEXT}"
    assert_success
    run grep -Eq '^SECOND=[0-9a-f]{48}$' "${PLAINTEXT}"
    assert_success
    run sops_set_count
    assert_success
    assert_output "2"
    assert_target_usable
}

@test "generate-sops-secrets: second run preserves ciphertext hash and mtime without sops set" {
    run run_generator FIRST=16 SECOND=24
    assert_success
    touch -t 200101010101 "${TARGET}"
    local hash_before
    local mtime_before
    hash_before="$(file_sha256 "${TARGET}")"
    mtime_before="$(file_mtime "${TARGET}")"
    rm -f "${MOCK_LOG}/sops-set.count"
    : >"${MOCK_LOG}/mise.calls"

    run run_generator FIRST=16 SECOND=24

    assert_success
    run file_sha256 "${TARGET}"
    assert_success
    assert_output "${hash_before}"
    run file_mtime "${TARGET}"
    assert_success
    assert_output "${mtime_before}"
    run sops_set_count
    assert_success
    assert_output "0"
    run grep -E '(^|[[:space:]])sops set([[:space:]]|$)' "${MOCK_LOG}/mise.calls"
    assert_failure
}

@test "generate-sops-secrets: preserves requested values that are not GENERATE" {
    run run_generator FIRST=16 EXISTING=16

    assert_success
    run grep -q '^EXISTING=keep-this-value$' "${PLAINTEXT}"
    assert_success
    run sops_set_count
    assert_success
    assert_output "1"
}

@test "generate-sops-secrets: rejects malformed variable arguments before SOPS" {
    run run_generator 'FIRST =16'

    assert_failure
    assert_output --partial "VARIABLE=BYTE_COUNT"
    run test ! -e "${MOCK_LOG}/mise.calls"
    assert_success
}

@test "generate-sops-secrets: rejects duplicate variable arguments before SOPS" {
    run run_generator FIRST=16 FIRST=32

    assert_failure
    assert_output --partial "duplicate"
    assert_output --partial "FIRST"
    run test ! -e "${MOCK_LOG}/mise.calls"
    assert_success
}

@test "generate-sops-secrets: rejects a byte count below 16" {
    run run_generator FIRST=15

    assert_failure
    assert_output --partial "between 16 and 1024"
    run test ! -e "${MOCK_LOG}/mise.calls"
    assert_success
}

@test "generate-sops-secrets: rejects a byte count above 1024" {
    run run_generator FIRST=1025

    assert_failure
    assert_output --partial "between 16 and 1024"
    run test ! -e "${MOCK_LOG}/mise.calls"
    assert_success
}

@test "generate-sops-secrets: rejects a requested variable absent from decrypted target" {
    local hash_before
    hash_before="$(file_sha256 "${TARGET}")"

    run run_generator MISSING=16

    assert_failure
    assert_output --partial "MISSING"
    assert_output --partial "find"
    run file_sha256 "${TARGET}"
    assert_success
    assert_output "${hash_before}"
    run sops_set_count
    assert_success
    assert_output "0"
}

@test "generate-sops-secrets: SOPS_AGE_KEY_CMD takes priority without leaking or persisting key output" {
    local fake_key="FAKE_AGE_PRIVATE_KEY_MUST_NOT_LEAK"
    cat >"${MOCK_BIN}/op" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >>"${MOCK_LOG}/op.calls"
printf '%s%s\n' 'FAKE_AGE_PRIVATE_KEY_' 'MUST_NOT_LEAK'
MOCK
    chmod +x "${MOCK_BIN}/op"
    KEY_FILE="${TEST_ROOT}/missing-fallback-key"
    export SOPS_AGE_KEY_CMD='op read "op://test-vault/test-item/test-field"'

    run run_generator FIRST=16

    assert_success
    refute_output --partial "${fake_key}"
    assert_file_exists "${MOCK_LOG}/op.calls"
    run grep -q '^command$' "${MOCK_LOG}/key-source.calls"
    assert_success
    run grep -R -F "${fake_key}" "${TEST_ROOT}"
    assert_failure
    assert_output ""
}

@test "generate-sops-secrets: missing Age key file fails with setup guidance" {
    KEY_FILE="${TEST_ROOT}/missing-age-key"

    run run_generator FIRST=16

    assert_failure
    assert_output --partial "could not decrypt"
    assert_output --partial "Recommended 1Password setup"
}

@test "generate-sops-secrets: unusable Age key fails clearly without modifying ciphertext" {
    local hash_before
    hash_before="$(file_sha256 "${TARGET}")"
    export MOCK_DECRYPT_EXIT=1

    run run_generator FIRST=16

    assert_failure
    assert_output --partial "could not decrypt"
    run file_sha256 "${TARGET}"
    assert_success
    assert_output "${hash_before}"
    run sops_set_count
    assert_success
    assert_output "0"
}

@test "generate-sops-secrets: random generation failure leaves encrypted target usable" {
    local hash_before
    hash_before="$(file_sha256 "${TARGET}")"
    export MOCK_OD_FAIL=1

    run run_generator FIRST=16

    assert_failure
    run file_sha256 "${TARGET}"
    assert_success
    assert_output "${hash_before}"
    assert_target_usable
}

@test "generate-sops-secrets: sops set failure leaves the encrypted target usable" {
    local hash_before
    hash_before="$(file_sha256 "${TARGET}")"
    export MOCK_SET_FAIL=1
    export MOCK_SET_CORRUPT=1

    run run_generator FIRST=16

    assert_failure
    run file_sha256 "${TARGET}"
    assert_success
    assert_output "${hash_before}"
    assert_target_usable
}
