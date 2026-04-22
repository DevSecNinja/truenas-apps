#!/usr/bin/env bats
# Unit tests for report_cd_status_to_gatus() and url_encode_simple()

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    create_default_mocks
}

teardown() {
    common_teardown
}

# --- url_encode_simple tests ---

@test "url_encode_simple: encodes spaces as %20" {
    run url_encode_simple "hello world"
    assert_output "hello%20world"
}

@test "url_encode_simple: encodes ampersand" {
    run url_encode_simple "a&b"
    assert_output "a%26b"
}

@test "url_encode_simple: encodes equals" {
    run url_encode_simple "key=val"
    assert_output "key%3Dval"
}

@test "url_encode_simple: encodes hash" {
    run url_encode_simple "test#anchor"
    assert_output "test%23anchor"
}

@test "url_encode_simple: encodes forward slash" {
    run url_encode_simple "path/to/file"
    assert_output "path%2Fto%2Ffile"
}

@test "url_encode_simple: passes through plain text" {
    run url_encode_simple "simple"
    assert_output "simple"
}

@test "url_encode_simple: encodes multiple special chars" {
    run url_encode_simple "a & b = c"
    assert_output "a%20%26%20b%20%3D%20c"
}

# --- report_cd_status_to_gatus tests ---

@test "report_cd_status_to_gatus: returns silently when GATUS_URL empty" {
    GATUS_URL=""
    run report_cd_status_to_gatus "true" "" "10s"
    assert_success
    assert_output ""
}

@test "report_cd_status_to_gatus: returns silently when GATUS_CD_TOKEN empty" {
    GATUS_URL="https://gatus.example.com"
    unset GATUS_CD_TOKEN
    run report_cd_status_to_gatus "true" "" "10s"
    assert_success
    assert_output ""
}

@test "report_cd_status_to_gatus: calls curl with correct URL" {
    GATUS_URL="https://gatus.example.com"
    export GATUS_CD_TOKEN="test-token"
    create_mock "curl" 0 ""
    run report_cd_status_to_gatus "true" "" "10s"
    assert_success
    assert_output --partial "CD status"
    assert_mock_called_with "curl" "Webhooks_docker-compose-cd"
}

@test "report_cd_status_to_gatus: includes error message when provided" {
    GATUS_URL="https://gatus.example.com"
    export GATUS_CD_TOKEN="test-token"
    create_mock "curl" 0 ""
    run report_cd_status_to_gatus "false" "deploy failed" "5s"
    assert_success
    assert_mock_called_with "curl" "error="
}

@test "report_cd_status_to_gatus: warns on curl failure" {
    GATUS_URL="https://gatus.example.com"
    export GATUS_CD_TOKEN="test-token"
    create_mock "curl" 1 "connection refused"
    run report_cd_status_to_gatus "false" "" "5s"
    assert_success
    assert_output --partial "WARNING: Failed to report"
}

@test "report_cd_status_to_gatus: uses dig for DNS resolution" {
    GATUS_URL="https://gatus.example.com"
    export GATUS_CD_TOKEN="test-token"
    GATUS_DNS_SERVER="1.1.1.1"
    create_mock "dig" 0 "10.0.0.1"
    create_mock "curl" 0 ""
    run report_cd_status_to_gatus "true" "" "10s"
    assert_success
    assert_mock_called "dig"
}
