#!/usr/bin/env bats
# Unit tests for log_image_changes()

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
}

teardown() {
    common_teardown
}

@test "log_image_changes: returns silently when both snapshots empty" {
    run log_image_changes "testapp" "" ""
    assert_success
    assert_output ""
}

@test "log_image_changes: reports initial deployment when before empty" {
    run log_image_changes "testapp" "" "web=nginx:latest"
    assert_success
    assert_output --partial "Initial deployment"
    assert_output --partial "web: nginx:latest"
}

@test "log_image_changes: reports no updates when snapshots match" {
    local snapshot="web=nginx:1.0"
    run log_image_changes "testapp" "${snapshot}" "${snapshot}"
    assert_success
    assert_output --partial "No updates"
}

@test "log_image_changes: reports UPDATED when images differ" {
    run log_image_changes "testapp" "web=nginx:1.0" "web=nginx:2.0"
    assert_success
    assert_output --partial "UPDATED"
    assert_output --partial "from: nginx:1.0"
    assert_output --partial "to:   nginx:2.0"
}

@test "log_image_changes: reports new service" {
    run log_image_changes "testapp" "web=nginx:1.0" $'web=nginx:1.0\nworker=redis:7'
    assert_success
    assert_output --partial "worker: new -> redis:7"
}

@test "log_image_changes: reports unchanged services alongside changes" {
    local before=$'db=postgres:15\nweb=nginx:1.0'
    local after=$'db=postgres:15\nweb=nginx:2.0'
    run log_image_changes "testapp" "${before}" "${after}"
    assert_success
    assert_output --partial "db: unchanged"
    assert_output --partial "web: UPDATED"
}
