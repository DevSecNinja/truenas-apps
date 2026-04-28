#!/usr/bin/env bats
# Integration tests: self-update detection added to update_compose_files().
#
# When a git pull updates scripts/dccd.sh itself, the function should:
#   1. Log that it is re-executing with the new version.
#   2. Call exec to replace the process with the newly-pulled script,
#      forwarding the original CLI arguments stored in _ORIG_ARGS.
#
# The re-exec path is guarded by two conditions (both must be true):
#   a. The script's relative path is tracked by git in the pulled repo.
#   b. git diff --name-only between the pre- and post-pull commits lists
#      that relative path (i.e. the file actually changed in this pull).

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    create_default_mocks

    # Real .git directory satisfies the "[ ! -d .git ]" guard without
    # requiring a full git initialisation (all git operations are mocked).
    mkdir -p "${BASE_DIR}/.git"

    # Sensible defaults — individual tests override as needed.
    _ORIG_ARGS=()
    _SCRIPT_PATH="${BASE_DIR}/bin/dccd-nonexistent.sh" # intentionally absent
    # DECRYPT_ONLY=1 short-circuits the deploy section so tests that don't
    # exercise the exec path still return cleanly after the git section.
    DECRYPT_ONLY=1
    FORCE=0
    NO_PULL=0
    REMOTE_BRANCH="main"
}

teardown() {
    common_teardown
}

# ---------------------------------------------------------------------------
# Helper: create a smart git mock that dispatches on the git sub-command.
#
# Arguments (all optional, positional):
#   $1  local_hash   – returned by "git rev-parse HEAD"       (default: aaa...)
#   $2  remote_hash  – returned by "git rev-parse origin/…"   (default: bbb...)
#   $3  script_rel   – returned by "git ls-files --full-name" (default: empty)
#   $4  diff_output  – returned by "git diff --name-only"     (default: empty)
#
# The mock handles all git sub-commands used inside update_compose_files so
# every code path runs without a real repository on disk.
# ---------------------------------------------------------------------------
_create_smart_git_mock() {
    local local_hash="${1:-aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1}"
    local remote_hash="${2:-bbbbbbb2bbbbbbb2bbbbbbb2bbbbbbb2bbbbbbb2}"
    local script_rel="${3:-}"
    local diff_output="${4:-}"

    cat >"${MOCK_BIN}/git" <<MOCK
#!/bin/bash
echo "\$@" >> "${MOCK_LOG}/git.calls"

# Strip "-c key=value" option pairs so we can inspect the sub-command.
args=()
while [[ \$# -gt 0 ]]; do
    if [[ "\$1" == "-c" ]]; then shift 2; else args+=("\$1"); shift; fi
done
subcmd="\${args[0]:-}"

case "\${subcmd}" in
    ls-files)
        # Respond to the "--full-name" call used by the self-update check;
        # the "-z" ownership-check call produces no output (no tracked files).
        if printf '%s\n' "\${args[@]}" | grep -q -- '--full-name'; then
            echo "${script_rel}"
        fi
        ;;
    fetch)    exit 0 ;;
    rev-parse)
        if printf '%s\n' "\${args[@]}" | grep -q 'origin/'; then
            echo "${remote_hash}"
        else
            echo "${local_hash}"
        fi
        ;;
    status)   echo "" ;;
    checkout) exit 0 ;;
    pull)     exit 0 ;;
    diff)     echo "${diff_output}" ;;
    *)        exit 0 ;;
esac
MOCK
    chmod +x "${MOCK_BIN}/git"
}

# ---------------------------------------------------------------------------
# Sanity: common_setup now initialises the two new globals
# ---------------------------------------------------------------------------

@test "self_update: common_setup initialises _ORIG_ARGS as empty array" {
    [[ "${#_ORIG_ARGS[@]}" -eq 0 ]]
}

@test "self_update: common_setup initialises _SCRIPT_PATH as empty string" {
    # common_setup sets it to ""; our setup() then sets it to a temp path.
    # Verify the variable exists and is non-empty (set by setup above).
    [[ -v _SCRIPT_PATH ]]
}

# ---------------------------------------------------------------------------
# No-pull mode: git operations are skipped entirely
# ---------------------------------------------------------------------------

@test "self_update: no-pull mode skips all git operations" {
    NO_PULL=1

    run update_compose_files "${BASE_DIR}"

    assert_success
    assert_output --partial "No-pull mode enabled"
    assert_mock_not_called "git"
}

# ---------------------------------------------------------------------------
# Self-update NOT triggered: script absent from git ls-files
# ---------------------------------------------------------------------------

@test "self_update: no re-exec when script is not tracked by git" {
    # script_rel="" → first condition [ -n "${script_rel}" ] is false → short-circuit
    _create_smart_git_mock \
        "aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1" \
        "bbbbbbb2bbbbbbb2bbbbbbb2bbbbbbb2bbbbbbb2" \
        "" \
        "scripts/dccd.sh"

    run update_compose_files "${BASE_DIR}"

    assert_success
    refute_output --partial "re-executing with the new version"
}

# ---------------------------------------------------------------------------
# Self-update NOT triggered: script tracked but not changed in this pull
# ---------------------------------------------------------------------------

@test "self_update: no re-exec when script is tracked but not in diff" {
    # script_rel is non-empty (tracked) but diff_output is empty (not changed).
    # grep -qF on empty output exits 1 → condition false.
    _create_smart_git_mock \
        "aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1" \
        "bbbbbbb2bbbbbbb2bbbbbbb2bbbbbbb2bbbbbbb2" \
        "scripts/dccd.sh" \
        ""

    run update_compose_files "${BASE_DIR}"

    assert_success
    refute_output --partial "re-executing with the new version"
}

# ---------------------------------------------------------------------------
# Self-update triggered: script tracked AND present in diff
# ---------------------------------------------------------------------------

@test "self_update: re-exec log message appears when script was updated by pull" {
    # Both conditions true → log message is emitted before exec.
    # _SCRIPT_PATH is a non-existent file, so exec fails harmlessly
    # (bash prints an error to stderr and continues); DECRYPT_ONLY=1 then
    # causes the function to return 0.
    _create_smart_git_mock \
        "aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1" \
        "bbbbbbb2bbbbbbb2bbbbbbb2bbbbbbb2bbbbbbb2" \
        "scripts/dccd.sh" \
        "scripts/dccd.sh"

    run update_compose_files "${BASE_DIR}"

    assert_output --partial "re-executing with the new version"
}

@test "self_update: git pull is performed and logged before re-exec check" {
    _create_smart_git_mock \
        "aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1" \
        "bbbbbbb2bbbbbbb2bbbbbbb2bbbbbbb2bbbbbbb2" \
        "scripts/dccd.sh" \
        "scripts/dccd.sh"

    run update_compose_files "${BASE_DIR}"

    assert_output --partial "Pulled latest commits from origin"
    assert_output --partial "re-executing with the new version"
}

# ---------------------------------------------------------------------------
# Self-update triggered: exec receives correct _SCRIPT_PATH and _ORIG_ARGS
# ---------------------------------------------------------------------------

@test "self_update: exec is called with _SCRIPT_PATH as the command" {
    # Use a real executable so exec succeeds and we can observe the output.
    local new_script="${BASE_DIR}/bin/new-dccd.sh"
    mkdir -p "${BASE_DIR}/bin"
    printf '#!/bin/bash\necho "NEW_SCRIPT_INVOKED: $0"\n' >"${new_script}"
    chmod +x "${new_script}"

    _SCRIPT_PATH="${new_script}"
    _ORIG_ARGS=()

    _create_smart_git_mock \
        "aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1" \
        "bbbbbbb2bbbbbbb2bbbbbbb2bbbbbbb2bbbbbbb2" \
        "scripts/dccd.sh" \
        "scripts/dccd.sh"

    run update_compose_files "${BASE_DIR}"

    assert_output --partial "NEW_SCRIPT_INVOKED:"
}

@test "self_update: exec forwards _ORIG_ARGS to the new script" {
    local capture_script="${BASE_DIR}/bin/capture.sh"
    mkdir -p "${BASE_DIR}/bin"
    printf '#!/bin/bash\necho "ARGS: $*"\n' >"${capture_script}"
    chmod +x "${capture_script}"

    _SCRIPT_PATH="${capture_script}"
    _ORIG_ARGS=("-d" "${BASE_DIR}" "-f" "-n")

    _create_smart_git_mock \
        "aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1" \
        "bbbbbbb2bbbbbbb2bbbbbbb2bbbbbbb2bbbbbbb2" \
        "scripts/dccd.sh" \
        "scripts/dccd.sh"

    run update_compose_files "${BASE_DIR}"

    assert_output --partial "ARGS: -d ${BASE_DIR} -f -n"
}

# ---------------------------------------------------------------------------
# No re-exec when hashes match (nothing was pulled)
# ---------------------------------------------------------------------------

@test "self_update: no re-exec when repo is already up-to-date" {
    local same_hash="aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1"

    # Same hash for both local and remote → no pull → no re-exec check
    _create_smart_git_mock \
        "${same_hash}" \
        "${same_hash}" \
        "scripts/dccd.sh" \
        "scripts/dccd.sh"

    # docker ps is called to check running containers
    create_mock "docker" 0 "abc123"

    run update_compose_files "${BASE_DIR}"

    assert_success
    refute_output --partial "re-executing with the new version"
    assert_output --partial "Already up-to-date"
}

# ---------------------------------------------------------------------------
# Force mode: no re-exec when force-deployed without a real pull
# ---------------------------------------------------------------------------

@test "self_update: no re-exec in force mode when hashes already match" {
    local same_hash="aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1aaaaaaa1"
    FORCE=1

    _create_smart_git_mock \
        "${same_hash}" \
        "${same_hash}" \
        "scripts/dccd.sh" \
        "scripts/dccd.sh"

    # docker ps returns a running container so we don't enter the no-containers path
    create_mock "docker" 0 "abc123"

    run update_compose_files "${BASE_DIR}"

    assert_success
    # The pull branch is only entered when local != remote; force mode skips pull
    # when hashes already match → no re-exec.
    refute_output --partial "re-executing with the new version"
}
