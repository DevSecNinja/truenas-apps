#!/usr/bin/env bats
# Integration tests: quiet mode

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
}

teardown() {
    common_teardown
}

@test "quiet mode: log_message buffers when QUIET=1" {
    QUIET=1
    _QUIET_BUF="$(mktemp)"
    log_message "INFO:  First message"
    log_message "INFO:  Second message"
    # stdout should be empty
    run cat "${_QUIET_BUF}"
    assert_output --partial "First message"
    assert_output --partial "Second message"
    rm -f "${_QUIET_BUF}"
}

@test "quiet mode: flush_output_buffer writes to stdout" {
    QUIET=1
    _QUIET_BUF="$(mktemp)"
    log_message "INFO:  Buffered content"
    run flush_output_buffer
    assert_output --partial "Buffered content"
    rm -f "${_QUIET_BUF}"
}

@test "quiet mode: normal mode writes directly to stdout" {
    QUIET=0
    run log_message "INFO:  Direct output"
    assert_output --partial "Direct output"
}

@test "quiet mode: flush does nothing when not in quiet mode" {
    QUIET=0
    run flush_output_buffer
    assert_success
    assert_output ""
}

@test "quiet mode: buffer is truncated after flush" {
    QUIET=1
    _QUIET_BUF="$(mktemp)"
    log_message "INFO:  Data"
    flush_output_buffer >/dev/null 2>&1
    run flush_output_buffer
    # Second flush should have nothing
    assert_output ""
    rm -f "${_QUIET_BUF}"
}
