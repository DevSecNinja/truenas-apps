#!/usr/bin/env bats
# Unit tests for check_backup_jobs()

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  common_setup

  SUDO=""
  BACKUP_MAX_AGE_HOURS=48
  WAIT_TIMEOUT=120
  LOG_TIMESTAMP="test"
}

teardown() {
  common_teardown
}

mock_backup_container() {
  local inspect_output="$1"
  local inspect_exit="${2:-0}"
  local logs_output="${3:-Backup 01 routines finish time: 2026-09-06 19:00:00 UTC with exit code 0}"
  local logs_exit="${4:-0}"

  cat >"${MOCK_BIN}/docker" <<MOCK
#!/bin/bash
printf '%s\n' "\$*" >>"${MOCK_LOG}/docker.calls"
case "\$1" in
ps)
    printf 'container-1\tapp-db-backup-1\tapp-db-backup\n'
    ;;
inspect)
    printf '%s\n' '${inspect_output}'
    exit ${inspect_exit}
    ;;
logs)
    printf '%s\n' '${logs_output}'
    exit ${logs_exit}
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

@test "check_backup_jobs: accepts a recent exited-zero backup" {
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
  cat >"${MOCK_BIN}/docker" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >>"${MOCK_LOG}/docker.calls"
case "$1" in
ps)
    printf 'container-1\tapp-db-backup-1\tapp-db-backup\n'
    ;;
inspect)
    printf 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z\n'
    ;;
logs)
    if [ "$*" = "logs --since 2026-09-06T18:59:00Z container-1" ]; then
        printf 'Backup 01 routines started but did not report completion\n'
    else
        printf 'Backup 01 routines finish time: 2026-09-05 19:00:00 UTC with exit code 0\n'
    fi
    ;;
esac
MOCK
  chmod +x "${MOCK_BIN}/docker"
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
  assert_output --partial "app-db-backup-1: no successful backup completion found in logs from the last 48 hours"
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
