#!/usr/bin/env bats
# Unit tests for url_encode_simple — extracted to top-level for testability.

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }

@test "url_encode_simple: passes plain ASCII through unchanged" {
    run url_encode_simple "hello-world"
    assert_success
    assert_output "hello-world"
}

@test "url_encode_simple: encodes spaces as +" {
    run url_encode_simple "hello world"
    assert_success
    assert_output "hello+world"
}

@test "url_encode_simple: encodes ampersand as %26" {
    run url_encode_simple "a&b"
    assert_success
    assert_output "a%26b"
}

@test "url_encode_simple: encodes equals as %3D" {
    run url_encode_simple "k=v"
    assert_success
    assert_output "k%3Dv"
}

@test "url_encode_simple: encodes hash as %23" {
    run url_encode_simple "a#b"
    assert_success
    assert_output "a%23b"
}

@test "url_encode_simple: encodes combination of special chars" {
    run url_encode_simple "foo bar&baz=1#frag"
    assert_success
    assert_output "foo+bar%26baz%3D1%23frag"
}

@test "url_encode_simple: empty input produces empty output" {
    run url_encode_simple ""
    assert_success
    assert_output ""
}
