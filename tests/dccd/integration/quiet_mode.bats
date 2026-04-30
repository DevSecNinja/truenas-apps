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

@test "quiet mode: log helpers buffer when enable_quiet_mode is active" {
    QUIET=1
    _QUIET_BUF="$(mktemp)"
    enable_quiet_mode
    log_info "First message"
    log_info "Second message"
    # stdout should be empty
    run cat "${_QUIET_BUF}"
    assert_output --partial "First message"
    assert_output --partial "Second message"
    flush_output_buffer >/dev/null 2>&1
    rm -f "${_QUIET_BUF}"
}

@test "quiet mode: flush_output_buffer writes to stdout" {
    QUIET=1
    _QUIET_BUF="$(mktemp)"
    enable_quiet_mode
    log_info "Buffered content"
    run flush_output_buffer
    assert_output --partial "Buffered content"
    rm -f "${_QUIET_BUF}"
}

@test "quiet mode: normal mode writes directly to stdout" {
    QUIET=0
    run log_info "Direct output"
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
    enable_quiet_mode
    log_info "Data"
    flush_output_buffer >/dev/null 2>&1
    run flush_output_buffer
    # Second flush should have nothing
    assert_output ""
    rm -f "${_QUIET_BUF}"
}
