#!/usr/bin/env bats
# Integration tests for validate-sops-secrets.sh using real mise-managed Age
# and SOPS, mirroring generate_sops_secrets_real.bats.

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

create_real_encrypted_target_from_plaintext() {
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

@test "validate-sops-secrets: real SOPS accepts a fully resolved encrypted target" {
    configure_real_tools
    cat >"${PLAINTEXT}" <<'EOF'
DOMAINNAME=example.com
DB_ENC_PASSPHRASE=some-real-passphrase-value-not-a-sentinel
EOF
    create_real_encrypted_target_from_plaintext "${KEY_FILE}"
    snapshot_target

    run env SOPS_AGE_KEY_FILE="${KEY_FILE}" bash "${VALIDATOR}" "${TARGET}" DOMAINNAME DB_ENC_PASSPHRASE

    assert_success
    refute_output --partial "example.com"
    refute_output --partial "some-real-passphrase-value-not-a-sentinel"
    assert_target_unchanged
}

@test "validate-sops-secrets: real SOPS reports an unresolved GENERATE sentinel without leaking values" {
    configure_real_tools
    cat >"${PLAINTEXT}" <<'EOF'
DOMAINNAME=example.com
DB_ENC_PASSPHRASE=GENERATE
EOF
    create_real_encrypted_target_from_plaintext "${KEY_FILE}"
    snapshot_target

    run env SOPS_AGE_KEY_FILE="${KEY_FILE}" bash "${VALIDATOR}" "${TARGET}" DOMAINNAME DB_ENC_PASSPHRASE

    assert_failure
    assert_output --partial "unresolved sentinel"
    assert_output --partial "DB_ENC_PASSPHRASE"
    refute_output --partial "example.com"
    assert_target_unchanged
}

@test "validate-sops-secrets: real SOPS reports a missing required variable" {
    configure_real_tools
    cat >"${PLAINTEXT}" <<'EOF'
DOMAINNAME=example.com
EOF
    create_real_encrypted_target_from_plaintext "${KEY_FILE}"
    snapshot_target

    run env SOPS_AGE_KEY_FILE="${KEY_FILE}" bash "${VALIDATOR}" "${TARGET}" DOMAINNAME NEVER_DEFINED

    assert_failure
    assert_output --partial "missing required variable"
    assert_output --partial "NEVER_DEFINED"
    assert_target_unchanged
}

@test "validate-sops-secrets: mismatched real Age identity fails decryption without modifying ciphertext" {
    configure_real_tools
    cat >"${PLAINTEXT}" <<'EOF'
DOMAINNAME=example.com
EOF
    create_real_encrypted_target_from_plaintext "${KEY_FILE}"
    local wrong_key="${TEST_ROOT}/wrong-age-keys.txt"
    run mise exec -- age-keygen -o "${wrong_key}"
    assert_success
    snapshot_target

    run env SOPS_AGE_KEY_FILE="${wrong_key}" bash "${VALIDATOR}" "${TARGET}" DOMAINNAME

    assert_failure
    assert_output --partial "could not decrypt"
    assert_target_unchanged
}
