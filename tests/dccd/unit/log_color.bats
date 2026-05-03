#!/usr/bin/env bats
# Unit tests for log color handling.

setup() {
    load '../helpers/common'
    common_setup
}

teardown() {
    common_teardown
}

@test "log_warn: colorizes stderr when stdout is captured" {
    command -v script >/dev/null 2>&1 || skip "script(1) is required for pty color test"
    script -q -e -c true /dev/null >/dev/null 2>&1 || skip "script(1) does not support required flags"

    local helper transcript cmd
    helper="${BATS_TMPDIR}/log-color-helper.sh"
    transcript="${BATS_TMPDIR}/log-color.typescript"

    cat >"${helper}" <<'HELPER'
#!/usr/bin/env bash
set -euo pipefail

repo_root=$1
cd "${repo_root}"

export LOG_TAG=dccd
export LOG_TIMESTAMP="2026-05-04 00:00:32"
export LOG_COLOR=auto
export TERM=xterm

# shellcheck source=../../../scripts/lib/log.sh disable=SC1091
. "${repo_root}/scripts/lib/log.sh"

captured=$(log_warn "alloy: container(s) without healthcheck (alloy) — using \"running\" state as readiness")
printf 'captured=<%s>\n' "${captured}"
HELPER
    chmod +x "${helper}"

    printf -v cmd 'bash %q %q' "${helper}" "${REPO_ROOT}"
    run env TERM=xterm script -q -e -c "${cmd}" "${transcript}"
    assert_success

    run cat "${transcript}"
    assert_success
    assert_output --partial $'\033[1;33m'
    assert_output --partial "WARN"
    assert_output --partial "alloy: container(s) without healthcheck"
    assert_output --partial "captured=<>"
}
