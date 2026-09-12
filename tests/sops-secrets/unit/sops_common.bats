#!/usr/bin/env bats
# Unit tests for scripts/sops-common.sh — the shared SOPS execution library
# used by both generate-sops-secrets.sh and validate-sops-secrets.sh.

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  sops_secrets_setup
  create_mise_mock
  # These tests call run_sops directly (not through run_generator/
  # run_validator), so the fake sops mock's env-var contract must be
  # supplied explicitly here instead of per-invocation.
  export SOPS_AGE_KEY_FILE="${KEY_FILE}"
  export MOCK_PLAINTEXT="${PLAINTEXT}"
  export MOCK_TARGET="${TARGET}"
  export MOCK_REQUIRE_ENCRYPTED=1
  # shellcheck source=scripts/sops-common.sh disable=SC1091
  source "${SOPS_COMMON_LIB}"
}

teardown() {
  sops_secrets_teardown
}

@test "sops_is_encrypted_dotenv: accepts a properly encrypted target" {
  run sops_is_encrypted_dotenv "${TARGET}"
  assert_success
}

@test "sops_is_encrypted_dotenv: rejects a target missing sops_mac" {
  printf 'FOO=bar\nsops_version=3.13.3\n' >"${TARGET}"

  run sops_is_encrypted_dotenv "${TARGET}"

  assert_failure
}

@test "sops_is_encrypted_dotenv: rejects a target with no ENC-encrypted variable line" {
  printf 'FOO=bar\nsops_version=3.13.3\nsops_mac=ENC[AES256_GCM,data:x,iv:x,tag:x,type:str]\n' >"${TARGET}"

  run sops_is_encrypted_dotenv "${TARGET}"

  assert_failure
}

@test "sops_is_encrypted_dotenv: rejects a nonexistent file" {
  run sops_is_encrypted_dotenv "${TEST_ROOT}/does-not-exist.env"
  assert_failure
}

@test "run_sops: default path invokes mise exec -- sops and logs the call" {
  run run_sops decrypt --input-type dotenv --output-type dotenv --extract '["FIRST"]' "${TARGET}"

  assert_success
  assert_output "GENERATE"
  assert_file_exists "${MOCK_LOG}/mise.calls"
}

@test "run_sops: explicit SOPS_BIN bypasses mise entirely" {
  local fake_sops="${TEST_ROOT}/fake-sops"
  create_fake_sops_bin "${fake_sops}"
  export SOPS_BIN="${fake_sops}"

  run run_sops decrypt --input-type dotenv --output-type dotenv --extract '["FIRST"]' "${TARGET}"

  assert_success
  assert_output "GENERATE"
  run test ! -e "${MOCK_LOG}/mise.calls"
  assert_success
  assert_file_exists "${MOCK_LOG}/sops.calls"
}

@test "run_sops: a SOPS_BIN path containing spaces is invoked correctly (quoting proof)" {
  # Mirrors real-world paths that legitimately contain spaces (e.g. Windows
  # "C:\Program Files\..." style installs resolved via `mise which sops` and
  # confirmed to work unmodified under Git Bash). An unquoted invocation
  # would word-split this into multiple bogus arguments and fail with
  # "command not found" instead of actually running the binary.
  local fake_dir="${TEST_ROOT}/dir with spaces"
  local fake_sops="${fake_dir}/fake sops binary"
  mkdir -p "${fake_dir}"
  create_fake_sops_bin "${fake_sops}"
  export SOPS_BIN="${fake_sops}"

  run run_sops decrypt --input-type dotenv --output-type dotenv --extract '["FIRST"]' "${TARGET}"

  assert_success
  assert_output "GENERATE"
  run test ! -e "${MOCK_LOG}/mise.calls"
  assert_success
  assert_file_exists "${MOCK_LOG}/sops.calls"
}

@test "run_sops: a bare SOPS_BIN command resolvable on PATH is accepted and bypasses mise" {
  local fake_sops="${MOCK_BIN}/fake-sops-on-path"
  create_fake_sops_bin "${fake_sops}"
  export SOPS_BIN="fake-sops-on-path"

  run run_sops decrypt --input-type dotenv --output-type dotenv --extract '["FIRST"]' "${TARGET}"

  assert_success
  assert_output "GENERATE"
  run test ! -e "${MOCK_LOG}/mise.calls"
  assert_success
}

@test "run_sops: rejects a SOPS_BIN pointing at a nonexistent path" {
  export SOPS_BIN="${TEST_ROOT}/does-not-exist"

  run run_sops decrypt --input-type dotenv --output-type dotenv "${TARGET}"

  assert_failure
  assert_output --partial "SOPS_BIN does not exist"
  run test ! -e "${MOCK_LOG}/mise.calls"
  assert_success
}

@test "run_sops: rejects a SOPS_BIN pointing at a directory" {
  export SOPS_BIN="${TEST_ROOT}"

  run run_sops decrypt --input-type dotenv --output-type dotenv "${TARGET}"

  assert_failure
  assert_output --partial "not a regular file"
  run test ! -e "${MOCK_LOG}/mise.calls"
  assert_success
}

@test "run_sops: rejects a SOPS_BIN pointing at a non-executable regular file" {
  local not_executable="${TEST_ROOT}/not-executable"
  printf '#!/bin/sh\n' >"${not_executable}"
  chmod -x "${not_executable}"
  export SOPS_BIN="${not_executable}"

  run run_sops decrypt --input-type dotenv --output-type dotenv "${TARGET}"

  assert_failure
  assert_output --partial "not executable"
  run test ! -e "${MOCK_LOG}/mise.calls"
  assert_success
}

@test "run_sops: rejects a bare SOPS_BIN command that is not on PATH" {
  export SOPS_BIN="definitely-not-a-real-sops-binary"

  run run_sops decrypt --input-type dotenv --output-type dotenv "${TARGET}"

  assert_failure
  assert_output --partial "not found on PATH"
  run test ! -e "${MOCK_LOG}/mise.calls"
  assert_success
}

@test "run_sops: SOPS_AGE_KEY_CMD isolation is preserved with an explicit SOPS_BIN" {
  local fake_sops="${TEST_ROOT}/fake-sops"
  create_fake_sops_bin "${fake_sops}"
  export SOPS_BIN="${fake_sops}"
  create_op_mock
  export MOCK_OP_OUTPUT="AGE-SECRET-KEY-1TESTTEST"
  export SOPS_AGE_KEY_CMD='op read "op://TestVault/AgeKey/private-key"'
  export SOPS_AGE_KEY="should-never-be-consulted"

  run run_sops decrypt --input-type dotenv --output-type dotenv --extract '["FIRST"]' "${TARGET}"

  assert_success
  assert_output "GENERATE"
  run grep -q '^command$' "${MOCK_LOG}/key-source.calls"
  assert_success
}

@test "run_sops: SOPS_AGE_KEY_CMD isolation is preserved through the default mise path" {
  create_op_mock
  export MOCK_OP_OUTPUT="AGE-SECRET-KEY-1TESTTEST"
  export SOPS_AGE_KEY_CMD='op read "op://TestVault/AgeKey/private-key"'
  export SOPS_AGE_KEY="should-never-be-consulted"

  run run_sops decrypt --input-type dotenv --output-type dotenv --extract '["FIRST"]' "${TARGET}"

  assert_success
  assert_output "GENERATE"
  run grep -q '^command$' "${MOCK_LOG}/key-source.calls"
  assert_success
}
