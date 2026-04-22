#!/usr/bin/env bats
# Unit tests for log_image_changes.

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }

@test "log_image_changes: no-op when both snapshots are empty" {
    run log_image_changes "plex" "" ""
    assert_success
    assert_output ""
}

@test "log_image_changes: reports initial deployment when before is empty" {
    local after='plex=docker.io/library/plex:1.0'
    run log_image_changes "plex" "" "${after}"
    assert_success
    assert_output --partial "Initial deployment"
    assert_output --partial "plex: docker.io/library/plex:1.0"
}

@test "log_image_changes: reports no updates when snapshots are identical" {
    local snap='web=app:1.0'
    run log_image_changes "myapp" "${snap}" "${snap}"
    assert_success
    assert_output --partial "No updates (images unchanged)"
}

@test "log_image_changes: reports UPDATED for changed images" {
    local before='web=app:1.0'
    local after='web=app:2.0'
    run log_image_changes "myapp" "${before}" "${after}"
    assert_success
    assert_output --partial "Image changes detected"
    assert_output --partial "UPDATED"
    assert_output --partial "from: app:1.0"
    assert_output --partial "to:   app:2.0"
}

@test "log_image_changes: reports 'new ->' for services without a prior entry" {
    local before='web=app:1.0'
    local after=$'web=app:1.0\nworker=wrk:1.0'
    run log_image_changes "myapp" "${before}" "${after}"
    assert_success
    assert_output --partial "worker: new -> wrk:1.0"
}

@test "log_image_changes: reports unchanged services alongside updates" {
    local before=$'a=aaa:1\nb=bbb:1'
    local after=$'a=aaa:1\nb=bbb:2'
    run log_image_changes "app" "${before}" "${after}"
    assert_success
    assert_output --partial "a: unchanged"
    assert_output --partial "b: UPDATED"
}
