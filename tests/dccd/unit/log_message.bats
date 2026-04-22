#!/usr/bin/env bats
# Unit tests for log_message()

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
}

teardown() {
    common_teardown
}

@test "log_message: outputs formatted message to stdout" {
    run log_message "INFO:  Test message"
    assert_success
    assert_output --partial "Test message"
}

@test "log_message: includes timestamp from date mock" {
    run log_message "INFO:  Hello"
    assert_output --partial "2026-01-01 00:00:00"
}

@test "log_message: forwards message to syslog via logger" {
    run log_message "INFO:  Syslog test"
    assert_success
    assert_mock_called "logger"
}

@test "log_message: buffers output in quiet mode" {
    QUIET=1
    _QUIET_BUF="$(mktemp)"
    run log_message "INFO:  Buffered"
    assert_output ""
    run cat "${_QUIET_BUF}"
    assert_output --partial "Buffered"
    rm -f "${_QUIET_BUF}"
}

@test "log_message: prints directly when not in quiet mode" {
    QUIET=0
    run log_message "INFO:  Direct"
    assert_output --partial "Direct"
}

@test "log_message: handles ERROR prefix" {
    run log_message "ERROR: Something failed"
    assert_success
    assert_output --partial "ERROR: Something failed"
}

@test "log_message: handles WARNING prefix" {
    run log_message "WARNING: Careful"
    assert_success
    assert_output --partial "WARNING: Careful"
}

@test "log_message: handles STATE prefix" {
    run log_message "STATE: Deploying"
    assert_success
    assert_output --partial "STATE: Deploying"
}

@test "log_message: handles RESULT prefix" {
    run log_message "RESULT: All done"
    assert_success
    assert_output --partial "RESULT: All done"
}
