#!/usr/bin/env bats

load '../helpers/diagnostics'

setup_file() {
    diagnostics_require_helpers
}

setup() {
    diagnostics_setup
    export DIAG_CONTAINERS=chrome DIAG_LIST_RC=0 DIAG_INSPECT_RC=0 DIAG_LOGS_RC=0
    export DIAG_STATE=$'status=running exit_code=0 oom_killed=false health=unhealthy failing_streak=5\nprobe 2026-09-19T08:00:00Z: exit_code=1\nconnect: Connection refused'
    export DIAG_LOGS='socat: E fork: Resource temporarily unavailable'
    # Fixed, state-only Go-template contract: checks the failed-probe predicate,
    # absent-Health branch and exclusion of Env, not just mocked output. This
    # does not claim to execute a Go template engine.
    export DIAG_FORMAT='status={{.State.Status}} exit_code={{.State.ExitCode}} oom_killed={{.State.OOMKilled}}{{if .State.Error}} error={{.State.Error}}{{end}}{{if .State.Health}} health={{.State.Health.Status}} failing_streak={{.State.Health.FailingStreak}}{{range .State.Health.Log}}{{if ne .ExitCode 0}}{{printf "\nprobe %s: exit_code=%d\n%s" .End .ExitCode .Output}}{{end}}{{end}}{{else}} health=not-configured{{end}}'
    printf '%s\n' \
        '#!/bin/bash' \
        'printf "%s\n" "$*" >>"${MOCK_LOG}/docker.calls"' \
        'case "$1" in' \
        'ps) printf "%s\n" "${DIAG_CONTAINERS}"; exit "${DIAG_LIST_RC}" ;;' \
        'inspect)' \
        '  if [[ $# != 4 || "$2" != --format || "$3" != "${DIAG_FORMAT}" ]]; then' \
        '    echo "unexpected inspect template/argv" >&2; exit 98' \
        '  fi' \
        '  printf "%s\n" "${DIAG_STATE}"; exit "${DIAG_INSPECT_RC}" ;;' \
        'logs) printf "%s\n" "${DIAG_LOGS}"; exit "${DIAG_LOGS_RC}" ;;' \
        '*) echo "unexpected docker command" >&2; exit 99 ;;' \
        'esac' >"${MOCK_BIN}/docker"
    chmod +x "${MOCK_BIN}/docker"
}

teardown() {
    common_teardown
}

@test "dump_project_logs_tail: state failed probes and requested log tail go only to stderr" {
    run --separate-stderr dump_project_logs_tail ix-karakeep 7
    assert_success
    assert_output ''
    assert_stderr --partial 'health=unhealthy failing_streak=5'
    assert_stderr --partial 'probe 2026-09-19T08:00:00Z: exit_code=1'
    assert_stderr --partial 'connect: Connection refused'
    assert_stderr --partial "${DIAG_LOGS}"
    assert_mock_called_with docker 'ps -a --filter label=com.docker.compose.project=ix-karakeep'
    assert_mock_called_with docker "inspect --format ${DIAG_FORMAT} chrome"
    assert_mock_called_with docker 'logs --tail 7 chrome'
}

@test "dump_project_logs_tail: recovered healthy container retains failed probe history" {
    DIAG_STATE=$'status=running exit_code=0 oom_killed=false health=healthy failing_streak=0\nprobe 2026-09-19T07:59:00Z: exit_code=7\nprevious failed probe'
    run --separate-stderr dump_project_logs_tail ix-karakeep
    assert_success
    assert_output ''
    assert_stderr --partial 'health=healthy failing_streak=0'
    assert_stderr --partial 'exit_code=7'
    assert_stderr --partial 'previous failed probe'
}

@test "dump_project_logs_tail: successful exited init without Health and empty logs are supported" {
    DIAG_CONTAINERS=karakeep-init
    DIAG_STATE='status=exited exit_code=0 oom_killed=false health=not-configured'
    DIAG_LOGS=''
    run --separate-stderr dump_project_logs_tail ix-karakeep
    assert_success
    assert_output ''
    assert_stderr --partial "${DIAG_STATE}"
    assert_stderr --partial '(no log output)'
    refute_stderr --partial 'unable to inspect'
}

@test "dump_project_logs_tail: inspect failure is explicit and log collection continues" {
    DIAG_INSPECT_RC=43
    DIAG_STATE='inspect: permission denied'
    run --separate-stderr dump_project_logs_tail ix-karakeep
    assert_success
    assert_output ''
    assert_stderr --partial 'unable to inspect container state'
    assert_stderr --partial "${DIAG_STATE}"
    assert_stderr --partial "${DIAG_LOGS}"
    assert_mock_called_with docker 'logs --tail 10 chrome'
}

@test "dump_project_logs_tail: log failure is explicit without losing state" {
    DIAG_LOGS_RC=44
    DIAG_LOGS='logs: logging driver does not support reading'
    run --separate-stderr dump_project_logs_tail ix-karakeep
    assert_success
    assert_output ''
    assert_stderr --partial 'health=unhealthy'
    assert_stderr --partial 'unable to read container logs'
    assert_stderr --partial "${DIAG_LOGS}"
}

@test "dump_project_logs_tail: discovery error is reported and never inspected as a container name" {
    DIAG_LIST_RC=45
    DIAG_CONTAINERS='ps: daemon unavailable'
    run --separate-stderr dump_project_logs_tail ix-karakeep
    assert_success
    assert_output ''
    assert_stderr --partial 'unable to list containers for diagnostics'
    assert_stderr --partial "${DIAG_CONTAINERS}"
    run get_mock_call_count docker
    assert_success
    assert_output 1
}
