#!/bin/bash
# Download BATS helper libraries for testing.
# Versions are pinned below and managed by Renovate.
# The libraries are downloaded to tests/libs/ (gitignored).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBS_DIR="${SCRIPT_DIR}/libs"

# renovate: datasource=github-releases depName=bats-core/bats-support
BATS_SUPPORT_VERSION="v0.3.0"
# renovate: datasource=github-releases depName=bats-core/bats-assert
BATS_ASSERT_VERSION="v2.1.0"
# renovate: datasource=github-releases depName=bats-core/bats-file
BATS_FILE_VERSION="v0.4.0"

download_lib() {
    local name="$1" version="$2" dest="${LIBS_DIR}/${1}"

    if [ -f "${dest}/load.bash" ]; then
        return 0
    fi

    echo "Downloading ${name} ${version}..."
    local url="https://github.com/bats-core/${name}/archive/refs/tags/${version}.tar.gz"
    local tmpdir
    tmpdir=$(mktemp -d)

    curl -fsSL "${url}" | tar -xz -C "${tmpdir}"
    rm -rf "${dest}"
    mv "${tmpdir}/${name}-${version#v}" "${dest}"
    rm -rf "${tmpdir}"
}

mkdir -p "${LIBS_DIR}"
download_lib "bats-support" "${BATS_SUPPORT_VERSION}"
download_lib "bats-assert" "${BATS_ASSERT_VERSION}"
download_lib "bats-file" "${BATS_FILE_VERSION}"
