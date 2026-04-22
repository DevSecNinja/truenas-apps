#!/usr/bin/env bats
# Unit tests for flush_output_buffer.

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }

@test "flush_output_buffer: flushes buffered content to stdout" {
    QUIET=1
    _QUIET_BUF="${TEST_TMPDIR}/qbuf"
    printf 'line1\nline2\n' >"${_QUIET_BUF}"

    run flush_output_buffer
    assert_success
    assert_output --partial "line1"
    assert_output --partial "line2"
}

@test "flush_output_buffer: sets QUIET=0 after flushing" {
    QUIET=1
    _QUIET_BUF="${TEST_TMPDIR}/qbuf"
    : >"${_QUIET_BUF}"

    flush_output_buffer
    [ "${QUIET}" -eq 0 ]
}

@test "flush_output_buffer: truncates buffer file after flushing" {
    QUIET=1
    _QUIET_BUF="${TEST_TMPDIR}/qbuf"
    printf 'content\n' >"${_QUIET_BUF}"

    flush_output_buffer

    # Buffer file still exists but is empty.
    assert_file_exists "${_QUIET_BUF}"
    [ ! -s "${_QUIET_BUF}" ]
}

@test "flush_output_buffer: no-op when buffer path is missing" {
    QUIET=1
    _QUIET_BUF=""

    run flush_output_buffer
    assert_success
    assert_output ""
    [ "${QUIET}" -eq 0 ]
}

@test "flush_output_buffer: no-op when buffer file does not exist" {
    QUIET=1
    _QUIET_BUF="${TEST_TMPDIR}/does-not-exist"

    run flush_output_buffer
    assert_success
    assert_output ""
    [ "${QUIET}" -eq 0 ]
}

@test "flush_output_buffer: no-op when QUIET=0" {
    QUIET=0
    _QUIET_BUF="${TEST_TMPDIR}/qbuf"
    printf 'should-not-appear\n' >"${_QUIET_BUF}"

    run flush_output_buffer
    assert_success
    refute_output --partial "should-not-appear"
}
