#!/usr/bin/env bats
# End-to-end smoke test: brings up a minimal busybox stack through a real
# `docker compose up -d`, asserts containers are running, then tears it down.
#
# This test is automatically skipped on machines where Docker is not
# available. It is also skipped when run outside of CI unless the user opts
# in with RUN_E2E=1, so `bats tests/` on a laptop does not unexpectedly pull
# images.

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() {
    common_setup

    # Skip unless explicitly requested or running in CI.
    if [ "${RUN_E2E:-0}" != "1" ] && [ "${CI:-}" != "true" ] && [ "${GITHUB_ACTIONS:-}" != "true" ]; then
        skip "E2E tests disabled — set RUN_E2E=1 or run in CI to enable"
    fi

    # Skip when Docker is not usable from this shell.
    if ! command -v docker >/dev/null 2>&1; then
        skip "docker not installed"
    fi
    if ! docker info >/dev/null 2>&1; then
        skip "docker daemon not reachable"
    fi

    # Build a tiny compose stack under $BASE_DIR/services/.
    mkdir -p "${BASE_DIR}/services/smoke"
    cat >"${BASE_DIR}/services/smoke/compose.yaml" <<'YAML'
---
services:
    smoke:
        image: docker.io/library/busybox:stable
        container_name: dccd-e2e-smoke
        command: ["sh", "-c", "sleep 30"]
        healthcheck:
            test: ["CMD", "true"]
            interval: 2s
            timeout: 2s
            retries: 3
        read_only: true
        mem_limit: 64m
        pids_limit: 50
YAML
}

teardown() {
    # Always try to clean up the stack even if the test failed.
    if command -v docker >/dev/null 2>&1; then
        docker rm -f dccd-e2e-smoke >/dev/null 2>&1 || true
        if [ -d "${BASE_DIR:-}" ]; then
            docker compose -f "${BASE_DIR}/services/smoke/compose.yaml" -p smoke down --remove-orphans >/dev/null 2>&1 || true
        fi
    fi
    common_teardown
}

@test "e2e: docker compose up/down against a minimal busybox stack" {
    run docker compose -f "${BASE_DIR}/services/smoke/compose.yaml" -p smoke up -d --wait --wait-timeout 30
    assert_success

    run docker ps --filter "name=dccd-e2e-smoke" --format "{{.Names}}"
    assert_success
    assert_output --partial "dccd-e2e-smoke"

    run docker compose -f "${BASE_DIR}/services/smoke/compose.yaml" -p smoke down --remove-orphans
    assert_success

    run docker ps -a --filter "name=dccd-e2e-smoke" --format "{{.Names}}"
    assert_success
    refute_output --partial "dccd-e2e-smoke"
}
