#!/usr/bin/env bats
# Integration tests for quiet-mode buffering and flush.

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }

@test "quiet_mode: messages logged while QUIET=1 are buffered, flush restores them" {
    QUIET=1
    _QUIET_BUF="${TEST_TMPDIR}/qbuf"
    : >"${_QUIET_BUF}"

    # Nothing reaches stdout while quiet.
    run log_message "msg-one"
    assert_success
    refute_output --partial "msg-one"

    run log_message "msg-two"
    assert_success

    # QUIET=1 is still set in the subshells above but the real variable in the
    # test shell is also 1 because we set it. Now flush and log a third msg.
    QUIET=1
    _QUIET_BUF="${TEST_TMPDIR}/qbuf"
    # Flush → stdout should include the previously-buffered lines, then
    # subsequent log_message calls go straight to stdout.
    run bash -c '
        set +euo pipefail
        export DCCD_TESTING=1
        source "'"${DCCD_SCRIPT}"'"
        QUIET=1
        _QUIET_BUF="'"${TEST_TMPDIR}"'/qbuf2"
        : >"$_QUIET_BUF"
        # Redirect logger and date via PATH.
        export PATH="'"${MOCK_BIN}"'":"$PATH"
        log_message "buffered-a"
        log_message "buffered-b"
        flush_output_buffer
        log_message "after-flush"
    '
    assert_success
    assert_output --partial "buffered-a"
    assert_output --partial "buffered-b"
    assert_output --partial "after-flush"
}
