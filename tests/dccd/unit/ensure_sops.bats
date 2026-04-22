#!/usr/bin/env bats
# Unit tests for ensure_sops()

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup

    # Override uname mock to return x86_64
    cat >"${MOCK_BIN}/uname" <<'MOCK'
#!/bin/bash
echo "x86_64"
MOCK
    chmod +x "${MOCK_BIN}/uname"
}

teardown() {
    common_teardown
}

@test "ensure_sops: uses existing binary when present" {
    mkdir -p "${SOPS_INSTALL_DIR}"
    local sops_bin="${SOPS_INSTALL_DIR}/sops-${SOPS_VERSION}"
    echo '#!/bin/bash' >"${sops_bin}"
    chmod +x "${sops_bin}"
    ensure_sops
    [[ "${SOPS_BIN}" == "${sops_bin}" ]]
}

@test "ensure_sops: downloads when binary missing" {
    # Create smart curl mock that handles both binary and checksum downloads
    cat >"${MOCK_BIN}/curl" <<'MOCK'
#!/bin/bash
echo "$@" >> "${MOCK_LOG:-/tmp}/curl.calls"
# Find the -o flag and write to that file
output_file=""
for i in "${@}"; do
    if [ "${prev}" = "-o" ]; then
        output_file="${i}"
    fi
    prev="${i}"
done
if [ -n "${output_file}" ]; then
    if echo "${output_file}" | grep -q "checksums"; then
        # Write a checksums file with matching hash
        local_hash=$(sha256sum /dev/null | awk '{print $1}')
        echo "${local_hash}  sops-v3.9.0.linux.amd64" > "${output_file}"
    else
        # Write an empty binary
        echo "" > "${output_file}"
    fi
fi
exit 0
MOCK
    chmod +x "${MOCK_BIN}/curl"

    # Create sha256sum mock that returns a fixed hash
    cat >"${MOCK_BIN}/sha256sum" <<'MOCK'
#!/bin/bash
echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  $1"
MOCK
    chmod +x "${MOCK_BIN}/sha256sum"

    # Need grep and awk on path
    cat >"${MOCK_BIN}/mv" <<'MOCK'
#!/bin/bash
command mv "$@"
MOCK
    chmod +x "${MOCK_BIN}/mv"

    cat >"${MOCK_BIN}/chmod" <<'MOCK'
#!/bin/bash
command chmod "$@"
MOCK
    chmod +x "${MOCK_BIN}/chmod"

    run ensure_sops
    assert_success
    assert_output --partial "Downloading SOPS"
}

@test "ensure_sops: fails on curl download error" {
    create_mock "curl" 1 ""
    create_mock "uname" 0 "x86_64"
    run ensure_sops
    assert_failure
    assert_output --partial "Failed to download SOPS"
}

@test "ensure_sops: maps aarch64 to arm64" {
    # Override uname to return aarch64
    cat >"${MOCK_BIN}/uname" <<'MOCK'
#!/bin/bash
echo "aarch64"
MOCK
    chmod +x "${MOCK_BIN}/uname"

    # Create curl mock that records the URL
    cat >"${MOCK_BIN}/curl" <<'MOCK'
#!/bin/bash
echo "$@" >> "${MOCK_LOG:-/tmp}/curl.calls"
output_file=""
for i in "${@}"; do
    if [ "${prev}" = "-o" ]; then
        output_file="${i}"
    fi
    prev="${i}"
done
if [ -n "${output_file}" ]; then
    echo "" > "${output_file}"
fi
exit 0
MOCK
    chmod +x "${MOCK_BIN}/curl"

    create_mock "sha256sum" 0 "abc123  dummy"
    run ensure_sops
    # It should try arm64 URL (we expect it to fail at checksum but the URL should contain arm64)
    assert_mock_called_with "curl" "arm64"
}

@test "ensure_sops: fails on unsupported architecture" {
    cat >"${MOCK_BIN}/uname" <<'MOCK'
#!/bin/bash
echo "riscv64"
MOCK
    chmod +x "${MOCK_BIN}/uname"

    run ensure_sops
    assert_failure
    assert_output --partial "Unsupported architecture"
}

@test "ensure_sops: fails on checksum mismatch" {
    # curl mock that downloads but with bad checksum
    cat >"${MOCK_BIN}/curl" <<'MOCK'
#!/bin/bash
output_file=""
for i in "${@}"; do
    if [ "${prev}" = "-o" ]; then
        output_file="${i}"
    fi
    prev="${i}"
done
if [ -n "${output_file}" ]; then
    if echo "${output_file}" | grep -q "checksums"; then
        echo "0000000000000000000000000000000000000000000000000000000000000000  sops-v3.9.0.linux.amd64" > "${output_file}"
    else
        echo "binary-content" > "${output_file}"
    fi
fi
exit 0
MOCK
    chmod +x "${MOCK_BIN}/curl"

    run ensure_sops
    assert_failure
    assert_output --partial "checksum mismatch"
}
