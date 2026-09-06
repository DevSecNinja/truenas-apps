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
    snapshot_target
    run run_generator FIRST=16 SECOND=24

    assert_success
    run file_sha256 "${TARGET}"
    assert_success
    refute_output "${TARGET_HASH_BEFORE}"
    run grep -Eq '^FIRST=[0-9a-f]{32}$' "${PLAINTEXT}"
    assert_success
    run grep -Eq '^SECOND=[0-9a-f]{48}$' "${PLAINTEXT}"
    assert_success
    run sops_set_count
    assert_success
    assert_output "2"
    assert_target_usable
    assert_no_generated_temp_files
}

@test "generate-sops-secrets: second run preserves ciphertext hash and mtime without sops set" {
    run run_generator FIRST=16 SECOND=24
    assert_success
    touch -t 200101010101 "${TARGET}"
    local mtime_before
    snapshot_target
    mtime_before="$(file_mtime "${TARGET}")"
    rm -f "${MOCK_LOG}/sops-set.count"
    : >"${MOCK_LOG}/mise.calls"

    run run_generator FIRST=16 SECOND=24

    assert_success
    assert_target_unchanged
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
    snapshot_target
    run run_generator FIRST=16 EXISTING=16

    assert_success
    run file_sha256 "${TARGET}"
    assert_success
    refute_output "${TARGET_HASH_BEFORE}"
    run grep -q '^EXISTING=keep-this-value$' "${PLAINTEXT}"
    assert_success
    run sops_set_count
    assert_success
    assert_output "1"
    assert_no_generated_temp_files
}

@test "generate-sops-secrets: rejects malformed variable arguments before SOPS" {
    snapshot_target
    run run_generator 'FIRST =16'

    assert_failure
    assert_output --partial "VARIABLE=BYTE_COUNT"
    run test ! -e "${MOCK_LOG}/mise.calls"
    assert_success
    assert_target_unchanged
}

@test "generate-sops-secrets: rejects duplicate variable arguments before SOPS" {
    snapshot_target
    run run_generator FIRST=16 FIRST=32

    assert_failure
    assert_output --partial "duplicate"
    assert_output --partial "FIRST"
    run test ! -e "${MOCK_LOG}/mise.calls"
    assert_success
    assert_target_unchanged
}

@test "generate-sops-secrets: rejects a byte count below 16" {
    snapshot_target
    run run_generator FIRST=15

    assert_failure
    assert_output --partial "between 16 and 1024"
    run test ! -e "${MOCK_LOG}/mise.calls"
    assert_success
    assert_target_unchanged
}

@test "generate-sops-secrets: rejects a byte count above 1024" {
    snapshot_target
    run run_generator FIRST=1025

    assert_failure
    assert_output --partial "between 16 and 1024"
    run test ! -e "${MOCK_LOG}/mise.calls"
    assert_success
    assert_target_unchanged
}

@test "generate-sops-secrets: rejects overflowing byte count before arithmetic" {
    snapshot_target
    run run_generator FIRST=18446744073709551632

    assert_failure
    assert_output --partial "between 16 and 1024"
    run test ! -e "${MOCK_LOG}/mise.calls"
    assert_success
    assert_target_unchanged
}

@test "generate-sops-secrets: rejects a requested variable absent from decrypted target" {
    snapshot_target

    run run_generator MISSING=16

    assert_failure
    assert_output --partial "MISSING"
    assert_output --partial "find"
    assert_target_unchanged
    run sops_set_count
    assert_success
    assert_output "0"
}

@test "generate-sops-secrets: accepts a multiline identity file from SOPS_AGE_KEY_CMD without leaking it" {
    local fake_key="AGE-SECRET-KEY-1TESTTEST"
    create_op_mock
    export MOCK_OP_OUTPUT="# created: 2026-09-06
# public key: age1example
${fake_key}"
    KEY_FILE="${TEST_ROOT}/missing-fallback-key"
    export SOPS_AGE_KEY_CMD='op read "op://TestVault/AgeKey/private-key"'
    snapshot_target

    run run_generator FIRST=16

    assert_success
    refute_output --partial "${fake_key}"
    run file_sha256 "${TARGET}"
    assert_success
    refute_output "${TARGET_HASH_BEFORE}"
    assert_file_exists "${MOCK_LOG}/op.calls"
    run grep -Fx 'read op://TestVault/AgeKey/private-key' "${MOCK_LOG}/op.calls"
    assert_success
    run grep -q '^command$' "${MOCK_LOG}/key-source.calls"
    assert_success
    run grep -R -F "${fake_key}" "${TEST_ROOT}"
    assert_failure
    assert_output ""
    assert_no_generated_temp_files
}

@test "generate-sops-secrets: accepts a supported PQ identity from SOPS_AGE_KEY_CMD" {
    create_op_mock
    export MOCK_OP_OUTPUT="AGE-SECRET-KEY-PQ-1TESTTEST"
    KEY_FILE="${TEST_ROOT}/missing-fallback-key"
    export SOPS_AGE_KEY_CMD='op read "op://TestVault/AgeKey/private-key"'
    snapshot_target

    run run_generator FIRST=16

    assert_success
    run file_sha256 "${TARGET}"
    assert_success
    refute_output "${TARGET_HASH_BEFORE}"
    assert_no_generated_temp_files
}

@test "generate-sops-secrets: rejects multiple mixed Age identities without modifying ciphertext" {
    create_op_mock
    export MOCK_OP_OUTPUT="AGE-SECRET-KEY-1TESTTEST
AGE-SECRET-KEY-PQ-1TESTTEST"
    KEY_FILE="${TEST_ROOT}/missing-fallback-key"
    export SOPS_AGE_KEY_CMD='op read "op://TestVault/AgeKey/private-key"'
    snapshot_target

    run run_generator FIRST=16

    assert_failure
    assert_output --partial "could not decrypt"
    assert_target_unchanged
}

@test "generate-sops-secrets: missing op fails before SOPS without modifying ciphertext" {
    export SOPS_AGE_KEY_CMD='op read "op://TestVault/AgeKey/private-key"'
    PATH="${MOCK_BIN}:/usr/bin:/bin"
    snapshot_target

    run run_generator FIRST=16

    assert_failure
    assert_output --partial "op CLI is unavailable"
    run test ! -e "${MOCK_LOG}/mise.calls"
    assert_success
    assert_target_unchanged
}

@test "generate-sops-secrets: unauthenticated op fails before SOPS without modifying ciphertext" {
    create_op_mock
    export MOCK_OP_EXIT=1
    export SOPS_AGE_KEY_CMD='op read "op://TestVault/AgeKey/private-key"'
    snapshot_target

    run run_generator FIRST=16

    assert_failure
    assert_output --partial "could not decrypt"
    assert_target_unchanged
}

@test "generate-sops-secrets: invalid op output fails before SOPS without modifying ciphertext" {
    create_op_mock
    export MOCK_OP_OUTPUT="not-an-age-identity"
    export SOPS_AGE_KEY_CMD='op read "op://TestVault/AgeKey/private-key"'
    snapshot_target

    run run_generator FIRST=16

    assert_failure
    assert_output --partial "could not decrypt"
    assert_target_unchanged
}

@test "generate-sops-secrets: flattened comment-prefixed identity fails without modifying ciphertext" {
    create_op_mock
    export MOCK_OP_OUTPUT="# created: today # public key: age1example AGE-SECRET-KEY-1TESTTEST"
    export SOPS_AGE_KEY_CMD='op read "op://TestVault/AgeKey/private-key"'
    snapshot_target

    run run_generator FIRST=16

    assert_failure
    assert_output --partial "could not decrypt"
    assert_target_unchanged
}

@test "generate-sops-secrets: does not shell-evaluate key command metacharacters" {
    local marker="${TEST_ROOT}/shell-evaluated"
    create_op_mock
    export MOCK_OP_OUTPUT="AGE-SECRET-KEY-1TESTTEST"
    export SOPS_AGE_KEY_CMD="op read \"op://TestVault/AgeKey/private-key\"; touch \"${marker}\""
    snapshot_target

    run run_generator FIRST=16

    assert_failure
    assert_output --partial "could not decrypt"
    run test ! -e "${marker}"
    assert_success
    assert_target_unchanged
}

@test "generate-sops-secrets: missing Age key file fails with setup guidance" {
    KEY_FILE="${TEST_ROOT}/missing-age-key"
    snapshot_target

    run run_generator FIRST=16

    assert_failure
    assert_output --partial "could not decrypt"
    assert_output --partial "Recommended 1Password setup"
    assert_target_unchanged
}

@test "generate-sops-secrets: unusable Age key fails clearly without modifying ciphertext" {
    snapshot_target
    export MOCK_DECRYPT_EXIT=1

    run run_generator FIRST=16

    assert_failure
    assert_output --partial "could not decrypt"
    assert_target_unchanged
    run sops_set_count
    assert_success
    assert_output "0"
}

@test "generate-sops-secrets: random generation failure leaves encrypted target usable" {
    snapshot_target
    export MOCK_OD_FAIL=1

    run run_generator FIRST=16

    assert_failure
    assert_target_unchanged
    assert_target_usable
}

@test "generate-sops-secrets: sops set failure leaves the encrypted target usable" {
    snapshot_target
    export MOCK_SET_FAIL=1
    export MOCK_SET_CORRUPT=1

    run run_generator FIRST=16

    assert_failure
    assert_target_unchanged
    assert_target_usable
}
