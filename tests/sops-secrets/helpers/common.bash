#!/usr/bin/env bash
# Shared setup and fixtures for generate-sops-secrets.sh tests.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"

if [ ! -f "${REPO_ROOT}/tests/libs/bats-support/load.bash" ]; then
  bash "${REPO_ROOT}/tests/setup_libs.sh"
fi

load "${REPO_ROOT}/tests/libs/bats-support/load"
load "${REPO_ROOT}/tests/libs/bats-assert/load"
load "${REPO_ROOT}/tests/libs/bats-file/load"

sops_secrets_setup() {
  TEST_ROOT="$(mktemp -d "${BATS_TMPDIR}/sops-secrets-test.XXXXXX")"
  TEST_ROOT="$(cd "${TEST_ROOT}" && pwd -P)"
  MOCK_BIN="${TEST_ROOT}/bin"
  MOCK_LOG="${TEST_ROOT}/log"
  TARGET="${TEST_ROOT}/secret.sops.env"
  KEY_FILE="${TEST_ROOT}/age-keys.txt"
  PLAINTEXT="${TEST_ROOT}/plaintext.env"
  GENERATOR="${REPO_ROOT}/scripts/generate-sops-secrets.sh"
  ORIGINAL_PATH="${PATH}"

  mkdir -p "${MOCK_BIN}" "${MOCK_LOG}"
  export PATH="${MOCK_BIN}:${PATH}"
  export MOCK_BIN MOCK_LOG TARGET PLAINTEXT
  unset MOCK_OP_EXIT MOCK_OP_OUTPUT MOCK_OP_OUTPUT_FILE
  unset SOPS_AGE_KEY SOPS_AGE_KEY_CMD SOPS_AGE_KEY_FILE TARGET_HASH_BEFORE

  printf '%s\n' 'not-a-real-age-key' >"${KEY_FILE}"
  write_encrypted_target
  write_plaintext
}

sops_secrets_teardown() {
  export PATH="${ORIGINAL_PATH}"
  chmod -R u+rwX "${TEST_ROOT}" 2>/dev/null || true
  rm -rf "${TEST_ROOT}"
}

write_encrypted_target() {
  cat >"${TARGET}" <<'EOF'
FIRST=ENC[AES256_GCM,data:bW9jaw==,iv:bW9jaw==,tag:bW9jaw==,type:str]
SECOND=ENC[AES256_GCM,data:bW9jaw==,iv:bW9jaw==,tag:bW9jaw==,type:str]
EXISTING=ENC[AES256_GCM,data:bW9jaw==,iv:bW9jaw==,tag:bW9jaw==,type:str]
sops_age__list_0__map_recipient=age1example
sops_mac=ENC[AES256_GCM,data:bW9jaw==,iv:bW9jaw==,tag:bW9jaw==,type:str]
sops_version=3.13.3
EOF
}

write_plaintext() {
  cat >"${PLAINTEXT}" <<'EOF'
# leading comment
FIRST=GENERATE
SECOND=GENERATE
EXISTING=keep-this-value
# trailing comment
EOF
}

run_generator() {
  env \
    SOPS_AGE_KEY_FILE="${KEY_FILE}" \
    MOCK_PLAINTEXT="${PLAINTEXT}" \
    MOCK_TARGET="${TARGET}" \
    MOCK_DECRYPT_EXIT="${MOCK_DECRYPT_EXIT:-0}" \
    MOCK_REQUIRE_ENCRYPTED="${MOCK_REQUIRE_ENCRYPTED:-1}" \
    MOCK_SET_FAIL="${MOCK_SET_FAIL:-0}" \
    MOCK_SET_CORRUPT="${MOCK_SET_CORRUPT:-0}" \
    MOCK_OD_FAIL="${MOCK_OD_FAIL:-0}" \
    bash "${GENERATOR}" "${TARGET}" "$@"
}

file_sha256() {
  local checksum

  if command -v sha256sum >/dev/null 2>&1; then
    checksum="$(sha256sum "${1}")"
  else
    checksum="$(shasum -a 256 "${1}")"
  fi
  printf '%s\n' "${checksum%% *}"
}

file_mtime() {
  if stat -c '%Y' "${1}" >/dev/null 2>&1; then
    stat -c '%Y' "${1}"
  else
    stat -f '%m' "${1}"
  fi
}

snapshot_target() {
  TARGET_HASH_BEFORE="$(file_sha256 "${TARGET}")"
}

assert_no_generated_temp_files() {
  run find "$(dirname "${TARGET}")" -maxdepth 1 -type f -name "$(basename "${TARGET}").generated.*" -print
  assert_success
  assert_output ""
}

assert_target_unchanged() {
  run file_sha256 "${TARGET}"
  assert_success
  assert_output "${TARGET_HASH_BEFORE}"
  assert_no_generated_temp_files
}

assert_target_usable() {
  run grep -q '^sops_mac=ENC\[AES256_GCM,' "${TARGET}"
  assert_success
  run grep -q '^sops_version=' "${TARGET}"
  assert_success
  run env SOPS_AGE_KEY_FILE="${KEY_FILE}" \
    MOCK_PLAINTEXT="${PLAINTEXT}" \
    MOCK_TARGET="${TARGET}" \
    MOCK_REQUIRE_ENCRYPTED=1 \
    mise exec -- sops decrypt --input-type dotenv --output-type dotenv "${TARGET}"
  assert_success
}
