#!/usr/bin/env bats
# Integration tests: root guard

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
}

teardown() {
    common_teardown
}

@test "root guard: script exits when id returns 0" {
    # Override id mock to return root
    cat >"${MOCK_BIN}/id" <<'MOCK'
#!/bin/bash
echo 0
MOCK
    chmod +x "${MOCK_BIN}/id"

    # Run dccd.sh WITHOUT DCCD_TESTING — it should hit root guard and exit
    run bash -c "export PATH='${MOCK_BIN}:${PATH}'; bash '${REPO_ROOT}/scripts/dccd.sh'"
    assert_failure
    assert_output --partial "Do not run this script as root"
}

@test "root guard: script proceeds when id returns non-zero" {
    # Override id mock to return non-root
    cat >"${MOCK_BIN}/id" <<'MOCK'
#!/bin/bash
echo 1000
MOCK
    chmod +x "${MOCK_BIN}/id"

    # Run dccd.sh WITHOUT DCCD_TESTING — it should pass root guard but fail on -d
    run bash -c "export PATH='${MOCK_BIN}:${PATH}'; bash '${REPO_ROOT}/scripts/dccd.sh' -h 2>&1 || true"
    refute_output --partial "Do not run this script as root"
}
