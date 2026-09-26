#!/usr/bin/env bats

load '../helpers/diagnostics'

setup_file() {
    diagnostics_require_helpers
}

setup() {
    diagnostics_setup
}

teardown() {
    common_teardown
}

@test "compose_up_wait_tolerant: failure preserves classifier stdout and logs actual error on stderr" {
    local message='network browser declared as external, but could not be found'
    create_mock docker 17 "${message}"
    run --separate-stderr compose_up_wait_tolerant karakeep -f "${BASE_DIR}/compose.yaml"
    assert_failure 1
    assert_output "${message}"
    assert_stderr --partial 'ERROR'
    assert_stderr --partial 'Docker Compose failed (exit 17)'
    assert_stderr --partial "${message}"
}

@test "compose_up_wait_tolerant: cron hiding stdout still sees actual failure under strict mode" {
    create_mock docker 17 'invalid mount config: bind source path does not exist'
    hide_stdout() {
        set -euo pipefail
        if compose_up_wait_tolerant karakeep -f "${BASE_DIR}/compose.yaml" >/dev/null; then
            return 0
        else
            return "$?"
        fi
    }
    run --separate-stderr hide_stdout
    assert_failure 1
    assert_output ''
    assert_stderr --partial 'Docker Compose failed (exit 17)'
    assert_stderr --partial 'invalid mount config: bind source path does not exist'
}

@test "compose_up_wait_tolerant: successful deployment still reports recreated containers without errors" {
    create_mock docker 0 'Container chrome Recreated'
    run --separate-stderr compose_up_wait_tolerant karakeep -f "${BASE_DIR}/compose.yaml"
    assert_success
    assert_output --partial '1 container(s) restarted:'
    assert_output --partial 'chrome'
    assert_stderr ''
}

@test "compose_up_wait_tolerant: existing no-healthcheck fallback succeeds when a container is running" {
    create_sequential_mock docker '1:container chrome has no healthcheck configured' '0:chrome'
    run --separate-stderr compose_up_wait_tolerant karakeep -f "${BASE_DIR}/compose.yaml"
    assert_success
    assert_output --partial 'using "running" state as readiness'
    assert_stderr ''
    assert_mock_called_with docker 'ps --status=running --quiet'
}
