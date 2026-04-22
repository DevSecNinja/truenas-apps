#!/usr/bin/env bats
# Unit tests for flush_output_buffer()

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
}

teardown() {
    common_teardown
}

@test "flush_output_buffer: outputs buffered content when QUIET=1" {
    QUIET=1
    _QUIET_BUF="$(mktemp)"
    echo "line 1" >>"${_QUIET_BUF}"
    echo "line 2" >>"${_QUIET_BUF}"
    run flush_output_buffer
    assert_output --partial "line 1"
    assert_output --partial "line 2"
    rm -f "${_QUIET_BUF}"
}

@test "flush_output_buffer: does nothing when QUIET=0" {
    QUIET=0
    run flush_output_buffer
    assert_success
    assert_output ""
}

@test "flush_output_buffer: handles empty buffer" {
    QUIET=1
    _QUIET_BUF="$(mktemp)"
    run flush_output_buffer
    assert_success
    rm -f "${_QUIET_BUF}"
}

@test "flush_output_buffer: clears buffer after flushing" {
    QUIET=1
    _QUIET_BUF="$(mktemp)"
    echo "data" >>"${_QUIET_BUF}"
    flush_output_buffer >/dev/null 2>&1
    # Buffer file should be truncated
    run cat "${_QUIET_BUF}"
    assert_output ""
    rm -f "${_QUIET_BUF}"
}

@test "flush_output_buffer: handles missing buffer file" {
    QUIET=1
    _QUIET_BUF="/tmp/nonexistent-buf-$$"
    run flush_output_buffer
    assert_success
}

@test "flush_output_buffer: preserves multi-line content" {
    QUIET=1
    _QUIET_BUF="$(mktemp)"
    printf "alpha\nbeta\ngamma\n" >>"${_QUIET_BUF}"
    run flush_output_buffer
    assert_line --index 0 "alpha"
    assert_line --index 1 "beta"
    assert_line --index 2 "gamma"
    rm -f "${_QUIET_BUF}"
}
