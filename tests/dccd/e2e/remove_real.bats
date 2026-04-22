#!/usr/bin/env bats
# E2E tests: real -R teardown against running containers
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

    mkdir -p "${BASE_DIR}/services/e2e-remove"
    cat >"${BASE_DIR}/services/e2e-remove/compose.yaml" <<'EOF'
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

    cd "${BASE_DIR}"
    git init --quiet
    git config user.email "test@test.local"
    git config user.name "Test"
    git add -A
    git commit --quiet -m "init"

    DCCD="${REPO_ROOT}/scripts/dccd.sh"
}

teardown() {
    docker compose -f "${BASE_DIR}/services/e2e-remove/compose.yaml" \
        --project-name "e2e-remove" down --remove-orphans 2>/dev/null || true
    common_teardown
}

@test "e2e_remove: -R tears down running containers" {
    if [ "${GITHUB_ACTIONS:-}" != "true" ] && [ "${DCCD_E2E:-}" != "1" ]; then
        skip "E2E tests are skipped locally — set DCCD_E2E=1 to run"
    fi

    docker pull docker.io/library/busybox:stable

    # Deploy first
    bash "${DCCD}" -d "${BASE_DIR}" -f -n

    # Verify running
    run docker compose -f "${BASE_DIR}/services/e2e-remove/compose.yaml" \
        --project-name "e2e-remove" ps --quiet
    assert_output  # non-empty

    # Remove
    run bash "${DCCD}" -d "${BASE_DIR}" -R e2e-remove
    assert_success

    # Verify no containers
    run docker ps -aq --filter "label=com.docker.compose.project=e2e-remove"
    assert_output ""
}
