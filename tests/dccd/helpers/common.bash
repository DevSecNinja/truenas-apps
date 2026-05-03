#!/usr/bin/env bash
# Shared BATS test setup/teardown for dccd.sh tests.
# Load in each .bats file: load '../helpers/common'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"

# Auto-install BATS helper libraries if missing
if [ ! -f "${REPO_ROOT}/tests/libs/bats-support/load.bash" ]; then
    bash "${REPO_ROOT}/tests/setup_libs.sh"
fi

load "${REPO_ROOT}/tests/libs/bats-support/load"
load "${REPO_ROOT}/tests/libs/bats-assert/load"
load "${REPO_ROOT}/tests/libs/bats-file/load"

# Directories used by every test
MOCK_BIN=""
MOCK_LOG=""
BASE_DIR=""

common_setup() {
    # Create isolated temp directories
    MOCK_BIN="$(mktemp -d "${BATS_TMPDIR}/dccd-mock-bin.XXXXXX")"
    MOCK_LOG="$(mktemp -d "${BATS_TMPDIR}/dccd-mock-log.XXXXXX")"
    BASE_DIR="$(mktemp -d "${BATS_TMPDIR}/dccd-base.XXXXXX")"

    # Save original PATH for E2E tests that need real commands
    export ORIGINAL_PATH="${PATH}"

    # Prepend mock bin to PATH
    export PATH="${MOCK_BIN}:${PATH}"

    # Create default mocks for logger and date (used by log.sh)
    cat >"${MOCK_BIN}/logger" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "${MOCK_BIN}/logger"

    cat >"${MOCK_BIN}/date" <<'MOCK'
#!/bin/bash
echo "2026-01-01 00:00:00"
MOCK
    chmod +x "${MOCK_BIN}/date"

    # Save temp dirs before sourcing (dccd.sh resets globals to "")
    local _saved_base_dir="${BASE_DIR}"
    local _saved_mock_bin="${MOCK_BIN}"
    local _saved_mock_log="${MOCK_LOG}"

    # Source dccd.sh with the testing guard — loads all functions but skips main
    DCCD_TESTING=1 source "${REPO_ROOT}/scripts/dccd.sh"

    # Disable strict mode (tests need to handle failures gracefully)
    set +euo pipefail

    # Restore saved dirs and reset all mutable globals AFTER sourcing
    BASE_DIR="${_saved_base_dir}"
    MOCK_BIN="${_saved_mock_bin}"
    MOCK_LOG="${_saved_mock_log}"
    SOPS_INSTALL_DIR="${BASE_DIR}/bin"
    SOPS_AGE_KEY_FILE="${BASE_DIR}/age.key"
    SOPS_BIN=""
    SERVER_NAME=""
    SERVER_APPS=()
    _DEPLOY_ERRORS=0
    _DEPLOY_ATTEMPTED=0
    _DEPLOY_CHANGED=0
    _DEPLOY_UNCHANGED=0
    _DEPLOY_RESTARTED=0
    _DEPLOY_FAILED_APPS=()
    TRUENAS=0
    TRUENAS_APPS_BASE="/mnt/.ix-apps/app_configs"
    NO_PULL=0
    FORCE=0
    APP_FILTER=""
    EXCLUDE=""
    QUIET=0
    _QUIET_BUF=""
    DECRYPT_ONLY=0
    GRACEFUL=0
    COMPOSE_OPTS=""
    COMPOSE_PROFILE_ARGS=()
    GATUS_URL=""
    GATUS_DNS_SERVER=""
    WAIT_TIMEOUT=120
    SUDO=""
    _ORIG_ARGS=()
    _SCRIPT_PATH=""

    # Create the services directory
    mkdir -p "${BASE_DIR}/services"
}

common_teardown() {
    # Clean up temp directories
    rm -rf "${MOCK_BIN}" "${MOCK_LOG}" "${BASE_DIR}" 2>/dev/null || true
}
