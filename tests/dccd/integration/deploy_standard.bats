#!/usr/bin/env bats
# Integration tests: deploy standard (non-TrueNAS) mode

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    create_default_mocks
}

teardown() {
    common_teardown
}

@test "deploy standard: redeploy_compose_file calls docker compose" {
    mkdir -p "${BASE_DIR}/services/testapp"
    cat >"${BASE_DIR}/services/testapp/compose.yaml" <<'YAML'
services:
  web:
    image: nginx
YAML

    # docker compose config --quiet succeeds, config --services returns services, pull succeeds, up succeeds
    create_sequential_mock "docker" "0:" "0:web" "0:" "0:"
    TMPRESTART="$(mktemp)"

    run redeploy_compose_file "${BASE_DIR}/services/testapp/compose.yaml"
    assert_success
    assert_mock_called "docker"
    rm -f "${TMPRESTART}"
}

@test "deploy standard: skips invalid compose file" {
    mkdir -p "${BASE_DIR}/services/badapp"
    touch "${BASE_DIR}/services/badapp/compose.yaml"

    # config --quiet fails
    create_mock "docker" 1 ""
    run redeploy_compose_file "${BASE_DIR}/services/badapp/compose.yaml"
    assert_success
    assert_output --partial "compose config validation failed"
}

@test "deploy standard: graceful mode skips unchanged" {
    mkdir -p "${BASE_DIR}/services/testapp"
    touch "${BASE_DIR}/services/testapp/compose.yaml"
    GRACEFUL=1
    TMPRESTART="$(mktemp)"
    echo "No changes" >"${TMPRESTART}"

    # config --quiet ok, config --services returns service, dry-run returns no Recreate
    create_sequential_mock "docker" "0:" "0:web" "0:No changes"
    run redeploy_compose_file "${BASE_DIR}/services/testapp/compose.yaml"
    assert_success
    assert_output --partial "no change"
    rm -f "${TMPRESTART}"
}

@test "deploy standard: graceful mode redeploys changed" {
    mkdir -p "${BASE_DIR}/services/testapp"
    touch "${BASE_DIR}/services/testapp/compose.yaml"
    GRACEFUL=1
    TMPRESTART="$(mktemp)"

    # config ok, services return, dry-run has "Recreate", up succeeds
    create_sequential_mock "docker" "0:" "0:web" "0:Container testapp-web-1 Recreate" "0:"
    run redeploy_compose_file "${BASE_DIR}/services/testapp/compose.yaml"
    assert_success
    assert_output --partial "Redeploying"
    rm -f "${TMPRESTART}"
}

@test "deploy standard: logs containers recreated by compose up" {
    mkdir -p "${BASE_DIR}/services/testapp"
    touch "${BASE_DIR}/services/testapp/compose.yaml"

    # config ok, services return, pull succeeds, up reports a recreated container
    create_sequential_mock "docker" "0:" "0:web" "0:" "0:Container testapp-web-1 Recreated"
    run redeploy_compose_file "${BASE_DIR}/services/testapp/compose.yaml"
    assert_success
    assert_output --partial "1 container(s) restarted:"
    assert_output --partial "testapp-web-1"
}

@test "deploy standard: no-pull mode skips image pull" {
    mkdir -p "${BASE_DIR}/services/testapp"
    touch "${BASE_DIR}/services/testapp/compose.yaml"
    NO_PULL=1

    # config ok, services return, up succeeds (no pull call)
    create_sequential_mock "docker" "0:" "0:web" "0:"
    TMPRESTART="$(mktemp)"
    run redeploy_compose_file "${BASE_DIR}/services/testapp/compose.yaml"
    assert_success
    assert_output --partial "Skipping image pull"
    rm -f "${TMPRESTART}"
}

@test "deploy standard: handles compose override files" {
    mkdir -p "${BASE_DIR}/services/testapp"
    touch "${BASE_DIR}/services/testapp/compose.yaml"
    touch "${BASE_DIR}/services/testapp/compose.svlazext.yaml"

    create_sequential_mock "docker" "0:" "0:web" "0:" "0:"
    TMPRESTART="$(mktemp)"
    run redeploy_compose_file "${BASE_DIR}/services/testapp/compose.yaml" "${BASE_DIR}/services/testapp/compose.svlazext.yaml"
    assert_success
    assert_mock_called_with "docker" "compose.svlazext.yaml"
    rm -f "${TMPRESTART}"
}

@test "deploy standard: increments error counter on failure" {
    mkdir -p "${BASE_DIR}/services/testapp"
    touch "${BASE_DIR}/services/testapp/compose.yaml"
    _DEPLOY_ERRORS=0

    # config ok, services ok, pull ok, up -d fails
    create_sequential_mock "docker" "0:" "0:web" "0:" "1:deploy failed"
    TMPRESTART="$(mktemp)"
    redeploy_compose_file "${BASE_DIR}/services/testapp/compose.yaml"
    [[ "${_DEPLOY_ERRORS}" -eq 1 ]]
    rm -f "${TMPRESTART}"
}
