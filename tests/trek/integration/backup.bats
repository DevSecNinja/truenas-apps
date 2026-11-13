#!/usr/bin/env bats
# Wrapper integration only; encryption/SQLite semantics are covered by runtime tests.

load '../helpers/common'

setup_file() {
	trek_tree_setup_file
}

setup() {
	trek_backup_setup
}

teardown() {
	local cleanup_status=0
	trek_tree_cleanup || cleanup_status=$?
	trek_teardown
	return "${cleanup_status}"
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
	for stage in dump discovery checksum decrypt decompress integrity schema; do
		assert_dir_exists "${MOCK_LOG}/deadline-${stage}"
	done
	# The strict mock rejects duplicate deadlines and any other command/query.
	assert_called upstream-umask-022
	assert_called verification-umask-077
	assert_file_exists "${BACKUP_ROOT}/sqlite3_travel_current.sqlite3.zst.gpg"
	assert_file_exists "${BACKUP_ROOT}/sqlite3_travel_current.sqlite3.zst.gpg.sha1"
	assert_backup_cleaned
	assert_no_backup_plaintext
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
	assert_output --partial 'ERROR: TREK backup: dump failed (exit 23)'
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
	assert_output --partial 'ERROR: TREK backup: dump failed (exit 124)'
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
	assert_output --partial 'ERROR: TREK backup: checksum failed (exit 31)'
	assert_backup_rejected 'mock SHA1 mismatch'
	assert_not_called gpg
	assert_not_called sqlite3
}

@test "backup: pipefail rejects failed GPG even if downstream ZSTD succeeds" {
	export BACKUP_SCENARIO=gpg-failure
	run_backup
	assert_failure 32
	assert_output --partial 'ERROR: TREK backup: decrypt failed (exit 32)'
	assert_backup_rejected 'mock GPG failure'
	assert_called gpg
	assert_called zstd
	assert_not_called sqlite3
}

@test "backup: rejects ZSTD failure and removes partially restored SQLite and GnuPG state" {
	export BACKUP_SCENARIO=zstd-failure
	run_backup
	assert_failure 33
	assert_output --partial 'ERROR: TREK backup: decompress failed (exit 33)'
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
	assert_output --partial 'ERROR: TREK backup: integrity failed (exit 34)'
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
	assert_output --partial 'ERROR: TREK backup: schema failed (exit 35)'
	assert_backup_rejected 'backup or verification command failed'
	assert_called sqlite-schema
}

@test "backup: rejects nonzero quick_check status even when stdout says ok" {
	# Regression: [[ "$(sqlite3 ...)" == ok ]] discards sqlite3's exit status.
	export BACKUP_SCENARIO=integrity-error-with-output
	run_backup
	assert_failure 34
	assert_output --partial 'ERROR: TREK backup: integrity failed (exit 34)'
	assert_backup_rejected 'backup or verification command failed'
	assert_called sqlite-integrity
	assert_not_called sqlite-schema
}

@test "backup: rejects nonzero schema query status even when stdout says 2" {
	export BACKUP_SCENARIO=schema-error-with-output
	run_backup
	assert_failure 35
	assert_output --partial 'ERROR: TREK backup: schema failed (exit 35)'
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

@test "run_stage: timeout dump stops before discovery" {
	export BACKUP_SCENARIO=timeout-dump
	run_backup
	assert_stage_rejected dump 124
	assert_called backup01-now
	assert_not_called find
	assert_not_called sha1sum
	assert_not_called gpg
	assert_not_called sqlite3
}

@test "run_stage: timeout discovery rejects a valid pair on stdout" {
	export BACKUP_SCENARIO=timeout-discovery
	run_backup
	assert_stage_rejected discovery 124
	assert_called find
	assert_not_called sha1sum
	assert_not_called gpg
	assert_not_called sqlite3
}

@test "run_stage: timeout checksum stops before decryption" {
	export BACKUP_SCENARIO=timeout-checksum
	run_backup
	assert_stage_rejected checksum 124
	assert_called sha1sum
	assert_not_called gpg
	assert_not_called zstd
	assert_not_called sqlite3
}

@test "run_stage: timeout decrypt survives a successful downstream decompressor" {
	export BACKUP_SCENARIO=timeout-decrypt
	run_backup
	assert_stage_rejected decrypt 124
	assert_called gpg
	assert_called zstd
	assert_called zstd-completed
	assert_called verification-umask-077
	assert_not_called sqlite3
}

@test "run_stage: timeout decompress removes partial plaintext and private GnuPG state" {
	export BACKUP_SCENARIO=timeout-decompress
	run_backup
	assert_stage_rejected decompress 124
	assert_called gpg
	assert_called zstd
	assert_called verification-umask-077
	assert_not_called sqlite3
}

@test "run_stage: timeout integrity rejects ok stdout and never queries schema" {
	export BACKUP_SCENARIO=timeout-integrity
	run_backup
	assert_stage_rejected integrity 124
	assert_called sqlite-integrity
	assert_not_called sqlite-schema
	assert_dir_not_exists "${MOCK_LOG}/deadline-schema"
}

@test "run_stage: timeout schema rejects count two after successful integrity" {
	export BACKUP_SCENARIO=timeout-schema
	run_backup
	assert_stage_rejected schema 124
	assert_called sqlite-integrity
	assert_called sqlite-schema
	assert_dir_exists "${MOCK_LOG}/deadline-integrity"
}

@test "run_stage: discovery propagates ordinary failure after partial output" {
	export BACKUP_SCENARIO=discovery-partial-failure
	run_backup
	refute_output --partial 'expected exactly one new encrypted dump'
	assert_stage_rejected discovery 36
	assert_called find
	assert_not_called sha1sum
	assert_not_called gpg
	assert_not_called sqlite3
}

@test "run_stage: discovery propagates ordinary failure even with a complete pair on stdout" {
	export BACKUP_SCENARIO=discovery-pair-failure
	run_backup
	assert_stage_rejected discovery 36
	assert_called find
	assert_not_called sha1sum
	assert_not_called sqlite3
}

@test "run_stage: pipefail preserves rightmost failure and reports both failing stages" {
	export BACKUP_SCENARIO=pipeline-failure
	run_backup
	assert_failure 33
	assert_output --partial 'ERROR: TREK backup: decrypt failed (exit 32)'
	assert_stage_rejected decompress 33
	assert_called gpg
	assert_called zstd
	assert_called verification-umask-077
	assert_not_called sqlite3
}

run_deadline_mock() {
	run env -i PATH="${MOCK_BIN}:${ORIGINAL_PATH}" MOCK_BIN="${MOCK_BIN}" \
		MOCK_LOG="${MOCK_LOG}" WORK_ROOT="${WORK_ROOT}" BACKUP_ROOT="${BACKUP_ROOT}" \
		REAL_TOUCH="${REAL_TOUCH}" TREK_MOCK_CONTEXT=backup BACKUP_SCENARIO=success \
		"${BASH}" "${MOCK_BIN}/timeout" "$@"
}

@test "timeout_mock: rejects altered signal grace duration and extra options" {
	local -a header=()
	local variant
	for variant in signal grace duration foreground missing; do
		case "${variant}" in
		signal) header=(--signal=KILL --kill-after=10s 300s) ;;
		grace) header=(--signal=TERM --kill-after=11s 300s) ;;
		duration) header=(--signal=TERM --kill-after=10s 301s) ;;
		foreground) header=(--foreground --signal=TERM --kill-after=10s 300s) ;;
		missing) header=(--signal=TERM 300s) ;;
		*) return 97 ;;
		esac
		run_deadline_mock "${header[@]}" backup01-now now
		assert_failure 97
		assert_output --partial 'Unexpected TREK mock invocation: timeout'
		assert_not_called backup01-now
	done
}

@test "timeout_mock: rejects unknown commands extra arguments and unapproved SQLite queries" {
	run_deadline_mock --signal=TERM --kill-after=10s 300s sh -c 'exit 0'
	assert_failure 97
	run_deadline_mock --signal=TERM --kill-after=10s 300s backup01-now now extra
	assert_failure 97
	run_deadline_mock --signal=TERM --kill-after=10s 300s sqlite3 \
		"${WORK_ROOT}/trek-backup.synthetic/restored.sqlite3" 'PRAGMA integrity_check;'
	assert_failure 97
	run_deadline_mock --signal=TERM --kill-after=10s 300s sqlite3 \
		"${WORK_ROOT}/trek-backup.synthetic/restored.sqlite3" 'SELECT 2;'
	assert_failure 97
	assert_not_called backup01-now
	assert_not_called sqlite3
}

@test "run_stage: verification timeout regressions reject an isolated prior unbounded implementation" {
	# Reconstruct the prior wrapper: only the dump was bounded. Never edit the
	# working source, and keep the generic ERR trap, pipefail and cleanup intact.
	local prior="${TEST_ROOT}/backup-unbounded.sh" stage
	cp "${TREK_BACKUP}" "${prior}"
	sed -i \
		-e '/^run_stage() {$/,/^}$/d' \
		-e 's/run_stage dump /timeout --signal=TERM --kill-after=10s 300s /' \
		-e 's/run_stage \(discovery\|checksum\|decrypt\|decompress\|integrity\|schema\) //' \
		"${prior}"
	run grep -c run_stage "${prior}"
	assert_failure 1
	assert_output 0
	run grep -c 'timeout --signal=TERM --kill-after=10s 300s backup01-now now' "${prior}"
	assert_success
	assert_output 1

	# Run the actual six new verification tests, not a second weaker assertion.
	# With no deadline calls, injection cannot happen and the old script succeeds.
	run env TREK_TEST_BACKUP="${prior}" "${BASH}" "${BATS_ROOT}/bin/bats" \
		--formatter tap --filter '^run_stage: timeout (discovery|checksum|decrypt|decompress|integrity|schema) ' \
		"${BATS_TEST_FILENAME}"
	assert_failure 1
	assert_line '1..6'
	for stage in discovery checksum decrypt decompress integrity schema; do
		assert_line --regexp "^not ok [0-9]+ run_stage: timeout ${stage} "
	done
	assert_output --partial 'command succeeded, but it was expected to fail'
	refute_output --partial 'Unexpected TREK mock invocation:'
}

@test "run_stage: real timeout sends TERM to the monitored parent and spawned cooperative child" {
	# Real GNU timeout, synthetic find and children only. No runtime/image test.
	export BACKUP_SCENARIO=tree-cooperative
	local started="${SECONDS}" elapsed
	run_backup
	elapsed=$((SECONDS - started))
	assert_stage_rejected discovery 124
	assert test "${elapsed}" -lt 9
	assert_called tree-parent-term
	assert_called tree-child-term
	assert_tree_started_and_stopped
	assert_not_called sha1sum
	assert_not_called gpg
	assert_not_called sqlite3
}

@test "run_stage: real timeout escalates to KILL for a TERM-ignoring parent and spawned child" {
	export BACKUP_SCENARIO=tree-ignoring
	local started="${SECONDS}" elapsed
	run_backup
	elapsed=$((SECONDS - started))
	# GNU timeout itself is killed with the process group during escalation.
	assert_stage_rejected discovery 137
	assert test "${elapsed}" -lt 9
	assert_not_called tree-parent-term
	assert_not_called tree-child-term
	assert_tree_started_and_stopped
	assert_not_called sha1sum
	assert_not_called gpg
	assert_not_called sqlite3
}
