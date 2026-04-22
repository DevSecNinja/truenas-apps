#!/usr/bin/env bats
# Unit tests for log_message.

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }

@test "log_message: prints timestamped message to stdout by default" {
    run log_message "hello"
    assert_success
    assert_output --partial "hello"
    assert_output --partial "2024-01-01 00:00:00"
}

@test "log_message: forwards to logger with dccd tag" {
    log_message "syslog me"
    run mock_last_call logger
    assert_success
    assert_output --partial "-t dccd syslog me"
}

@test "log_message: buffers output in quiet mode instead of printing" {
    QUIET=1
    _QUIET_BUF="${TEST_TMPDIR}/qbuf"
    : >"${_QUIET_BUF}"

    run log_message "buffered"
    assert_success
    refute_output --partial "buffered"

    run cat "${_QUIET_BUF}"
    assert_success
    assert_output --partial "buffered"
}

@test "log_message: prints immediately when QUIET=1 but buffer path is empty" {
    QUIET=1
    _QUIET_BUF=""

    run log_message "no-buffer"
    assert_success
    assert_output --partial "no-buffer"
}

@test "log_message: ERROR prefix triggers no crash under non-tty" {
    # stdout is not a TTY in the test runner, so colorisation path is skipped.
    run log_message "ERROR: boom"
    assert_success
    assert_output --partial "ERROR: boom"
}
