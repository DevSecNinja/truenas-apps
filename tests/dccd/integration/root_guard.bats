#!/usr/bin/env bats
# Integration test for the root guard.

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() {
    common_setup
    unset DCCD_TESTING
}
teardown() { common_teardown; }

@test "root_guard: invoking dccd.sh as root prints guidance and exits" {
    # Skip when we cannot simulate being root (no sudo or already root).
    if [ "$(id -u)" -eq 0 ]; then
        # Running as root — script should exit on its own without simulation.
        run "${DCCD_SCRIPT}"
        assert_failure
        assert_output --partial "Do not run this script as root"
        return
    fi

    # Non-root: use a small wrapper that overrides `id` to report UID 0.
    # We simply stub `id` in the mock PATH and invoke the script under
    # `env PATH=<mock>:<orig> bash <script>`.
    create_mock_script id '
if [ "${1:-}" = "-u" ]; then echo 0; exit 0; fi
exec "'"$(PATH="${ORIG_PATH}" command -v id)"'" "$@"
'

    run env PATH="${MOCK_BIN}:${ORIG_PATH}" bash "${DCCD_SCRIPT}"
    assert_failure
    assert_output --partial "Do not run this script as root"
}

@test "root_guard: DCCD_TESTING=1 bypasses the root guard (sourcing works)" {
    # Source in a subshell and confirm it returns 0 regardless of uid.
    run bash -c "DCCD_TESTING=1 source '${DCCD_SCRIPT}' && declare -F log_message >/dev/null && echo OK"
    assert_success
    assert_output --partial "OK"
}
