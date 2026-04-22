#!/usr/bin/env bash
# Local runner for the dccd BATS test suite.
#
# Bootstraps the bats-support / bats-assert / bats-file helper libraries if
# they are missing, then runs one or more test tiers. E2E tests are excluded
# by default because they need a working Docker daemon and pull images; opt
# in with --e2e or RUN_E2E=1.
#
# Usage:
#   scripts/run-bats-tests.sh                # unit + integration
#   scripts/run-bats-tests.sh --unit         # unit only
#   scripts/run-bats-tests.sh --integration  # integration only
#   scripts/run-bats-tests.sh --e2e          # E2E only (requires Docker)
#   scripts/run-bats-tests.sh --all          # unit + integration + E2E
#   scripts/run-bats-tests.sh --junit        # also write report.xml
#   scripts/run-bats-tests.sh -- path/to/file.bats  # pass-through to bats

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TESTS_ROOT="${REPO_ROOT}/tests"
UNIT_DIR="${TESTS_ROOT}/dccd/unit"
INTEGRATION_DIR="${TESTS_ROOT}/dccd/integration"
E2E_DIR="${TESTS_ROOT}/dccd/e2e"

run_unit=0
run_integration=0
run_e2e=0
want_junit=0
extra_args=()

usage() {
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

if [ "$#" -eq 0 ]; then
    run_unit=1
    run_integration=1
fi

while [ "$#" -gt 0 ]; do
    case "$1" in
        --unit) run_unit=1; shift ;;
        --integration) run_integration=1; shift ;;
        --e2e) run_e2e=1; shift ;;
        --all) run_unit=1; run_integration=1; run_e2e=1; shift ;;
        --junit) want_junit=1; shift ;;
        -h|--help) usage 0 ;;
        --) shift; extra_args=("$@"); break ;;
        *) extra_args+=("$1"); shift ;;
    esac
done

# Resolve a `bats` binary. Prefer mise-managed version when available so
# local runs match CI, but fall back to whatever is on PATH so the suite
# works in minimal dev environments.
if command -v mise >/dev/null 2>&1 && mise exec -- bats --version >/dev/null 2>&1; then
    BATS=(mise exec -- bats)
elif command -v bats >/dev/null 2>&1; then
    BATS=(bats)
else
    echo "ERROR: bats is not installed. Install via 'mise install' or your package manager." >&2
    exit 1
fi

# Ensure bats helper libs are present (gitignored; downloaded on demand).
if [ ! -f "${TESTS_ROOT}/libs/bats-support/load.bash" ] \
    || [ ! -f "${TESTS_ROOT}/libs/bats-assert/load.bash" ] \
    || [ ! -f "${TESTS_ROOT}/libs/bats-file/load.bash" ]; then
    echo "[run-bats-tests] Bootstrapping bats helper libraries..."
    "${TESTS_ROOT}/bootstrap.sh"
fi

# Build the list of test targets.
targets=()
[ "${run_unit}" -eq 1 ] && targets+=("${UNIT_DIR}")
[ "${run_integration}" -eq 1 ] && targets+=("${INTEGRATION_DIR}")
if [ "${run_e2e}" -eq 1 ]; then
    targets+=("${E2E_DIR}")
    # Make sure the E2E guard inside the tests sees the opt-in.
    export RUN_E2E=1
fi

if [ "${#targets[@]}" -eq 0 ] && [ "${#extra_args[@]}" -eq 0 ]; then
    echo "ERROR: nothing to run" >&2
    exit 2
fi

bats_args=(--formatter tap)
if [ "${want_junit}" -eq 1 ] || [ "${CI:-}" = "true" ] || [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    bats_args+=(--report-formatter junit --output "${REPO_ROOT}")
fi

set -x
exec "${BATS[@]}" "${bats_args[@]}" "${extra_args[@]}" "${targets[@]}"
