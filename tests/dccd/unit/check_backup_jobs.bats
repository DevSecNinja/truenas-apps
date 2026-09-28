#!/usr/bin/env bats
# Unit tests for check_backup_jobs()
# Command/completion evidence only; archive consistency still requires restore testing.

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  common_setup

  SUDO=""
  BACKUP_MAX_AGE_HOURS=48
  WAIT_TIMEOUT=120
  LOG_TIMESTAMP="test"
  BACKUP01_SUCCESS='Backup 01 routines finish time: 2026-09-06 19:00:00 UTC with exit code 0'
  BACKUP02_SUCCESS='Backup 02 routines finish time: 2026-09-06 19:00:00 UTC with exit code 0'
}

teardown() {
  common_teardown
}

mock_backup_container() {
  local inspect_output="$1"
  local inspect_exit="${2:-0}"
  local logs_output="${3:-Backup 01 routines finish time: 2026-09-06 19:00:00 UTC with exit code 0}"
  local logs_exit="${4:-0}"
  local expected_jobs="${5:-}"
  local logs_literal
  # Keep quoted diagnostic payloads and ANSI bytes intact in the generated mock.
  printf -v logs_literal '%q' "${logs_output}"

  cat >"${MOCK_BIN}/docker" <<MOCK
#!/bin/bash
printf '%s\n' "\$*" >>"${MOCK_LOG}/docker.calls"
case "\$1" in
ps)
    printf 'container-1\tapp-db-backup-1\tapp-db-backup\t%s\n' '${expected_jobs}'
    ;;
inspect)
    printf '%s\n' '${inspect_output}'
    exit ${inspect_exit}
    ;;
logs)
    printf '%s\n' ${logs_literal}
    exit ${logs_exit}
    ;;
esac
MOCK
  chmod +x "${MOCK_BIN}/docker"
}

mock_retained_backup_logs() {
  local expected_jobs="${1:-}"
  local current_logs="${2:-Backup 01 routines started but did not report completion}"

  cat >"${MOCK_BIN}/docker" <<MOCK
#!/bin/bash
printf '%s\n' "\$*" >>"${MOCK_LOG}/docker.calls"
case "\$1" in
ps)
    printf 'container-1\tapp-db-backup-1\tapp-db-backup\t%s\n' '${expected_jobs}'
    ;;
inspect)
    printf 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z\n'
    ;;
logs)
    if [ "\$*" = "logs --since 2026-09-06T18:59:00Z container-1" ]; then
        printf '%s\n' '${current_logs}'
    else
        printf 'Backup 01 routines finish time: 2026-09-05 19:00:00 UTC with exit code 0\n'
        printf 'Backup 02 routines finish time: 2026-09-05 19:00:00 UTC with exit code 0\n'
    fi
    ;;
esac
MOCK
  chmod +x "${MOCK_BIN}/docker"
}

mock_fixed_date() {
  local now_epoch="$1"
  local finished_epoch="${2:-$1}"

  cat >"${MOCK_BIN}/date" <<MOCK
#!/bin/bash
printf '%s\n' "\$*" >>"${MOCK_LOG}/date.calls"
case "\$1" in
+%s)
    printf '%s\n' '${now_epoch}'
    ;;
--date=*)
    printf '%s\n' '${finished_epoch}'
    ;;
*)
    exit 1
    ;;
esac
MOCK
  chmod +x "${MOCK_BIN}/date"
}

@test "check_backup_jobs: accepts a recent legacy single-job backup without an expected-job label" {
  mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z'
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_success
  assert_output --partial "app-db-backup: successful backup confirmed in logs (1h ago)"
  assert_output --partial "All 1 database backup job(s) completed successfully within 48 hours"
  assert_mock_called_with "docker" "inspect --format"
  assert_mock_called_with "docker" "logs --since 2026-09-06T18:59:00Z container-1"
}

@test "check_backup_jobs: fails a recent exited-zero backup with no success marker" {
  mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 \
    'Backup 01 routines started but did not report completion'
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_failure
  assert_output --partial "app-db-backup-1: no successful backup completion found in logs from the last 48 hours"
  assert_output --partial "1/1 database backup job(s) failed the freshness check"
  assert_mock_called_with "docker" "logs --since 2026-09-06T18:59:00Z container-1"
}

@test "check_backup_jobs: does not accept a retained success marker from an older execution" {
  mock_retained_backup_logs
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_failure
  assert_output --partial "app-db-backup-1: no successful backup completion found in logs from the last 48 hours"
  assert_mock_called_with "docker" "logs --since 2026-09-06T18:59:00Z container-1"
}

@test "check_backup_jobs: does not accept an explicit backup exit code 1 marker" {
  mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 \
    'Backup 01 routines finish time: 2026-09-06 19:00:00 UTC with exit code 1'
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_failure
  assert_output --partial "app-db-backup-1: backup routine 01 reported exit code 1"
  assert_output --partial "1/1 database backup job(s) failed the freshness check"
  refute_output --partial "successful backup confirmed"
  assert_mock_called_with "docker" "logs --since 2026-09-06T18:59:00Z container-1"
}

@test "check_backup_jobs: a later success cannot mask a failed job in an exited-zero container" {
  local expected_jobs
  local logs=$'Backup 01 routines finish time: 2026-09-06 19:00:00 UTC with exit code 23\n'
  logs+="${BACKUP02_SUCCESS}"
  mock_fixed_date 1000000 996400

  for expected_jobs in '' '01,02'; do
    mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${logs}" 0 "${expected_jobs}"

    run check_backup_jobs

    assert_failure
    assert_output --partial "app-db-backup-1: backup routine 01 reported exit code 23"
    assert_output --partial "1/1 database backup job(s) failed the freshness check"
    refute_output --partial "successful backup confirmed"
    assert_mock_called_with "docker" "logs --since 2026-09-06T18:59:00Z container-1"
  done
}

@test "check_backup_jobs: an earlier success cannot mask a later failed job in an exited-zero container" {
  local expected_jobs
  local logs="${BACKUP01_SUCCESS}"$'\nBackup 02 routines finish time: 2026-09-06 19:00:00 UTC with exit code 47'
  mock_fixed_date 1000000 996400

  for expected_jobs in '' '01,02'; do
    mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${logs}" 0 "${expected_jobs}"

    run check_backup_jobs

    assert_failure
    assert_output --partial "app-db-backup-1: backup routine 02 reported exit code 47"
    assert_output --partial "1/1 database backup job(s) failed the freshness check"
    refute_output --partial "successful backup confirmed"
    assert_mock_called_with "docker" "logs --since 2026-09-06T18:59:00Z container-1"
  done
}

@test "check_backup_jobs: rejects negative job status even alongside a successful completion" {
  local code logs
  mock_fixed_date 1000000 996400

  for code in -1 -143; do
    logs="${BACKUP01_SUCCESS}"$'\n'"Backup 02 routines finish time: 2026-09-06 19:00:00 UTC with exit code ${code}"
    mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${logs}"

    run check_backup_jobs

    assert_failure
    assert_output --partial "app-db-backup-1: backup routine 02 reported exit code ${code}"
    assert_output --partial "1/1 database backup job(s) failed the freshness check"
    refute_output --partial "successful backup confirmed"
  done
}

@test "check_backup_jobs: rejects malformed completion status even alongside a successful completion" {
  local code logs
  mock_fixed_date 1000000 996400

  for code in '' unknown 0oops 0.5; do
    logs="Backup 01 routines finish time: 2026-09-06 19:00:00 UTC with exit code ${code}"$'\n'"${BACKUP02_SUCCESS}"
    mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${logs}"

    run check_backup_jobs

    assert_failure
    assert_output --partial "app-db-backup-1: malformed backup completion record"
    assert_output --partial "1/1 database backup job(s) failed the freshness check"
    refute_output --partial "successful backup confirmed"
  done
}

@test "check_backup_jobs: rejects a completion record missing its exit-code field despite another success" {
  local logs="${BACKUP01_SUCCESS}"$'\nBackup 02 routines finish time: 2026-09-06 19:00:00 UTC'
  mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${logs}" 0 '01,02'
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_failure
  assert_output --partial "app-db-backup-1: malformed backup completion record"
  assert_output --partial "1/1 database backup job(s) failed the freshness check"
  refute_output --partial "successful backup confirmed"
}

@test "check_backup_jobs: a dump-error diagnostic overrides all-zero completion evidence" {
  local expected_jobs logs
  local diagnostic="DB Backup of 'synthetic_database' reported errors"
  local completions="${BACKUP01_SUCCESS}"$'\n'"${BACKUP02_SUCCESS}"
  mock_fixed_date 1000000 996400

  for expected_jobs in '' '01,02'; do
    for logs in "${diagnostic}"$'\n'"${completions}" "${completions}"$'\n'"${diagnostic}"; do
      mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${logs}" 0 "${expected_jobs}"

      run check_backup_jobs

      assert_failure
      assert_output --partial "app-db-backup-1: backup reported a dump or output-move error"
      assert_output --partial "1/1 database backup job(s) failed the freshness check"
      refute_output --partial "malformed backup completion record"
      refute_output --partial "successful backup confirmed"
      assert_mock_called_with "docker" "logs --since 2026-09-06T18:59:00Z container-1"
    done
  done
}

@test "check_backup_jobs: a prefixed output-move error overrides all-zero completion evidence" {
  local expected_jobs logs
  local diagnostic=$'2026-09-06T19:00:00Z stderr F \033[31m'
  diagnostic+="Moving of backup 'synthetic_archive.sql.zst' reported errors"
  diagnostic+=$'\033[0m'
  local completions="${BACKUP01_SUCCESS}"$'\033[0m\n'"${BACKUP02_SUCCESS}"$'\033[0m'
  mock_fixed_date 1000000 996400

  for expected_jobs in '' '01,02'; do
    for logs in "${diagnostic}"$'\n'"${completions}" "${completions}"$'\n'"${diagnostic}"; do
      mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${logs}" 0 "${expected_jobs}"

      run check_backup_jobs

      assert_failure
      assert_output --partial "app-db-backup-1: backup reported a dump or output-move error"
      assert_output --partial "1/1 database backup job(s) failed the freshness check"
      refute_output --partial "malformed backup completion record"
      refute_output --partial "successful backup confirmed"
      assert_mock_called_with "docker" "logs --since 2026-09-06T18:59:00Z container-1"
    done
  done
}

@test "check_backup_jobs: accepts all-zero completion evidence with ANSI reset suffixes and no operation errors" {
  local logs="${BACKUP01_SUCCESS}"$'\033[0m\n'"${BACKUP02_SUCCESS}"$'\033[0m'
  mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${logs}" 0 '01,02'
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_success
  assert_output --partial "app-db-backup: successful backup confirmed in logs (1h ago)"
  assert_output --partial "All 1 database backup job(s) completed successfully within 48 hours"
  refute_output --partial "malformed backup completion record"
  refute_output --partial "backup reported a dump or output-move error"
}

@test "check_backup_jobs: accepts one completion per labelled job using only label and state metadata" {
  local logs="${BACKUP01_SUCCESS}"$'\n'"${BACKUP02_SUCCESS}"
  mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${logs}" 0 '01,02'
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_success
  assert_output --partial "app-db-backup: successful backup confirmed in logs (1h ago)"
  assert_output --partial "All 1 database backup job(s) completed successfully within 48 hours"

  # Assert the complete call list: no full inspect or environment/secret lookup.
  run get_mock_call_args "docker"
  assert_success
  assert_equal "${#lines[@]}" 3
  assert_line --index 0 'ps -a --filter label=com.docker.compose.service --format {{.ID}}\t{{.Names}}\t{{.Label "com.docker.compose.service"}}\t{{.Label "dccd.backup-jobs"}}'
  assert_line --index 1 'inspect --format {{.State.Status}}|{{.State.ExitCode}}|{{.State.StartedAt}}|{{.State.FinishedAt}} container-1'
  assert_line --index 2 'logs --since 2026-09-06T18:59:00Z container-1'
}

@test "check_backup_jobs: matches labelled job IDs independently of completion order" {
  local logs="${BACKUP02_SUCCESS}"$'\n'"${BACKUP01_SUCCESS}"
  mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${logs}" 0 '01,02'
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_success
  assert_output --partial "app-db-backup: successful backup confirmed in logs (1h ago)"
  assert_output --partial "All 1 database backup job(s) completed successfully within 48 hours"
}

@test "check_backup_jobs: fails when labelled job 01 has no completion despite job 02 succeeding" {
  mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${BACKUP02_SUCCESS}" 0 '01,02'
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_failure
  assert_output --partial "app-db-backup-1: expected one successful completion for backup routine 01, found 0"
  assert_output --partial "1/1 database backup job(s) failed the freshness check"
  refute_output --partial "successful backup confirmed"
}

@test "check_backup_jobs: fails when labelled job 02 has no completion despite job 01 succeeding" {
  mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${BACKUP01_SUCCESS}" 0 '01,02'
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_failure
  assert_output --partial "app-db-backup-1: expected one successful completion for backup routine 02, found 0"
  assert_output --partial "1/1 database backup job(s) failed the freshness check"
  refute_output --partial "successful backup confirmed"
}

@test "check_backup_jobs: rejects duplicate expected job IDs even when both jobs completed" {
  local logs="${BACKUP01_SUCCESS}"$'\n'"${BACKUP02_SUCCESS}"
  mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${logs}" 0 '01,01,02'
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_failure
  assert_output --partial "app-db-backup-1: duplicate job 01 in dccd.backup-jobs"
  assert_output --partial "1/1 database backup job(s) failed the freshness check"
  refute_output --partial "successful backup confirmed"
}

@test "check_backup_jobs: rejects invalid expected-job labels despite successful completions" {
  local expected_jobs
  local logs="${BACKUP01_SUCCESS}"$'\n'"${BACKUP02_SUCCESS}"
  mock_fixed_date 1000000 996400

  for expected_jobs in '01,two' ',01,02' '01,02,' '01,,02' '01, 02' '-01,02' '01.0,02' '01;02'; do
    mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${logs}" 0 "${expected_jobs}"

    run check_backup_jobs

    assert_failure
    assert_output --partial "app-db-backup-1: invalid dccd.backup-jobs label"
    assert_output --partial "1/1 database backup job(s) failed the freshness check"
    refute_output --partial "successful backup confirmed"
  done
}

@test "check_backup_jobs: rejects duplicate completion of either labelled job even when neither is missing" {
  local job logs
  mock_fixed_date 1000000 996400

  for job in 01 02; do
    logs="${BACKUP01_SUCCESS}"$'\n'"${BACKUP02_SUCCESS}"$'\n'
    logs+="Backup ${job} routines finish time: 2026-09-06 19:00:00 UTC with exit code 0"
    mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${logs}" 0 '01,02'

    run check_backup_jobs

    assert_failure
    assert_output --partial "app-db-backup-1: expected one successful completion for backup routine ${job}, found 2"
    assert_output --partial "1/1 database backup job(s) failed the freshness check"
    refute_output --partial "successful backup confirmed"
  done
}

@test "check_backup_jobs: preserves at-least-one-success legacy behavior without expected-job counts" {
  local logs="${BACKUP01_SUCCESS}"$'\n'"${BACKUP01_SUCCESS}"
  mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 "${logs}"
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_success
  assert_output --partial "app-db-backup: successful backup confirmed in logs (1h ago)"
  assert_output --partial "All 1 database backup job(s) completed successfully within 48 hours"
}

@test "check_backup_jobs: retained older completions cannot satisfy a missing labelled job in the current run" {
  mock_retained_backup_logs '01,02' "${BACKUP01_SUCCESS}"
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_failure
  assert_output --partial "app-db-backup-1: expected one successful completion for backup routine 02, found 0"
  assert_output --partial "1/1 database backup job(s) failed the freshness check"
  refute_output --partial "successful backup confirmed"
  assert_mock_called_with "docker" "logs --since 2026-09-06T18:59:00Z container-1"
}

@test "check_backup_jobs: fails when recent backup logs cannot be read" {
  mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 'daemon unavailable' 1
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_failure
  assert_output --partial "app-db-backup-1: unable to read backup logs"
  assert_output --partial "1/1 database backup job(s) failed the freshness check"
  assert_mock_called_with "docker" "logs --since 2026-09-06T18:59:00Z container-1"
}

@test "check_backup_jobs: accepts a prefixed production-style success marker" {
  mock_backup_container 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z' 0 \
    '2026-09-06T19:00:01.123456789Z stdout F Backup 01 routines finish time: 2026-09-06 19:00:00 UTC with exit code 0'
  mock_fixed_date 1000000 996400

  run check_backup_jobs

  assert_success
  assert_output --partial "app-db-backup: successful backup confirmed in logs (1h ago)"
  assert_mock_called_with "docker" "logs --since 2026-09-06T18:59:00Z container-1"
}

@test "check_backup_jobs: fails a successful backup older than 48 hours" {
  mock_backup_container 'exited|0|2026-09-04T18:59:00Z|2026-09-04T19:00:00Z'
  mock_fixed_date 1000000 827199

  run check_backup_jobs

  assert_failure
  assert_output --partial "latest successful backup is older than 48 hours"
  assert_output --partial "1/1 database backup job(s) failed the freshness check"
}

@test "check_backup_jobs: accepts a backup exactly 48 hours old" {
  mock_backup_container 'exited|0|2026-09-04T19:59:00Z|2026-09-04T20:00:00Z'
  mock_fixed_date 1000000 827200

  run check_backup_jobs

  assert_success
  assert_output --partial "successful backup confirmed in logs (48h ago)"
  refute_output --partial "older than 48 hours"
  assert_mock_called_with "docker" "logs --since 2026-09-04T19:59:00Z container-1"
}

@test "check_backup_jobs: fails an exited backup with a non-zero status" {
  mock_backup_container 'exited|2|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z'
  mock_fixed_date 1000000

  run check_backup_jobs

  assert_failure
  assert_output --partial "app-db-backup-1: backup failed (state=exited, exit=2)"
  assert_output --partial "1/1 database backup job(s) failed the freshness check"
}

@test "check_backup_jobs: succeeds with a warning when no backup containers match" {
  create_mock "docker" 0 ""

  run check_backup_jobs

  assert_success
  assert_output --partial "No database backup containers found"
  refute_output --partial "Backup Job Check"
}

@test "check_backup_jobs: times out an active backup without a real delay" {
  WAIT_TIMEOUT=4
  cat >"${MOCK_BIN}/docker" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >>"${MOCK_LOG}/docker.calls"
case "$1" in
ps)
    printf 'container-1\tapp-db-backup-1\tapp-db-backup\n'
    ;;
inspect)
    printf 'running|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z\n'
    ;;
esac
MOCK
  chmod +x "${MOCK_BIN}/docker"

  cat >"${MOCK_BIN}/date" <<'MOCK'
#!/bin/bash
counter_file="${MOCK_LOG}/date.counter"
count=0
if [ -f "${counter_file}" ]; then
    count=$(<"${counter_file}")
fi
count=$((count + 1))
printf '%s\n' "${count}" >"${counter_file}"
case "${count}" in
1) printf '100\n' ;;
2) printf '102\n' ;;
*) printf '104\n' ;;
esac
MOCK
  chmod +x "${MOCK_BIN}/date"
  create_mock "sleep" 0 ""

  run check_backup_jobs

  assert_failure
  assert_output --partial "backup did not finish within 4s"
  assert_mock_called_with "sleep" "2"
  run get_mock_call_count "docker"
  assert_success
  assert_output "3"
}

@test "check_backup_jobs: fails when a backup container cannot be inspected" {
  mock_backup_container '' 1
  mock_fixed_date 1000000

  run check_backup_jobs

  assert_failure
  assert_output --partial "app-db-backup-1: unable to inspect backup container"
  assert_output --partial "1/1 database backup job(s) failed the freshness check"
}

@test "check_backup_jobs: fails when Docker container discovery fails" {
  create_mock "docker" 1 "daemon unavailable"

  set -o pipefail
  run check_backup_jobs
  set +o pipefail

  assert_failure
  assert_output --partial "Unable to discover database backup containers"
}
