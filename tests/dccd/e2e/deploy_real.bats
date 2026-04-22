#!/usr/bin/env bats
# E2E tests: real docker compose deploy with minimal test stacks
#
# These tests use real Docker containers and are designed to run in CI
# (GitHub Actions). Skip locally unless DCCD_E2E=1 is set.

setup() {
    load '../helpers/common'
    common_setup

    if [ "${GITHUB_ACTIONS:-}" != "true" ] && [ "${DCCD_E2E:-}" != "1" ]; then
        return 0  # skip in each @test, not here
    fi

    # E2E tests use real Docker — no mocks
    rm -rf "${MOCK_BIN}"
    export PATH="${ORIGINAL_PATH:-${PATH}}"

    # Create a minimal compose stack with a healthcheck container
    mkdir -p "${BASE_DIR}/services/e2e-test"
    cat >"${BASE_DIR}/services/e2e-test/compose.yaml" <<'EOF'
---
services:
  healthcheck:
    image: docker.io/library/busybox:stable
    command: ["sh", "-c", "touch /tmp/healthy && sleep 300"]
    healthcheck:
      test: ["CMD", "test", "-f", "/tmp/healthy"]
      interval: 2s
      timeout: 3s
      retries: 5
    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    mem_limit: 32m
    pids_limit: 50
EOF

    # Initialize a git repo so dccd.sh can operate
    cd "${BASE_DIR}"
    git init --quiet
    git config user.email "test@test.local"
    git config user.name "Test"
    git add -A
    git commit --quiet -m "init"

    DCCD="${REPO_ROOT}/scripts/dccd.sh"
}

teardown() {
    # Clean up Docker resources created by the test
    docker compose -f "${BASE_DIR}/services/e2e-test/compose.yaml" \
        --project-name "e2e-test" down --remove-orphans 2>/dev/null || true

    common_teardown
}

@test "e2e_deploy: compose up creates running containers" {
    if [ "${GITHUB_ACTIONS:-}" != "true" ] && [ "${DCCD_E2E:-}" != "1" ]; then
        skip "E2E tests are skipped locally — set DCCD_E2E=1 to run"
    fi

    # Pre-pull the image to avoid timeout
    docker pull docker.io/library/busybox:stable

    # Deploy using force + no-pull mode (image already pulled)
    run bash "${DCCD}" -d "${BASE_DIR}" -f -n
    assert_success

    # Verify container is running
    run docker compose -f "${BASE_DIR}/services/e2e-test/compose.yaml" \
        --project-name "e2e-test" ps --quiet
    assert_success
    assert_output  # non-empty = container ID present
}

@test "e2e_deploy: force redeploy recreates containers" {
    if [ "${GITHUB_ACTIONS:-}" != "true" ] && [ "${DCCD_E2E:-}" != "1" ]; then
        skip "E2E tests are skipped locally — set DCCD_E2E=1 to run"
    fi

    docker pull docker.io/library/busybox:stable

    # First deploy
    bash "${DCCD}" -d "${BASE_DIR}" -f -n

    # Get container ID
    local first_id
    first_id=$(docker compose -f "${BASE_DIR}/services/e2e-test/compose.yaml" \
        --project-name "e2e-test" ps --quiet)

    # Force redeploy
    bash "${DCCD}" -d "${BASE_DIR}" -f -n

    # Container ID should differ (recreated)
    local second_id
    second_id=$(docker compose -f "${BASE_DIR}/services/e2e-test/compose.yaml" \
        --project-name "e2e-test" ps --quiet)

    [ "${first_id}" != "${second_id}" ]
}
