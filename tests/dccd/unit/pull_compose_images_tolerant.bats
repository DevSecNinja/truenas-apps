#!/usr/bin/env bats
# Unit tests for pull_compose_images_tolerant()

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
}

teardown() {
    common_teardown
}

@test "pull_compose_images_tolerant: returns success when pull fails under pipefail" {
    set -o pipefail
    create_mock "docker" 1 "pull access denied for ghcr.io/example/private:latest"

    run pull_compose_images_tolerant "testapp" -f "${BASE_DIR}/services/testapp/compose.yaml"
    assert_success
    assert_output --partial "pull access denied"
    assert_output --partial "testapp: Image pull failed; continuing deployment with locally available images"
}
