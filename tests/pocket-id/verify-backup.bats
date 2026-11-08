#!/usr/bin/env bats
# Regression coverage for the ORIGINAL backup01-now post-validation guard.
# All fixtures are synthetic. Only sha1sum is real; no crypto/SQLite/runtime proof.

load 'helpers/common'

setup_file() {
  pocket_require_helpers
}

setup() {
  pocket_setup
}

teardown() {
  pocket_teardown
}

@test "verify-backup: accepts one original dump/completion and validates every stage" {
  local inherited
  inherited="$(umask)"
  run_verify
  assert_success
  assert_stderr ''
  assert_line "${POCKET_ARTIFACT}: OK"
  assert_line 'Pocket ID backup verified: one GPG/ZSTD/SHA1 snapshot, SQLite integrity and keys present'
  refute_output --partial "${DEFAULT_ENCRYPT_PASSPHRASE}"
  assert_dir_exists "${POCKET_BACKUP}"
  assert_file_exists "${POCKET_BACKUP}/${POCKET_ARTIFACT}"
  assert_file_exists "${POCKET_BACKUP}/${POCKET_ARTIFACT}.sha1"
  local stage
  for stage in source backup01-now gpg zstd integrity foreign-key migration keys; do
    assert_file_exists "${MOCK_LOG}/${stage}.called"
  done
  assert_recorded_umask backup01-now "${inherited}"
  assert_verification_umasks_private
  run find "${TMPDIR}" -mindepth 1 -print
  assert_success
  assert_output ''
}

@test "verify-backup: restores caller umask 0022 only for the original upstream job" {
  local expected
  expected="$(
    umask 0022
    umask
  )"
  run_verify_with_umask 0022
  assert_success
  assert_output --partial 'Pocket ID backup verified:'
  assert_recorded_umask backup01-now "${expected}"
  assert_verification_umasks_private
}

@test "verify-backup: preserves nondefault caller umask 0027 without leaking it to verification" {
  local expected
  expected="$(
    umask 0027
    umask
  )"
  run_verify_with_umask 0027
  assert_success
  assert_output --partial 'Pocket ID backup verified:'
  assert_recorded_umask backup01-now "${expected}"
  assert_verification_umasks_private
}

@test "verify-backup: source-open failure prevents the upstream job" {
  export POCKET_CASE=source-open
  run_verify
  assert_guard_failure 'source is not initialized/readable'
  assert_file_exists "${MOCK_LOG}/source.called"
  assert_file_not_exist "${MOCK_LOG}/backup01-now.called"
}

@test "verify-backup: unready migration state prevents the upstream job" {
  export POCKET_CASE=source-unready
  run_verify
  assert_guard_failure 'source migration state is not ready'
  assert_file_not_exist "${MOCK_LOG}/backup01-now.called"
}

@test "verify-backup: nonzero upstream status fails despite success-shaped logs" {
  export POCKET_CASE=job-exit
  run_verify
  assert_guard_failure 'upstream job exited 23'
  assert_file_not_exist "${MOCK_LOG}/gpg.called"
}

@test "verify-backup: exit-zero upstream operation errors fail closed" {
  export POCKET_CASE=error-log
  local error
  for error in 'reported errors' 'Skipping encryption' 'Skipping Checksum' 'Encryption failed' 'SQLite3 backup failed'; do
    export POCKET_LOG_ERROR="${error}"
    run_verify
    assert_guard_failure 'upstream reported an operation failure'
    assert_file_not_exist "${MOCK_LOG}/gpg.called"
  done
}

@test "verify-backup: missing dump log is rejected" {
  export POCKET_CASE=missing-dump
  run_verify
  assert_guard_failure 'expected exactly one dump'
  assert_file_not_exist "${MOCK_LOG}/gpg.called"
}

@test "verify-backup: duplicate dump logs are rejected" {
  export POCKET_CASE=duplicate-dump
  run_verify
  assert_guard_failure 'expected exactly one dump'
  assert_file_not_exist "${MOCK_LOG}/gpg.called"
}

@test "verify-backup: missing successful completion is rejected" {
  export POCKET_CASE=missing-completion
  run_verify
  assert_guard_failure 'expected exactly one successful upstream completion'
  assert_file_not_exist "${MOCK_LOG}/gpg.called"
}

@test "verify-backup: duplicate successful completions are rejected" {
  export POCKET_CASE=duplicate-completion
  run_verify
  assert_guard_failure 'expected exactly one successful upstream completion'
  assert_file_not_exist "${MOCK_LOG}/gpg.called"
}

@test "verify-backup: success logs without output are rejected" {
  export POCKET_CASE=no-output
  run_verify
  assert_guard_failure 'expected exactly one new encrypted/checksum pair'
  assert_file_not_exist "${MOCK_LOG}/gpg.called"
}

@test "verify-backup: two new encrypted pairs are rejected" {
  export POCKET_CASE=duplicate-pair
  run_verify
  assert_guard_failure 'expected exactly one new encrypted/checksum pair'
  assert_file_exists "${POCKET_BACKUP}/${POCKET_EXTRA_ARTIFACT}.sha1"
  assert_file_not_exist "${MOCK_LOG}/gpg.called"
}

@test "verify-backup: real SHA1 rejects ciphertext changed after manifest generation" {
  export POCKET_CASE=bad-checksum
  run_verify
  assert_guard_failure 'encrypted artifact checksum failed'
  assert_line "${POCKET_ARTIFACT}: FAILED"
  assert_file_not_exist "${MOCK_LOG}/gpg.called"
}

@test "verify-backup: manifest naming a different artifact is rejected" {
  export POCKET_CASE=wrong-manifest-name
  run_verify
  assert_guard_failure 'checksum must name only this encrypted artifact'
  assert_file_not_exist "${MOCK_LOG}/gpg.called"
}

@test "verify-backup: nonprivate output permissions are rejected" {
  export POCKET_CASE=output-mode
  run_verify
  assert_guard_failure 'output ownership or permissions are incorrect'
  assert_file_not_exist "${MOCK_LOG}/gpg.called"
}

@test "verify-backup: nonprivate backup directory is rejected" {
  export POCKET_CASE=directory-mode
  run_verify
  assert_guard_failure 'backup directory must be private'
  assert_file_not_exist "${MOCK_LOG}/gpg.called"
}

@test "verify-backup: decrypt failure prevents decompression" {
  export POCKET_CASE=decrypt-fail
  run_verify
  assert_guard_failure 'encrypted artifact cannot be decrypted'
  assert_file_exists "${MOCK_LOG}/gpg.called"
  assert_file_not_exist "${MOCK_LOG}/zstd.called"
}

@test "verify-backup: decompression failure prevents snapshot queries" {
  export POCKET_CASE=decompress-fail
  run_verify
  assert_guard_failure 'decrypted artifact is not valid ZSTD'
  assert_file_exists "${MOCK_LOG}/zstd.called"
  assert_file_not_exist "${MOCK_LOG}/integrity.called"
}

@test "verify-backup: integrity corruption prevents foreign-key and key checks" {
  export POCKET_CASE=integrity-fail
  run_verify
  assert_guard_failure 'restored SQLite integrity check failed'
  assert_file_exists "${MOCK_LOG}/integrity.called"
  assert_file_not_exist "${MOCK_LOG}/foreign-key.called"
  assert_file_not_exist "${MOCK_LOG}/keys.called"
}

@test "verify-backup: integrity query SQL error fails closed" {
  export POCKET_CASE=integrity-sql-error
  run_verify
  assert_guard_failure 'restored SQLite integrity'
  assert_file_not_exist "${MOCK_LOG}/foreign-key.called"
}

@test "verify-backup: foreign-key SQL error with empty stdout fails closed" {
  # Protect the parent's explicit status capture: [[ -z $(sqlite3 ...) ]] alone
  # mistakes an empty failed query for success. Never skip this regression.
  export POCKET_CASE=fk-sql-error
  run_verify
  assert_guard_failure 'foreign-key'
  assert_file_exists "${MOCK_LOG}/foreign-key.called"
  assert_file_not_exist "${MOCK_LOG}/migration.called"
  assert_file_not_exist "${MOCK_LOG}/keys.called"
}

@test "verify-backup: reported foreign-key violations fail closed" {
  export POCKET_CASE=fk-violation
  run_verify
  assert_guard_failure 'restored SQLite foreign-key check failed'
  assert_file_not_exist "${MOCK_LOG}/migration.called"
}

@test "verify-backup: missing signing or session row fails closed" {
  export POCKET_CASE=missing-keys
  run_verify
  assert_guard_failure 'restored signing/session keys are missing'
  assert_file_exists "${MOCK_LOG}/keys.called"
}

@test "verify-backup: restored migration must match the live source" {
  export POCKET_CASE=migration-mismatch
  run_verify
  assert_guard_failure 'restored migration version differs'
  assert_file_not_exist "${MOCK_LOG}/keys.called"
}

@test "verify-backup: integrity-clean empty snapshot without app schema fails closed" {
  # Model the observed empty-DB failure: integrity=ok and no FK violations do
  # not prove that the original job included the initialized application schema.
  export POCKET_CASE=missing-schema
  run_verify
  assert_guard_failure 'restored migration query failed'
  assert_file_exists "${MOCK_LOG}/integrity.called"
  assert_file_exists "${MOCK_LOG}/foreign-key.called"
  assert_file_exists "${MOCK_LOG}/migration.called"
  assert_file_not_exist "${MOCK_LOG}/keys.called"
}

@test "verify-backup: a prior successful pair cannot mask a current job with no output" {
  run_verify
  assert_success
  assert_output --partial 'Pocket ID backup verified:'
  assert_file_exists "${POCKET_BACKUP}/${POCKET_ARTIFACT}.sha1"
  rm -- "${MOCK_LOG}/gpg.called"

  export POCKET_CASE=no-output
  run_verify
  assert_guard_failure 'expected exactly one new encrypted/checksum pair'
  assert_file_exists "${POCKET_BACKUP}/${POCKET_ARTIFACT}"
  assert_file_exists "${POCKET_BACKUP}/${POCKET_ARTIFACT}.sha1"
  assert_file_not_exist "${MOCK_LOG}/gpg.called"
}
