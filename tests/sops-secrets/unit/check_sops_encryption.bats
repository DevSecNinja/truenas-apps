#!/usr/bin/env bats
# Marker-only hook contract: synthetic files, real grep, no SOPS execution.

load '../../libs/bats-support/load'
load '../../libs/bats-assert/load'
load '../../libs/bats-file/load'

setup_file() {
	command -v grep || return 1
}

setup() {
	CHECK_SCRIPT="${BATS_TEST_DIRNAME}/../../../scripts/check-sops-encryption.sh"
	TEST_ROOT="$(mktemp -d "${BATS_TMPDIR}/dccd-test.XXXXXX")"
	MARKED="${TEST_ROOT}/marked.env"
	SPACED="${TEST_ROOT}/second marked.env"
	UNMARKED="${TEST_ROOT}/unmarked file.env"
	assert_file_exists "${CHECK_SCRIPT}"
	printf '%s\n' 'sops_mac=synthetic-marker-only' >"${MARKED}"
	cp -- "${MARKED}" "${SPACED}"
	printf '%s\n' 'NOTE=synthetic-content-must-not-appear' \
		'not_sops_mac=synthetic-not-a-line-prefix' >"${UNMARKED}"
}

teardown() {
	rm -rf -- "${TEST_ROOT}"
}

@test "check_sops_encryption: accepts multiple marked files including a spaced path" {
	assert_file_exists "${MARKED}"
	assert_file_exists "${SPACED}"
	run bash "${CHECK_SCRIPT}" "${MARKED}" "${SPACED}"
	assert_success
	assert_output ""
}

@test "check_sops_encryption: missing line-start marker fails without printing file content" {
	assert_file_exists "${UNMARKED}"
	run bash "${CHECK_SCRIPT}" "${UNMARKED}"
	assert_failure 1
	assert_output "ERROR: ${UNMARKED} is not SOPS-encrypted"
	refute_output --partial 'synthetic-content-must-not-appear'
	refute_output --partial 'synthetic-not-a-line-prefix'
}

@test "check_sops_encryption: a later invalid file fails after valid marked files" {
	run bash "${CHECK_SCRIPT}" "${MARKED}" "${SPACED}" "${UNMARKED}"
	assert_failure 1
	assert_output "ERROR: ${UNMARKED} is not SOPS-encrypted"
	refute_output --partial 'synthetic-content-must-not-appear'
}

@test "check_sops_encryption: absent files and no arguments fail closed" {
	local missing="${TEST_ROOT}/absent file.env"
	assert_file_not_exists "${missing}"
	run bash "${CHECK_SCRIPT}" "${missing}"
	assert_failure 1
	assert_line "ERROR: ${missing} is not SOPS-encrypted"

	run bash "${CHECK_SCRIPT}"
	assert_failure 1
	assert_output 'ERROR: provide at least one encrypted dotenv file'
}
