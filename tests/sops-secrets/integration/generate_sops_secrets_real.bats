#!/usr/bin/env bats
# Integration tests using real mise-managed Age and SOPS with an offline op fake.

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    sops_secrets_setup
}

teardown() {
    sops_secrets_teardown
}

require_real_tool() {
    local tool="${1}"

    if ! command -v mise >/dev/null 2>&1; then
        if [[ "${CI:-}" == "true" ]]; then
            fail "mise is required in CI"
            return 1
        fi
        skip "mise is unavailable"
    fi
    if ! mise exec -- "${tool}" --version >/dev/null 2>&1; then
        if [[ "${CI:-}" == "true" ]]; then
            fail "mise-managed ${tool} is required in CI"
            return 1
        fi
        skip "mise-managed ${tool} is unavailable"
    fi
}

create_real_encrypted_target() {
    local key_file="${1}"
    local recipient

    rm -f "${key_file}"
    run mise exec -- age-keygen -o "${key_file}"
    assert_success
    assert_file_exists "${key_file}"
    run mise exec -- age-keygen -y "${key_file}"
    assert_success
    recipient="${output}"
    run mise exec -- sops encrypt \
        --age "${recipient}" \
        --input-type dotenv \
        --output-type dotenv \
        --output "${TARGET}" \
        "${PLAINTEXT}"
    assert_success
}

configure_real_tools() {
    case "$(uname -s)" in
        Linux*|Darwin*|MINGW*|MSYS*|CYGWIN*) ;;
        *)
            if [[ "${CI:-}" == "true" ]]; then
                fail "real SOPS integration test platform is unsupported in CI"
                return 1
            fi
            skip "unsupported platform"
            ;;
    esac
    export MISE_AUTO_INSTALL=0
    require_real_tool age-keygen
    require_real_tool sops
    export SOPS_CONFIG="${TEST_ROOT}/empty-sops-config.yaml"
    : >"${SOPS_CONFIG}"
}

@test "generate-sops-secrets: real SOPS uses the exact op reference and is idempotent" {
    configure_real_tools
    create_real_encrypted_target "${KEY_FILE}"
    create_op_mock
    export MOCK_OP_OUTPUT_FILE="${KEY_FILE}"
    export SOPS_AGE_KEY_CMD='op read "op://TestVault/AgeKey/private-key"'
    local decrypted
    local first
    local second
    local existing
    local mtime_before

    snapshot_target
    run bash "${GENERATOR}" "${TARGET}" FIRST=16 SECOND=24
    assert_success
    run file_sha256 "${TARGET}"
    assert_success
    refute_output "${TARGET_HASH_BEFORE}"
    assert_no_generated_temp_files

    decrypted="$(
        env SOPS_AGE_KEY_CMD="${SOPS_AGE_KEY_CMD}" \
            mise exec -- sops decrypt \
            --input-type dotenv \
            --output-type dotenv \
            "${TARGET}"
    )" || fail "real SOPS could not decrypt generated fixture"
    first="$(printf '%s\n' "${decrypted}" | awk -F= '$1 == "FIRST" { print $2 }')"
    second="$(printf '%s\n' "${decrypted}" | awk -F= '$1 == "SECOND" { print $2 }')"
    existing="$(printf '%s\n' "${decrypted}" | awk -F= '$1 == "EXISTING" { print $2 }')"
    [[ "${first}" =~ ^[0-9a-f]{32}$ ]] || fail "FIRST has unexpected format"
    [[ "${second}" =~ ^[0-9a-f]{48}$ ]] || fail "SECOND has unexpected format"
    [[ "${existing}" == "keep-this-value" ]] || fail "existing value was changed"
    unset decrypted first second existing
    run grep -Fx 'read op://TestVault/AgeKey/private-key' "${MOCK_LOG}/op.calls"
    assert_success

    touch -t 200101010101 "${TARGET}"
    snapshot_target
    mtime_before="$(file_mtime "${TARGET}")"
    run bash "${GENERATOR}" "${TARGET}" FIRST=16 SECOND=24
    assert_success
    assert_target_unchanged
    run file_mtime "${TARGET}"
    assert_success
    assert_output "${mtime_before}"
}

@test "generate-sops-secrets: nonzero op leaves real ciphertext unchanged" {
    configure_real_tools
    create_real_encrypted_target "${KEY_FILE}"
    create_op_mock
    export MOCK_OP_EXIT=1
    export SOPS_AGE_KEY_CMD='op read "op://TestVault/AgeKey/private-key"'
    snapshot_target

    run bash "${GENERATOR}" "${TARGET}" FIRST=16

    assert_failure
    assert_output --partial "could not decrypt"
    assert_target_unchanged
    run grep -Fx 'read op://TestVault/AgeKey/private-key' "${MOCK_LOG}/op.calls"
    assert_success
}

@test "generate-sops-secrets: mismatched op identity leaves real ciphertext unchanged" {
    configure_real_tools
    create_real_encrypted_target "${KEY_FILE}"
    local wrong_key="${TEST_ROOT}/wrong-age-keys.txt"
    run mise exec -- age-keygen -o "${wrong_key}"
    assert_success
    create_op_mock
    export MOCK_OP_OUTPUT_FILE="${wrong_key}"
    export SOPS_AGE_KEY_CMD='op read "op://TestVault/AgeKey/private-key"'
    snapshot_target

    run bash "${GENERATOR}" "${TARGET}" FIRST=16

    assert_failure
    assert_output --partial "could not decrypt"
    assert_target_unchanged
    run grep -Fx 'read op://TestVault/AgeKey/private-key' "${MOCK_LOG}/op.calls"
    assert_success
}
