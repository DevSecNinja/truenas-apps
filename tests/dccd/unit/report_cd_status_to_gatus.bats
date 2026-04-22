#!/usr/bin/env bats
# Unit tests for report_cd_status_to_gatus.

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }

@test "report_cd_status_to_gatus: no-op when GATUS_URL is empty" {
    create_mock curl 0 ""
    GATUS_URL=""
    GATUS_CD_TOKEN="tok"

    run report_cd_status_to_gatus "true"
    assert_success
    [ "$(mock_call_count curl)" = "0" ]
}

@test "report_cd_status_to_gatus: no-op when GATUS_CD_TOKEN is empty" {
    create_mock curl 0 ""
    GATUS_URL="https://status.example.com"
    GATUS_CD_TOKEN=""

    run report_cd_status_to_gatus "true"
    assert_success
    [ "$(mock_call_count curl)" = "0" ]
}

@test "report_cd_status_to_gatus: calls curl with success query on happy path" {
    create_mock curl 0 ""
    GATUS_URL="https://status.example.com"
    GATUS_CD_TOKEN="tok"

    run report_cd_status_to_gatus "true"
    assert_success
    assert_output --partial "CD status (success=true) reported to Gatus"

    run mock_last_call curl
    assert_output --partial "success=true"
    assert_output --partial "Authorization: Bearer tok"
}

@test "report_cd_status_to_gatus: encodes error message into query" {
    create_mock curl 0 ""
    GATUS_URL="https://status.example.com"
    GATUS_CD_TOKEN="tok"

    report_cd_status_to_gatus "false" "boom happened"

    run mock_last_call curl
    assert_output --partial "error=boom+happened"
    assert_output --partial "success=false"
}

@test "report_cd_status_to_gatus: passes duration when supplied" {
    create_mock curl 0 ""
    GATUS_URL="https://status.example.com"
    GATUS_CD_TOKEN="tok"

    report_cd_status_to_gatus "true" "" "42"

    run mock_last_call curl
    assert_output --partial "duration=42"
}

@test "report_cd_status_to_gatus: logs warning when curl fails" {
    create_mock curl 22 "curl error"
    GATUS_URL="https://status.example.com"
    GATUS_CD_TOKEN="tok"

    run report_cd_status_to_gatus "false"
    assert_success
    assert_output --partial "WARNING: Failed to report CD status"
}

@test "report_cd_status_to_gatus: uses dig + --resolve when GATUS_DNS_SERVER is set" {
    create_mock curl 0 ""
    create_mock dig 0 "1.2.3.4"
    GATUS_URL="https://status.example.com"
    GATUS_CD_TOKEN="tok"
    GATUS_DNS_SERVER="192.168.1.1"

    report_cd_status_to_gatus "true"

    run mock_last_call curl
    assert_output --partial "--resolve status.example.com:443:1.2.3.4"
    run mock_last_call dig
    assert_output --partial "status.example.com"
    assert_output --partial "@192.168.1.1"
}
