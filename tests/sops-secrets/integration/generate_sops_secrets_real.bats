#!/usr/bin/env bats
# Integration test using real mise-managed age and SOPS.

setup() {
    load '../helpers/common'
    sops_secrets_setup
}

teardown() {
    sops_secrets_teardown
}

@test "generate-sops-secrets: real SOPS set is encrypted and idempotent" {
    if ! command -v mise >/dev/null 2>&1; then
        skip "mise is unavailable"
    fi
    case "$(uname -s)" in
        Linux*|Darwin*|MINGW*|MSYS*|CYGWIN*) ;;
        *) skip "unsupported platform" ;;
    esac
    export MISE_AUTO_INSTALL=0
    if ! mise exec -- age-keygen --version >/dev/null 2>&1; then
        skip "mise-managed age is unavailable"
    fi
    if ! mise exec -- sops --version >/dev/null 2>&1; then
        skip "mise-managed SOPS is unavailable"
    fi

    local recipient
    local decrypted="${TEST_ROOT}/decrypted.env"
    local hash_before
    local mtime_before
    export SOPS_CONFIG="${TEST_ROOT}/empty-sops-config.yaml"
    : >"${SOPS_CONFIG}"

    rm -f "${KEY_FILE}"
    run mise exec -- age-keygen -o "${KEY_FILE}"
    assert_success
    assert_file_exists "${KEY_FILE}"
    run mise exec -- age-keygen -y "${KEY_FILE}"
    assert_success
    recipient="${output}"

    run mise exec -- sops encrypt \
        --age "${recipient}" \
        --input-type dotenv \
        --output-type dotenv \
        --output "${TARGET}" \
        "${PLAINTEXT}"
    assert_success

    run env SOPS_AGE_KEY_FILE="${KEY_FILE}" \
        bash "${GENERATOR}" "${TARGET}" FIRST=16 SECOND=24
    assert_success
    run grep -q '^sops_mac=ENC\[AES256_GCM,' "${TARGET}"
    assert_success

    run env SOPS_AGE_KEY_FILE="${KEY_FILE}" \
        mise exec -- sops decrypt \
        --input-type dotenv \
        --output-type dotenv \
        --output "${decrypted}" \
        "${TARGET}"
    assert_success
    assert_file_exists "${decrypted}"
    run grep -Eq '^FIRST=[0-9a-f]{32}$' "${decrypted}"
    assert_success
    run grep -Eq '^SECOND=[0-9a-f]{48}$' "${decrypted}"
    assert_success
    run grep -q '^EXISTING=keep-this-value$' "${decrypted}"
    assert_success

    touch -t 200101010101 "${TARGET}"
    hash_before="$(file_sha256 "${TARGET}")"
    mtime_before="$(file_mtime "${TARGET}")"
    run env SOPS_AGE_KEY_FILE="${KEY_FILE}" \
        bash "${GENERATOR}" "${TARGET}" FIRST=16 SECOND=24
    assert_success
    run file_sha256 "${TARGET}"
    assert_success
    assert_output "${hash_before}"
    run file_mtime "${TARGET}"
    assert_success
    assert_output "${mtime_before}"
}
