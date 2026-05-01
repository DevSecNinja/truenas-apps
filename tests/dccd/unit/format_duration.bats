#!/usr/bin/env bats
# Unit tests for format_duration()

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    create_default_mocks
}

teardown() {
    common_teardown
}

@test "format_duration: zero seconds" {
    run format_duration 0
    assert_output "0s"
}

@test "format_duration: sub-minute" {
    run format_duration 45
    assert_output "45s"
}

@test "format_duration: exactly one minute" {
    run format_duration 60
    assert_output "1m 0s"
}

@test "format_duration: minutes and seconds" {
    run format_duration 93
    assert_output "1m 33s"
}

@test "format_duration: exactly one hour" {
    run format_duration 3600
    assert_output "1h 0m 0s"
}

@test "format_duration: hours, minutes, seconds" {
    run format_duration 7510
    assert_output "2h 5m 10s"
}

@test "format_duration: exactly one day" {
    run format_duration 86400
    assert_output "1d 0h 0m 0s"
}

@test "format_duration: days, hours, minutes, seconds" {
    run format_duration 93784
    assert_output "1d 2h 3m 4s"
}

@test "format_duration: skips zero hours when minutes present" {
    run format_duration 120
    assert_output "2m 0s"
}

@test "format_duration: defaults to 0 when arg missing" {
    run format_duration
    assert_output "0s"
}
