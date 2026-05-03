#!/usr/bin/env bats
# Unit tests for container restart logging helpers.

setup() {
    load '../helpers/common'
    common_setup
}

teardown() {
    common_teardown
}

@test "extract_restarted_containers: returns unique recreated and restarted containers" {
    local compose_output=$'Container testapp-web-1 Recreate\nContainer testapp-web-1 Recreated\nContainer testapp-worker-1 Restarting\nContainer testapp-worker-1 Restarted\nContainer testapp-db-1 Started'

    run extract_restarted_containers "${compose_output}"
    assert_success
    assert_line "testapp-web-1"
    assert_line "testapp-worker-1"
    refute_output --partial "testapp-db-1"
}

@test "record_container_restarts: logs restarted containers and increments counter" {
    local compose_output=$'Container testapp-web-1 Recreated\nContainer testapp-worker-1 Restarted'
    local output_file="${BATS_TMPDIR}/container-restarts.log"

    record_container_restarts "testapp" "${compose_output}" >"${output_file}"

    run cat "${output_file}"
    assert_success
    assert_output --partial "2 container(s) restarted:"
    assert_output --partial "testapp-web-1"
    assert_output --partial "testapp-worker-1"

    run test "${_DEPLOY_RESTARTED}" -eq 2
    assert_success
}

@test "record_container_restarts: ignores compose output without restarts" {
    local output_file="${BATS_TMPDIR}/container-restarts-empty.log"

    record_container_restarts "testapp" "Container testapp-web-1 Started" >"${output_file}"

    run cat "${output_file}"
    assert_success
    assert_output ""

    run test "${_DEPLOY_RESTARTED}" -eq 0
    assert_success
}
