#!/usr/bin/env bats
# Unit tests for validate-sops-secrets.sh (non-printing SOPS secret validator).

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  sops_secrets_setup
  create_mise_mock
}

teardown() {
  sops_secrets_teardown
}

write_resolved_plaintext() {
  cat >"${PLAINTEXT}" <<'EOF'
DOMAINNAME=example.com
DB_ENC_PASSPHRASE=some-real-passphrase-value-not-a-sentinel
EOF
}

write_change_me_plaintext() {
  cat >"${PLAINTEXT}" <<'EOF'
DOMAINNAME=example.com
DB_ENC_PASSPHRASE=CHANGE_ME
EOF
}

@test "validate-sops-secrets: succeeds when all required variables exist and are resolved" {
  write_resolved_plaintext

  run run_validator DOMAINNAME DB_ENC_PASSPHRASE

  assert_success
  assert_output --partial "DOMAINNAME"
  assert_output --partial "DB_ENC_PASSPHRASE"
  refute_output --partial "example.com"
  refute_output --partial "some-real-passphrase-value-not-a-sentinel"
}

@test "validate-sops-secrets: fails when a required variable is missing" {
  write_resolved_plaintext
  snapshot_target

  run run_validator DOMAINNAME NEVER_DEFINED

  assert_failure
  assert_output --partial "missing required variable"
  assert_output --partial "NEVER_DEFINED"
  assert_target_unchanged
}

@test "validate-sops-secrets: rejects an invalid required variable name before decrypting" {
  write_resolved_plaintext
  snapshot_target

  run run_validator "1INVALID"

  assert_failure
  assert_output --partial "invalid variable name"
  run test ! -e "${MOCK_LOG}/mise.calls"
  assert_success
  assert_target_unchanged
}

@test "validate-sops-secrets: rejects a required variable name containing spaces" {
  write_resolved_plaintext
  snapshot_target

  run run_validator "NOT VALID"

  assert_failure
  assert_output --partial "invalid variable name"
  run test ! -e "${MOCK_LOG}/mise.calls"
  assert_success
  assert_target_unchanged
}

@test "validate-sops-secrets: fails on the exact GENERATE sentinel" {
  # The default write_plaintext fixture (from sops_secrets_setup) leaves
  # FIRST and SECOND as GENERATE. The check covers every key in the file,
  # not only the ones named on the command line.
  snapshot_target

  run run_validator EXISTING

  assert_failure
  assert_output --partial "unresolved sentinel"
  assert_output --partial "FIRST"
  assert_output --partial "SECOND"
  refute_output --partial "keep-this-value"
  assert_target_unchanged
}

@test "validate-sops-secrets: fails on the exact CHANGE_ME sentinel" {
  write_change_me_plaintext
  snapshot_target

  run run_validator DOMAINNAME DB_ENC_PASSPHRASE

  assert_failure
  assert_output --partial "unresolved sentinel"
  assert_output --partial "DB_ENC_PASSPHRASE"
  refute_output --partial "example.com"
  assert_target_unchanged
}

@test "validate-sops-secrets: a value merely containing GENERATE or CHANGE_ME as a substring is not a match" {
  cat >"${PLAINTEXT}" <<'EOF'
DOMAINNAME=example.com
DB_ENC_PASSPHRASE=please_regenerate_soon_but_not_CHANGE_MEd
EOF
  snapshot_target

  run run_validator DOMAINNAME DB_ENC_PASSPHRASE

  assert_success
  refute_output --partial "unresolved sentinel"
}

@test "validate-sops-secrets: fails when decryption fails" {
  write_resolved_plaintext
  export MOCK_DECRYPT_EXIT=1
  snapshot_target

  run run_validator DOMAINNAME

  assert_failure
  assert_output --partial "could not decrypt"
  assert_output --partial "Recommended 1Password setup"
  assert_target_unchanged
}

@test "validate-sops-secrets: fails when the target is not a SOPS-encrypted dotenv file" {
  printf 'DOMAINNAME=example.com\n' >"${TARGET}"
  snapshot_target

  run run_validator DOMAINNAME

  assert_failure
  assert_output --partial "not a SOPS-encrypted dotenv file"
  run test ! -e "${MOCK_LOG}/mise.calls"
  assert_success
  assert_target_unchanged
}

@test "validate-sops-secrets: fails clearly when the target file does not exist" {
  run env \
    SOPS_AGE_KEY_FILE="${KEY_FILE}" \
    MOCK_PLAINTEXT="${PLAINTEXT}" \
    MOCK_TARGET="${TARGET}" \
    MOCK_REQUIRE_ENCRYPTED=1 \
    bash "${VALIDATOR}" "${TEST_ROOT}/does-not-exist.env" DOMAINNAME

  assert_failure
  assert_output --partial "does not exist"
}

@test "validate-sops-secrets: rejects usage with no required variables" {
  run run_validator

  assert_failure
  assert_output --partial "Usage:"
}

@test "validate-sops-secrets: never prints decrypted secret values on the success path" {
  write_resolved_plaintext

  run run_validator DOMAINNAME DB_ENC_PASSPHRASE

  assert_success
  refute_output --partial "example.com"
  refute_output --partial "some-real-passphrase-value-not-a-sentinel"
}

@test "validate-sops-secrets: never prints decrypted secret values on a failure path" {
  write_change_me_plaintext

  run run_validator DOMAINNAME DB_ENC_PASSPHRASE

  assert_failure
  refute_output --partial "example.com"
}

@test "validate-sops-secrets: honors an explicit SOPS_BIN override" {
  write_resolved_plaintext
  local fake_sops="${TEST_ROOT}/fake-sops"
  create_fake_sops_bin "${fake_sops}"
  export SOPS_BIN="${fake_sops}"

  run run_validator DOMAINNAME DB_ENC_PASSPHRASE

  assert_success
  run test ! -e "${MOCK_LOG}/mise.calls"
  assert_success
  assert_file_exists "${MOCK_LOG}/sops.calls"
}

@test "validate-sops-secrets: an invalid SOPS_BIN override fails clearly without decrypting" {
  write_resolved_plaintext
  export SOPS_BIN="${TEST_ROOT}/does-not-exist-sops"
  snapshot_target

  run run_validator DOMAINNAME

  assert_failure
  assert_output --partial "SOPS_BIN does not exist"
  run test ! -e "${MOCK_LOG}/mise.calls"
  assert_success
  assert_target_unchanged
}

@test "validate-sops-secrets: a SOPS_BIN path containing spaces works end-to-end (quoting proof)" {
  # Same real-world concern as generate-sops-secrets.sh: paths that
  # legitimately contain spaces (e.g. Windows "C:\Program Files\..." style
  # installs) must not be word-split anywhere in the call chain.
  write_resolved_plaintext
  local fake_dir="${TEST_ROOT}/dir with spaces"
  local fake_sops="${fake_dir}/fake sops binary"
  mkdir -p "${fake_dir}"
  create_fake_sops_bin "${fake_sops}"
  export SOPS_BIN="${fake_sops}"

  run run_validator DOMAINNAME DB_ENC_PASSPHRASE

  assert_success
  run test ! -e "${MOCK_LOG}/mise.calls"
  assert_success
  assert_file_exists "${MOCK_LOG}/sops.calls"
}

@test "validate-sops-secrets: sourcing has no side effects, and the function works when called directly" {
  write_resolved_plaintext

  run source "${VALIDATOR}"
  assert_success
  assert_output ""

  export SOPS_AGE_KEY_FILE="${KEY_FILE}"
  export MOCK_PLAINTEXT="${PLAINTEXT}"
  export MOCK_TARGET="${TARGET}"
  export MOCK_REQUIRE_ENCRYPTED=1
  # shellcheck source=scripts/validate-sops-secrets.sh disable=SC1091
  source "${VALIDATOR}"

  run validate_sops_secrets "${TARGET}" DOMAINNAME DB_ENC_PASSPHRASE

  assert_success
  refute_output --partial "example.com"
}
