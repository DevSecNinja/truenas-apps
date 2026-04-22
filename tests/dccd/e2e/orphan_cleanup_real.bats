#!/usr/bin/env bats
# E2E tests: real orphan detection after simulated git pull removes a service
#
# Skip locally unless DCCD_E2E=1 is set.

setup() {
    load '../helpers/common'
    common_setup

    if [ "${GITHUB_ACTIONS:-}" != "true" ] && [ "${DCCD_E2E:-}" != "1" ]; then
        return 0
    fi

    rm -rf "${MOCK_BIN}"
    export PATH="${ORIGINAL_PATH:-${PATH}}"

    # Create two services
    for app in e2e-keep e2e-orphan; do
        mkdir -p "${BASE_DIR}/services/${app}"
        cat >"${BASE_DIR}/services/${app}/compose.yaml" <<EOF
---
services:
  worker:
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
    done

    cd "${BASE_DIR}"
    git init --quiet
    git config user.email "test@test.local"
    git config user.name "Test"
    git add -A
    git commit --quiet -m "init"

    DCCD="${REPO_ROOT}/scripts/dccd.sh"
}

teardown() {
    for app in e2e-keep e2e-orphan; do
        docker compose -f "${BASE_DIR}/services/${app}/compose.yaml" \
            --project-name "${app}" down --remove-orphans 2>/dev/null || true
    done
    # Label-based cleanup in case compose file is gone
    docker ps -aq --filter "label=com.docker.compose.project=e2e-orphan" 2>/dev/null |
        xargs -r docker rm -f 2>/dev/null || true
    common_teardown
}

@test "e2e_orphan: cleanup_orphaned_projects tears down removed service" {
    if [ "${GITHUB_ACTIONS:-}" != "true" ] && [ "${DCCD_E2E:-}" != "1" ]; then
        skip "E2E tests are skipped locally — set DCCD_E2E=1 to run"
    fi

    docker pull docker.io/library/busybox:stable

    # Deploy both services
    bash "${DCCD}" -d "${BASE_DIR}" -f -n

    # Verify both are running
    run docker ps -aq --filter "label=com.docker.compose.project=e2e-keep"
    assert_output  # non-empty
    run docker ps -aq --filter "label=com.docker.compose.project=e2e-orphan"
    assert_output  # non-empty

    # Simulate service removal (as if a git pull removed it)
    rm -rf "${BASE_DIR}/services/e2e-orphan"

    # Redeploy — orphan cleanup should detect and tear down e2e-orphan
    run bash "${DCCD}" -d "${BASE_DIR}" -f -n
    assert_success
    assert_output --partial "Detected removed service 'e2e-orphan'"

    # Verify orphan containers are gone
    run docker ps -aq --filter "label=com.docker.compose.project=e2e-orphan"
    assert_output ""

    # Verify kept service is still running
    run docker ps -aq --filter "label=com.docker.compose.project=e2e-keep"
    assert_output  # non-empty
}
