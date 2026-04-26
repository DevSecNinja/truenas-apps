#!/usr/bin/env bats
# Unit tests for compute_config_hash()
#
# compute_config_hash <app_dir>:
#   - Returns "" when <app_dir>/config does not exist.
#   - Returns a non-empty SHA-256 hex string when <app_dir>/config/ has files.
#   - Is deterministic: same files → same hash on repeated calls.
#   - Is sensitive to changes: adding/modifying/removing a file changes the hash.
#
# The function uses real find/sort/sha256sum/xargs — no mocking needed for those.
# We keep the logger/date mocks from common_setup so log_message doesn't fail.

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
    # sha256sum, find, sort, xargs are real system tools — do not mock them.
}

teardown() {
    common_teardown
}

# ---------------------------------------------------------------------------
# Helper: create an app directory tree under BASE_DIR/services/<name>
# ---------------------------------------------------------------------------
_make_app_dir() {
    local name="$1"
    mkdir -p "${BASE_DIR}/services/${name}"
    echo "${BASE_DIR}/services/${name}"
}

# ---------------------------------------------------------------------------
# Helper: assert a string is a valid lowercase SHA-256 hex (64 hex chars)
# ---------------------------------------------------------------------------
_assert_is_sha256() {
    local value="$1"
    [[ "${value}" =~ ^[0-9a-f]{64}$ ]] || {
        echo "Expected a 64-char hex SHA-256, got: '${value}'" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# Test 1 — no config directory → empty string
# ---------------------------------------------------------------------------
@test "compute_config_hash: returns empty string when no config directory exists" {
    local app_dir
    app_dir=$(_make_app_dir "myapp")
    # Deliberately do NOT create config/

    run compute_config_hash "${app_dir}"
    assert_success
    assert_output ""
}

# ---------------------------------------------------------------------------
# Test 2 — config directory exists but is empty → still a hash (sha256sum of
#           an empty stream produces a well-defined hash).
#           Actually: `find ... -type f | sort` yields nothing, so
#           `xargs sha256sum` produces no output, and `sha256sum` of empty
#           input IS a defined value.  The implementation returns that hash.
# ---------------------------------------------------------------------------
@test "compute_config_hash: returns a hash for an empty config directory" {
    local app_dir
    app_dir=$(_make_app_dir "emptyconfig")
    mkdir -p "${app_dir}/config"

    run compute_config_hash "${app_dir}"
    assert_success
    # sha256sum of an empty stream is a valid 64-char hex string
    _assert_is_sha256 "${output}"
}

# ---------------------------------------------------------------------------
# Test 3 — config directory with files → non-empty hash
# ---------------------------------------------------------------------------
@test "compute_config_hash: returns a non-empty hash when config directory has files" {
    local app_dir
    app_dir=$(_make_app_dir "withfiles")
    mkdir -p "${app_dir}/config"
    echo "key=value" >"${app_dir}/config/app.conf"
    echo "more=data" >"${app_dir}/config/extra.conf"

    run compute_config_hash "${app_dir}"
    assert_success
    _assert_is_sha256 "${output}"
}

# ---------------------------------------------------------------------------
# Test 4 — determinism: calling twice with unchanged files yields the same hash
# ---------------------------------------------------------------------------
@test "compute_config_hash: returns the same hash on repeated calls when files unchanged" {
    local app_dir
    app_dir=$(_make_app_dir "determinism")
    mkdir -p "${app_dir}/config"
    echo "stable=content" >"${app_dir}/config/stable.conf"
    printf 'line1\nline2\nline3\n' >"${app_dir}/config/multi.conf"

    run compute_config_hash "${app_dir}"
    assert_success
    local hash1="${output}"
    _assert_is_sha256 "${hash1}"

    run compute_config_hash "${app_dir}"
    assert_success
    local hash2="${output}"

    [ "${hash1}" = "${hash2}" ] || {
        echo "Hashes differ across calls: '${hash1}' vs '${hash2}'" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# Test 5 — sensitivity: modifying a file changes the hash
# ---------------------------------------------------------------------------
@test "compute_config_hash: returns a different hash after a file is modified" {
    local app_dir
    app_dir=$(_make_app_dir "modified")
    mkdir -p "${app_dir}/config"
    echo "original=value" >"${app_dir}/config/setting.conf"

    run compute_config_hash "${app_dir}"
    assert_success
    local hash_before="${output}"
    _assert_is_sha256 "${hash_before}"

    # Modify the file content
    echo "changed=value" >"${app_dir}/config/setting.conf"

    run compute_config_hash "${app_dir}"
    assert_success
    local hash_after="${output}"
    _assert_is_sha256 "${hash_after}"

    [ "${hash_before}" != "${hash_after}" ] || {
        echo "Hash did not change after file modification: '${hash_before}'" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# Test 6 — sensitivity: adding a new file changes the hash
# ---------------------------------------------------------------------------
@test "compute_config_hash: returns a different hash after a file is added" {
    local app_dir
    app_dir=$(_make_app_dir "addfile")
    mkdir -p "${app_dir}/config"
    echo "existing=1" >"${app_dir}/config/base.conf"

    run compute_config_hash "${app_dir}"
    assert_success
    local hash_before="${output}"
    _assert_is_sha256 "${hash_before}"

    # Add a second file
    echo "new=2" >"${app_dir}/config/new.conf"

    run compute_config_hash "${app_dir}"
    assert_success
    local hash_after="${output}"
    _assert_is_sha256 "${hash_after}"

    [ "${hash_before}" != "${hash_after}" ] || {
        echo "Hash did not change after adding a file: '${hash_before}'" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# Test 7 — sensitivity: removing a file changes the hash
# ---------------------------------------------------------------------------
@test "compute_config_hash: returns a different hash after a file is removed" {
    local app_dir
    app_dir=$(_make_app_dir "removefile")
    mkdir -p "${app_dir}/config"
    echo "keep=me" >"${app_dir}/config/keep.conf"
    echo "delete=me" >"${app_dir}/config/delete.conf"

    run compute_config_hash "${app_dir}"
    assert_success
    local hash_before="${output}"
    _assert_is_sha256 "${hash_before}"

    rm "${app_dir}/config/delete.conf"

    run compute_config_hash "${app_dir}"
    assert_success
    local hash_after="${output}"
    _assert_is_sha256 "${hash_after}"

    [ "${hash_before}" != "${hash_after}" ] || {
        echo "Hash did not change after removing a file: '${hash_before}'" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# Test 8 — subdirectory support: files in nested subdirs are included
# ---------------------------------------------------------------------------
@test "compute_config_hash: includes files in nested config subdirectories" {
    local app_dir
    app_dir=$(_make_app_dir "nested")
    mkdir -p "${app_dir}/config/subdir"
    echo "root=value" >"${app_dir}/config/root.conf"
    echo "nested=value" >"${app_dir}/config/subdir/nested.conf"

    run compute_config_hash "${app_dir}"
    assert_success
    local hash_with_nested="${output}"
    _assert_is_sha256 "${hash_with_nested}"

    # Remove the nested file — hash should change
    rm "${app_dir}/config/subdir/nested.conf"

    run compute_config_hash "${app_dir}"
    assert_success
    local hash_without_nested="${output}"

    [ "${hash_with_nested}" != "${hash_without_nested}" ] || {
        echo "Hash did not change when nested file removed: '${hash_with_nested}'" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# Test 9 — path argument: only config/ dir inside given app_dir is hashed;
#           a sibling app's config/ does NOT affect the result.
# ---------------------------------------------------------------------------
@test "compute_config_hash: only hashes config inside the given app_dir" {
    local app_a app_b
    app_a=$(_make_app_dir "app-a")
    app_b=$(_make_app_dir "app-b")
    mkdir -p "${app_a}/config"
    mkdir -p "${app_b}/config"
    echo "a=1" >"${app_a}/config/a.conf"
    echo "b=2" >"${app_b}/config/b.conf"

    run compute_config_hash "${app_a}"
    assert_success
    local hash_a="${output}"

    run compute_config_hash "${app_b}"
    assert_success
    local hash_b="${output}"

    [ "${hash_a}" != "${hash_b}" ] || {
        echo "Different apps produced the same hash: '${hash_a}'" >&2
        return 1
    }
}
