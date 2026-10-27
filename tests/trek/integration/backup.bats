#!/usr/bin/env bats
# Wrapper integration only; encryption/SQLite semantics are covered by runtime tests.

load '../helpers/common'

setup_file() {
	trek_setup_file
}

setup() {
	trek_backup_setup
}

teardown() {
	trek_teardown
}

@test "backup: succeeds only after validating the new encrypted pair through every stage" {
	run_backup
	assert_success
	assert_line 'TREK encrypted backup verified: SHA1, GPG, ZSTD, SQLite integrity and schema.'
	refute_output --partial "${DEFAULT_ENCRYPT_PASSPHRASE}"
	local stage
	for stage in timeout backup01-now find sha1sum gpg zstd sqlite-integrity sqlite-schema; do
		assert_called "${stage}"
	done
	assert_called upstream-umask-022
	assert_called verification-umask-077
	assert_file_exists "${BACKUP_ROOT}/sqlite3_travel_current.sqlite3.zst.gpg"
	assert_file_exists "${BACKUP_ROOT}/sqlite3_travel_current.sqlite3.zst.gpg.sha1"
	assert_backup_cleaned
}

@test "backup: rejects upstream exit zero with no new dump even when an old pair exists" {
	export BACKUP_SCENARIO=no-dump
	run_backup
	assert_backup_rejected 'expected exactly one new encrypted dump and one SHA1 sidecar'
	assert_called backup01-now
	assert_not_called sha1sum
}

@test "backup: propagates nonzero upstream status and cleans temporary files" {
	export BACKUP_SCENARIO=upstream-failure
	run_backup
	assert_failure 23
	assert_backup_rejected 'backup or verification command failed'
	assert_called timeout
	assert_called backup01-now
	assert_not_called find
	assert_not_called sha1sum
}

@test "backup: propagates timeout status and cleans temporary files without starting verification" {
	export BACKUP_SCENARIO=timeout
	run_backup
	assert_failure 124
	assert_output --partial 'mock upstream timed out'
	assert_backup_rejected 'backup or verification command failed'
	assert_called timeout
	assert_not_called find
	assert_not_called sha1sum
	assert_not_called gpg
	assert_not_called sqlite3
}

@test "backup: rejects a missing SHA1 sidecar" {
	export BACKUP_SCENARIO=missing-sha1
	run_backup
	assert_backup_rejected 'expected exactly one new encrypted dump and one SHA1 sidecar'
	assert_not_called sha1sum
}

@test "backup: rejects a sidecar whose basename does not match the dump" {
	export BACKUP_SCENARIO=wrong-sidecar-name
	run_backup
	assert_backup_rejected 'dump and checksum do not form a nonempty output pair'
	assert_not_called sha1sum
}

@test "backup: rejects an empty encrypted dump" {
	export BACKUP_SCENARIO=empty-dump
	run_backup
	assert_backup_rejected 'dump and checksum do not form a nonempty output pair'
	assert_not_called sha1sum
}

@test "backup: rejects SHA1 verification failure before attempting decryption" {
	export BACKUP_SCENARIO=checksum-failure
	run_backup
	assert_failure 31
	assert_backup_rejected 'mock SHA1 mismatch'
	assert_not_called gpg
	assert_not_called sqlite3
}

@test "backup: pipefail rejects failed GPG even if downstream ZSTD succeeds" {
	export BACKUP_SCENARIO=gpg-failure
	run_backup
	assert_failure 32
	assert_backup_rejected 'mock GPG failure'
	assert_called gpg
	assert_called zstd
	assert_not_called sqlite3
}

@test "backup: rejects ZSTD failure and removes partially restored SQLite and GnuPG state" {
	export BACKUP_SCENARIO=zstd-failure
	run_backup
	assert_failure 33
	assert_backup_rejected 'mock ZSTD failure'
	assert_not_called sqlite3
}

@test "backup: rejects non-ok SQLite quick_check output" {
	export BACKUP_SCENARIO=integrity-failure
	run_backup
	assert_backup_rejected 'restored SQLite integrity check failed'
	assert_called sqlite-integrity
	assert_not_called sqlite-schema
}

@test "backup: rejects a SQLite quick_check command error" {
	export BACKUP_SCENARIO=integrity-error
	run_backup
	assert_failure 34
	assert_backup_rejected 'backup or verification command failed'
	assert_called sqlite-integrity
	assert_not_called sqlite-schema
}

@test "backup: rejects a restored database missing either required TREK table" {
	export BACKUP_SCENARIO=schema-failure
	run_backup
	assert_backup_rejected 'restored database is missing TREK tables'
	assert_called sqlite-schema
}

@test "backup: rejects a SQLite schema query command error" {
	export BACKUP_SCENARIO=schema-error
	run_backup
	assert_failure 35
	assert_backup_rejected 'backup or verification command failed'
	assert_called sqlite-schema
}

@test "backup: rejects nonzero quick_check status even when stdout says ok" {
	# Regression: [[ "$(sqlite3 ...)" == ok ]] discards sqlite3's exit status.
	export BACKUP_SCENARIO=integrity-error-with-output
	run_backup
	assert_failure 34
	assert_backup_rejected 'backup or verification command failed'
	assert_called sqlite-integrity
	assert_not_called sqlite-schema
}

@test "backup: rejects nonzero schema query status even when stdout says 2" {
	export BACKUP_SCENARIO=schema-error-with-output
	run_backup
	assert_failure 35
	assert_backup_rejected 'backup or verification command failed'
	assert_called sqlite-schema
}

@test "backup: rejects multiple new encrypted dumps" {
	export BACKUP_SCENARIO=multiple-dumps
	run_backup
	assert_backup_rejected 'expected exactly one new encrypted dump and one SHA1 sidecar'
	assert_not_called sha1sum
}

@test "backup: rejects multiple new SHA1 sidecars" {
	export BACKUP_SCENARIO=multiple-sidecars
	run_backup
	assert_backup_rejected 'expected exactly one new encrypted dump and one SHA1 sidecar'
	assert_not_called sha1sum
}

@test "backup: rejects multiple complete new output pairs" {
	export BACKUP_SCENARIO=multiple-pairs
	run_backup
	assert_backup_rejected 'expected exactly one new encrypted dump and one SHA1 sidecar'
	assert_not_called sha1sum
}

@test "backup: rejects an unencrypted SQLite output alongside a valid pair" {
	export BACKUP_SCENARIO=plaintext
	run_backup
	assert_backup_rejected 'unexpected output files; inspect for incomplete or unencrypted backups'
	assert_not_called sha1sum
}

@test "backup: rejects a compressed but unencrypted output alongside a valid pair" {
	export BACKUP_SCENARIO=compressed-plaintext
	run_backup
	assert_backup_rejected 'unexpected output files; inspect for incomplete or unencrypted backups'
	assert_not_called sha1sum
}

@test "backup: rejects any unexpected new file alongside the encrypted pair" {
	export BACKUP_SCENARIO=unexpected-output
	run_backup
	assert_backup_rejected 'unexpected output files; inspect for incomplete or unencrypted backups'
	assert_not_called sha1sum
}

@test "backup: rejects an unset encryption passphrase before invoking upstream" {
	unset DEFAULT_ENCRYPT_PASSPHRASE
	run_backup
	assert_backup_rejected 'a populated encryption passphrase is required'
	assert_not_called backup01-now
	assert_not_called touch
}

@test "backup: rejects an empty encryption passphrase before invoking upstream" {
	export DEFAULT_ENCRYPT_PASSPHRASE=''
	run_backup
	assert_backup_rejected 'a populated encryption passphrase is required'
	assert_not_called backup01-now
}

@test "backup: rejects the GENERATE encryption placeholder" {
	export DEFAULT_ENCRYPT_PASSPHRASE=GENERATE
	run_backup
	assert_backup_rejected 'a populated encryption passphrase is required'
	assert_not_called backup01-now
}

@test "backup: rejects the CHANGE_ME encryption placeholder" {
	export DEFAULT_ENCRYPT_PASSPHRASE=CHANGE_ME
	run_backup
	assert_backup_rejected 'a populated encryption passphrase is required'
	assert_not_called backup01-now
}
