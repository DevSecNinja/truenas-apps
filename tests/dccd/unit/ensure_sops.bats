#!/usr/bin/env bats
# Unit tests for ensure_sops.

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }

@test "ensure_sops: returns immediately when binary already exists (cached)" {
    mkdir -p "${SOPS_INSTALL_DIR}"
    local cached="${SOPS_INSTALL_DIR}/sops-${SOPS_VERSION}"
    printf '#!/bin/sh\n' >"${cached}"
    chmod +x "${cached}"

    # curl must never be invoked on the cached path.
    create_mock curl 1 "should-not-be-called"

    run ensure_sops
    assert_success
    [ "${SOPS_BIN}" = "${cached}" ]
    [ "$(mock_call_count curl)" = "0" ]
}

@test "ensure_sops: exits with error on unsupported architecture" {
    create_mock uname 0 "mips64"

    run ensure_sops
    assert_failure
    assert_output --partial "Unsupported architecture"
}

@test "ensure_sops: downloads and verifies checksum on fresh install" {
    create_mock uname 0 "x86_64"

    # Two curl invocations: first the binary, second the checksums file.
    # The checksums file MUST contain the line expected by dccd — grep uses
    # pattern "<binary_name>$".
    local binary_name="sops-${SOPS_VERSION}.linux.amd64"
    local fake_bin_path="${TEST_TMPDIR}/fake-sops"
    printf '#!/bin/sh\necho sops\n' >"${fake_bin_path}"
    chmod +x "${fake_bin_path}"
    local expected_hash
    expected_hash=$(sha256sum "${fake_bin_path}" | awk '{print $1}')

    create_mock_script curl "
# Args form: -fsSL -o <path> <url>
dest=\"\$4\"
url=\"\$5\"
case \"\${url}\" in
    *checksums.txt) printf '%s  %s\n' \"${expected_hash}\" \"${binary_name}\" >\"\${dest}\" ;;
    *) cat \"${fake_bin_path}\" >\"\${dest}\" ;;
esac
exit 0
"

    run ensure_sops
    assert_success
    assert_output --partial "checksum verified"
    assert_output --partial "SOPS ${SOPS_VERSION} installed"
    [ -x "${SOPS_BIN}" ]
}

@test "ensure_sops: exits when checksum mismatches" {
    create_mock uname 0 "x86_64"

    create_mock_script curl "
dest=\"\$4\"
url=\"\$5\"
case \"\${url}\" in
    *checksums.txt) printf 'deadbeef  sops-${SOPS_VERSION}.linux.amd64\n' >\"\${dest}\" ;;
    *) printf 'fake\n' >\"\${dest}\" ;;
esac
exit 0
"

    run ensure_sops
    assert_failure
    assert_output --partial "checksum mismatch"
}

@test "ensure_sops: exits when download fails" {
    create_mock uname 0 "x86_64"
    create_mock curl 22 ""

    run ensure_sops
    assert_failure
    assert_output --partial "Failed to download SOPS"
}
