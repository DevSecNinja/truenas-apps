#!/usr/bin/env bash
# Shared BATS setup helpers for dccd tests.
#
# Usage (in every .bats file):
#   load '../helpers/common.bash'
#
#   setup_file() { common_setup_file; }
#   setup()      { common_setup; }
#   teardown()   { common_teardown; }
#
# common_setup_file() sources dccd.sh once per file using DCCD_TESTING=1.
# common_setup() creates an isolated temp dir + mock PATH per test and resets
# all mutable globals so tests are fully independent.

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# Resolve repo root dynamically so tests at any depth can source the script.
if [ -z "${REPO_ROOT:-}" ]; then
    if REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}" && git rev-parse --show-toplevel 2>/dev/null)"; then
        :
    else
        REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
    fi
    export REPO_ROOT
fi
export DCCD_SCRIPT="${REPO_ROOT}/scripts/dccd.sh"

# ---------------------------------------------------------------------------
# Library loading (bats-support / bats-assert / bats-file)
# ---------------------------------------------------------------------------

_load_bats_libs() {
    local libs_dir="${REPO_ROOT}/tests/libs"
    local lib
    for lib in bats-support bats-assert bats-file; do
        if [ -f "${libs_dir}/${lib}/load.bash" ]; then
            # shellcheck source=/dev/null
            load "${libs_dir}/${lib}/load.bash"
        fi
    done
}

# ---------------------------------------------------------------------------
# Per-file setup: currently a no-op. BATS isolates each @test in a subshell,
# so function definitions from `setup_file` do NOT propagate into tests —
# sourcing dccd.sh must happen in `setup()`. Keeping this function defined
# makes the three-line boilerplate in every .bats file symmetric.
# ---------------------------------------------------------------------------

common_setup_file() {
    :
}

_source_dccd() {
    export DCCD_TESTING=1
    # shellcheck source=/dev/null
    source "${DCCD_SCRIPT}"
    # dccd.sh enables `set -euo pipefail`; that is appropriate for prod but
    # hostile to the BATS test runner (unset var refs and non-zero exits from
    # helper functions would abort the whole test case). Restore permissive
    # shell behaviour in the test process — `run` still captures failures of
    # the function-under-test correctly because it spawns a subshell.
    set +euo pipefail
}

# ---------------------------------------------------------------------------
# Per-test setup: isolated temp dir, mock bin dir, default mocks, reset state.
# ---------------------------------------------------------------------------

common_setup() {
    _load_bats_libs

    # Isolated temp dir per test (uses BATS_TMPDIR for parallel-safety).
    TEST_TMPDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/dccd-test.XXXXXX")"
    export TEST_TMPDIR

    MOCK_BIN="${TEST_TMPDIR}/bin"
    MOCK_LOG="${TEST_TMPDIR}/calls"
    mkdir -p "${MOCK_BIN}" "${MOCK_LOG}"
    export MOCK_BIN MOCK_LOG

    # Prepend mock bin so stubs shadow real commands.
    export ORIG_PATH="${PATH}"
    export PATH="${MOCK_BIN}:${PATH}"

    # Load mock helpers (defines create_mock, create_mock_passthrough, etc.)
    # shellcheck source=./mocks.bash
    source "${REPO_ROOT}/tests/dccd/helpers/mocks.bash"

    # Source dccd.sh so function definitions are available in the test shell.
    # Must happen per-test: BATS isolates @test bodies in subshells that do
    # NOT inherit function definitions from setup_file.
    _source_dccd

    # Reset all mutable globals that dccd.sh functions touch. Without this,
    # tests that run after a mutating test would see stale state.
    _DEPLOY_ERRORS=0
    _DEPLOY_ATTEMPTED=0
    _DEPLOY_CHANGED=0
    _DEPLOY_UNCHANGED=0
    _DEPLOY_FAILED_APPS=()
    SERVER_APPS=()
    SERVER_NAME=""
    SOPS_BIN=""
    SOPS_INSTALL_DIR="${TEST_TMPDIR}/sops-install"
    SOPS_AGE_KEY_FILE=""
    BASE_DIR="${TEST_TMPDIR}/repo"
    QUIET=0
    _QUIET_BUF=""
    FORCE=0
    NO_PULL=0
    TRUENAS=0
    APP_FILTER=""
    REMOVE_APP=""
    COMPOSE_OPTS=""
    COMPOSE_PROFILE_ARGS=()
    GATUS_URL=""
    GATUS_CD_TOKEN=""
    GATUS_DNS_SERVER=""

    # SUDO override: dccd.sh sets SUDO="sudo" so docker commands are prefixed
    # with it. In tests we bypass sudo entirely so the docker mock runs
    # directly without needing a functional sudo stub that has to re-exec.
    SUDO=""

    export _DEPLOY_ERRORS _DEPLOY_ATTEMPTED _DEPLOY_CHANGED _DEPLOY_UNCHANGED
    export SERVER_NAME SOPS_BIN SOPS_INSTALL_DIR SOPS_AGE_KEY_FILE BASE_DIR
    export QUIET _QUIET_BUF FORCE NO_PULL TRUENAS APP_FILTER REMOVE_APP
    export COMPOSE_OPTS GATUS_URL GATUS_CD_TOKEN GATUS_DNS_SERVER SUDO

    # Default mocks that every test needs to avoid syslog side-effects and
    # non-deterministic timestamps from real `logger` / `date` calls.
    create_mock logger 0 ""
    create_mock_stdout date "2024-01-01 00:00:00"

    # Fallback assertion helpers (used when bats-assert / bats-file are not
    # installed yet — bootstrap.sh installs them; this keeps tests runnable
    # in a minimal environment).
    if ! command -v assert_success >/dev/null 2>&1; then
        # shellcheck disable=SC2317
        assert_success() {
            if [ "${status}" -ne 0 ]; then
                echo "expected success, got status=${status}"
                echo "output: ${output}"
                return 1
            fi
        }
        # shellcheck disable=SC2317
        assert_failure() {
            if [ "${status}" -eq 0 ]; then
                echo "expected failure, got status=0"
                echo "output: ${output}"
                return 1
            fi
        }
        # shellcheck disable=SC2317
        assert_output() {
            local partial=0
            if [ "${1:-}" = "--partial" ]; then
                partial=1
                shift
            fi
            local expected="$1"
            if [ "${partial}" -eq 1 ]; then
                if [[ "${output}" != *"${expected}"* ]]; then
                    echo "expected output to contain: ${expected}"
                    echo "got: ${output}"
                    return 1
                fi
            else
                if [ "${output}" != "${expected}" ]; then
                    echo "expected: ${expected}"
                    echo "got: ${output}"
                    return 1
                fi
            fi
        }
        # shellcheck disable=SC2317
        refute_output() {
            local partial=0
            if [ "${1:-}" = "--partial" ]; then
                partial=1
                shift
            fi
            local needle="$1"
            if [ "${partial}" -eq 1 ]; then
                if [[ "${output}" == *"${needle}"* ]]; then
                    echo "expected output NOT to contain: ${needle}"
                    echo "got: ${output}"
                    return 1
                fi
            else
                if [ "${output}" = "${needle}" ]; then
                    echo "expected output NOT equal to: ${needle}"
                    return 1
                fi
            fi
        }
        # shellcheck disable=SC2317
        assert_equal() {
            if [ "$1" != "$2" ]; then
                echo "expected '$2', got '$1'"
                return 1
            fi
        }
        # shellcheck disable=SC2317
        assert_file_exists() {
            if [ ! -e "$1" ]; then
                echo "expected file to exist: $1"
                return 1
            fi
        }
        # shellcheck disable=SC2317
        assert_file_not_exists() {
            if [ -e "$1" ]; then
                echo "expected file NOT to exist: $1"
                return 1
            fi
        }
    fi
}

common_teardown() {
    PATH="${ORIG_PATH:-${PATH}}"
    if [ -n "${TEST_TMPDIR:-}" ] && [ -d "${TEST_TMPDIR}" ]; then
        rm -rf "${TEST_TMPDIR}"
    fi
}
