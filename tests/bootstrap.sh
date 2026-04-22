#!/usr/bin/env bash
# Bootstrap BATS helper libraries (bats-support, bats-assert, bats-file) into
# tests/libs/. These are gitignored and downloaded on demand so the test
# framework works identically on a developer laptop and in CI without
# requiring git submodules.
#
# Usage:
#   tests/bootstrap.sh            # install if missing
#   tests/bootstrap.sh --force    # re-install even if present

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBS_DIR="${SCRIPT_DIR}/libs"

FORCE=0
if [ "${1:-}" = "--force" ]; then
    FORCE=1
fi

# Pinned versions for reproducibility. Renovate tracks github-tags on these.
# renovate: datasource=github-tags depName=bats-core/bats-support
BATS_SUPPORT_VERSION="0.3.0"
# renovate: datasource=github-tags depName=bats-core/bats-assert
BATS_ASSERT_VERSION="2.1.0"
# renovate: datasource=github-tags depName=bats-core/bats-file
BATS_FILE_VERSION="0.4.0"

install_lib() {
    local name="$1" version="$2"
    local dest="${LIBS_DIR}/${name}"

    if [ "${FORCE}" -eq 0 ] && [ -f "${dest}/load.bash" ]; then
        echo "[bootstrap] ${name}@${version} already installed"
        return 0
    fi

    echo "[bootstrap] Installing ${name}@${version} -> ${dest}"
    mkdir -p "${LIBS_DIR}"
    rm -rf "${dest}"

    local url="https://github.com/bats-core/${name}/archive/refs/tags/v${version}.tar.gz"
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT

    if ! curl -fsSL "${url}" -o "${tmp}/${name}.tar.gz"; then
        echo "[bootstrap] ERROR: failed to download ${url}" >&2
        return 1
    fi

    tar -xzf "${tmp}/${name}.tar.gz" -C "${tmp}"
    mv "${tmp}/${name}-${version}" "${dest}"

    trap - EXIT
    rm -rf "${tmp}"
}

install_lib bats-support "${BATS_SUPPORT_VERSION}"
install_lib bats-assert "${BATS_ASSERT_VERSION}"
install_lib bats-file "${BATS_FILE_VERSION}"

echo "[bootstrap] Done. Libraries in ${LIBS_DIR}:"
ls -1 "${LIBS_DIR}"
