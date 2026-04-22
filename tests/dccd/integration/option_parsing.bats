#!/usr/bin/env bats
# Integration tests for option parsing (getopts, defaults, mutual exclusivity).
# These invoke dccd.sh as a subprocess rather than sourcing it because they
# need to exercise the main execution path (option loop).

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() {
    common_setup
    # These tests invoke dccd.sh as a subprocess; unset DCCD_TESTING so the
    # main flow runs but arrange for early-exits (e.g. missing -d).
    unset DCCD_TESTING
}
teardown() { common_teardown; }

@test "option_parsing: exits when -d is not provided" {
    run "${DCCD_SCRIPT}"
    assert_failure
    assert_output --partial "ERROR: The base directory (-d) is required"
}

@test "option_parsing: -h prints usage and exits" {
    run "${DCCD_SCRIPT}" -h
    assert_failure
    assert_output --partial "Usage:"
}

@test "option_parsing: unknown option exits with error" {
    run "${DCCD_SCRIPT}" -Z
    assert_failure
    assert_output --partial "Invalid option"
}

@test "option_parsing: option missing required argument exits with error" {
    run "${DCCD_SCRIPT}" -d
    assert_failure
    assert_output --partial "requires an argument"
}

@test "option_parsing: -R (remove mode) without -d still errors on missing base dir" {
    run "${DCCD_SCRIPT}" -R plex
    assert_failure
    assert_output --partial "base directory (-d) is required"
}
