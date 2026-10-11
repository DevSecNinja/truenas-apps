#!/usr/bin/env bats
# Offline command-level regressions, NOT host ZFS or application restore tests.
load '../helpers/diagnostics'
load '../helpers/recovery'

setup_file() {
  recovery_require_tools
}

setup() {
  recovery_setup
}

teardown() {
  common_teardown
}

@test "recovery_main: stops the whole target project before snapshot and deploy, retaining the recovery point" {
  run_recovery widget
  assert_success
  assert_output --partial "widget recovered; scheduled deployments are no longer paused"
  assert_file_not_exists "${BASE_DIR}/.dccd-maintenance"
  assert_file_exists "${MOCK_LOG}/snapshot-name"
  local snapshot
  snapshot="$(<"${MOCK_LOG}/snapshot-name")"
  run cat "${MOCK_LOG}/events"
  assert_success
  assert_output "$(printf 'stop live-web\nstop live-retired\nsnapshot %s\nsync\npull\ndeploy\ncomplete %s' "${snapshot}" "${snapshot}")"
  assert_mock_called_with zfs 'snapshot -r -o org.truenas-apps:recovery-app=widget -o org.truenas-apps:recovery-status=pending -o org.truenas-apps:recovery-revision=revision-old'
  assert_mock_called_with zfs '"reference":"registry.invalid/old:v1","id":"sha256:old"'
  run get_mock_call_args dccd.sh
  assert_success
  assert_output --partial ' -t -f -a widget -w 900 -D'
  assert_output --partial ' -t -f -a widget -w 900 -n -B'
  assert_recovery_event_absent '^destroy '
}

@test "recovery_main: sync failure retains the pre-sync snapshot and maintenance without deploying" {
  export RECOVERY_FAIL_AT=sync
  run_recovery widget
  assert_failure 41
  assert_output --partial "Recovery incomplete"
  assert_recovery_paused
  assert_file_exists "${MOCK_LOG}/snapshot-name"
  assert_recovery_event_absent '^deploy$'
}

@test "recovery_main: image pull failure retains the snapshot and cannot deploy" {
  export RECOVERY_FAIL_AT=pull
  run_recovery widget
  assert_failure 42
  assert_recovery_paused
  assert_file_exists "${MOCK_LOG}/snapshot-name"
  assert_recovery_event_absent '^deploy$'
  assert_mock_called_with docker 'pull'
}

@test "recovery_wait_backups: a backup that stays active times out before any project container is stopped" {
  export RECOVERY_BUSY_BACKUP=1 RECOVERY_WAIT_TIMEOUT=1
  run_recovery widget
  assert_failure
  assert_output --partial "Backup still active: widget-db-backup"
  assert_recovery_paused
  assert_recovery_not_stopped
  assert_mock_called_with docker 'inspect --format {{.State.Status}} live-backup'
}

@test "recovery_main: snapshot failure prevents deployment and preserves the maintenance marker" {
  export RECOVERY_FAIL_AT=snapshot
  run_recovery widget
  assert_failure 43
  assert_recovery_paused
  assert_recovery_event_absent '^deploy$'
  assert_file_not_exists "${MOCK_LOG}/snapshot-name"
  assert_mock_called_with docker 'stop --time 60 live-retired'
}

@test "recovery_main: nonzero deployment keeps both snapshot and maintenance marker" {
  export RECOVERY_FAIL_AT=deploy
  run_recovery widget
  assert_failure 44
  assert_output --partial "no automatic rollback or snapshot deletion"
  assert_recovery_paused
  assert_file_exists "${MOCK_LOG}/snapshot-name"
}

@test "recovery_main: retry after a failed deployment reuses the snapshot and target without syncing again" {
  export RECOVERY_FAIL_AT=deploy
  run_recovery widget
  assert_failure 44
  local snapshot
  snapshot="$(<"${MOCK_LOG}/snapshot-name")"
  unset RECOVERY_FAIL_AT

  run_recovery widget
  assert_success
  assert_output --partial "Reusing ${snapshot}"
  assert_file_not_exists "${BASE_DIR}/.dccd-maintenance"
  run cat "${MOCK_LOG}/snapshot-name"
  assert_success
  assert_output "${snapshot}"
  run grep -E '^(sync|pull|snapshot |deploy)' "${MOCK_LOG}/events"
  assert_success
  assert_output "$(printf 'snapshot %s\nsync\npull\ndeploy\npull\ndeploy' "${snapshot}")"
  assert_recovery_event_absent '^destroy '
}

@test "recovery_main: retry refuses a snapshot from another owner or Git revision" {
  recovery_seed_snapshot
  export RECOVERY_STORED_OWNER=other
  run_recovery widget
  assert_failure
  assert_output --partial "Existing snapshot has the wrong owner"
  unset RECOVERY_STORED_OWNER
  export RECOVERY_STORED_REVISION=old-revision
  run_recovery widget
  assert_failure
  assert_output --partial "Repository changed since the deployment attempt"
  assert_recovery_not_stopped
  assert_recovery_paused
}

@test "recovery_main: retry after sync failure preserves the original snapshot and can finish syncing" {
  export RECOVERY_FAIL_AT=sync
  run_recovery widget
  assert_failure 41
  local snapshot
  snapshot="$(<"${MOCK_LOG}/snapshot-name")"
  unset RECOVERY_FAIL_AT
  run_recovery widget
  assert_success
  assert_file_not_exists "${BASE_DIR}/.dccd-maintenance"
  run grep -E '^(snapshot |sync$)' "${MOCK_LOG}/events"
  assert_success
  assert_output "$(printf 'snapshot %s\nsync\nsync' "${snapshot}")"
}

@test "recovery_main: retry refuses changed target images before another deployment" {
  export RECOVERY_FAIL_AT=deploy
  run_recovery widget
  assert_failure 44
  unset RECOVERY_FAIL_AT
  export RECOVERY_IMAGE=registry.invalid/widget:v3
  run_recovery widget
  assert_failure
  assert_output --partial "Target images changed since the deployment attempt"
  assert_recovery_paused
  run grep -c '^deploy$' "${MOCK_LOG}/events"
  assert_success
  assert_output 1
}

@test "recovery_main: an unmounted dataset cannot be mistaken for the live app filesystem" {
  export RECOVERY_MOUNTED=no
  run_recovery widget
  assert_failure
  assert_output --partial "No dedicated ZFS dataset is mounted"
  assert_mock_not_called git
  assert_mock_not_called docker
  assert_recovery_not_stopped
}

@test "recovery_main: wrong app and malformed maintenance markers fail closed" {
  local marker
  for marker in $'other\n'"${TEST_SNAPSHOT}" $'widget\nbogus' $'widget\n'"${TEST_SNAPSHOT}"$'\nextra'; do
    printf '%s\n' "${marker}" >"${BASE_DIR}/.dccd-maintenance"
    run_recovery widget
    assert_failure
    assert_recovery_not_stopped
    assert_mock_not_called git
    run cat "${BASE_DIR}/.dccd-maintenance"
    assert_success
    assert_output "${marker}"
  done
}

@test "recovery_main: cleanup explicitly destroys only the owned completed snapshot recursively" {
  recovery_seed_snapshot
  rm "${BASE_DIR}/.dccd-maintenance"
  export RECOVERY_STORED_STATUS=complete
  run_recovery --cleanup widget "${TEST_SNAPSHOT}"
  assert_success
  assert_output --partial "Deleted recovery snapshot ${TEST_SNAPSHOT}"
  assert_file_not_exists "${MOCK_LOG}/snapshot-name"
  assert_mock_called_with zfs "destroy -r ${TEST_SNAPSHOT}"
  assert_mock_not_called docker
  assert_mock_not_called git
  run cat "${MOCK_LOG}/events"
  assert_success
  assert_output "destroy ${TEST_SNAPSHOT}"
}

@test "recovery_main: cleanup rejects arbitrary, other-app, pending, failed, and wrongly owned snapshots" {
  recovery_seed_snapshot
  rm "${BASE_DIR}/.dccd-maintenance"
  export RECOVERY_STORED_STATUS=complete
  local snapshot state
  for snapshot in 'tank/apps/widget@manual' 'tank/apps/other@pre-dccd-20261010T210000Z-42' 'tank/apps/widget@pre-dccd-oops'; do
    run_recovery --cleanup widget "${snapshot}"
    assert_failure
    assert_output --partial "Snapshot is not a recovery snapshot of this app"
  done
  for state in pending failed; do
    export RECOVERY_STORED_STATUS="${state}"
    run_recovery --cleanup widget "${TEST_SNAPSHOT}"
    assert_failure
    assert_output --partial "Snapshot is not marked as a completed recovery for this app"
  done
  export RECOVERY_STORED_STATUS=complete RECOVERY_STORED_OWNER=other
  run_recovery --cleanup widget "${TEST_SNAPSHOT}"
  assert_failure
  assert_output --partial "Snapshot is not marked as a completed recovery for this app"
  assert_file_exists "${MOCK_LOG}/snapshot-name"
  assert_recovery_event_absent '^destroy '
}

@test "recovery_main: cleanup refuses even a completed snapshot while maintenance is active" {
  recovery_seed_snapshot
  export RECOVERY_STORED_STATUS=complete
  run_recovery --cleanup widget "${TEST_SNAPSHOT}"
  assert_failure
  assert_output --partial "Finish the pending recovery before cleanup"
  assert_recovery_paused
}

@test "recovery_main: external writable mounts in either desired or existing containers are rejected before stop" {
  export RECOVERY_MOUNT_SOURCE="${BASE_DIR}/services/other/data"
  run_recovery widget
  assert_failure
  assert_output --partial "Writable mount is outside the app dataset"
  assert_recovery_not_stopped
  unset RECOVERY_MOUNT_SOURCE
  export RECOVERY_LIVE_MOUNT="${BASE_DIR}/services/other/data"
  run_recovery widget
  assert_failure
  assert_output --partial "Writable mount is outside the app dataset"
  assert_recovery_not_stopped
}

@test "recovery_main: an unrelated dataset nested under the app is rejected before sync or stop" {
  export RECOVERY_NESTED_DATASET=1
  run_recovery widget
  assert_failure
  assert_output --partial "is not a child of tank/apps/widget"
  assert_mock_not_called git
  assert_mock_not_called docker
  assert_recovery_not_stopped
}

@test "recovery_main: volumes, builds, replicas, and active profiles require an explicit app-specific plan" {
  export RECOVERY_MOUNT_TYPE=volume
  run_recovery widget
  assert_failure
  assert_output --partial "Named/anonymous volumes need an app-specific snapshot plan"
  unset RECOVERY_MOUNT_TYPE
  export RECOVERY_BUILD='{"context":"."}'
  run_recovery widget
  assert_failure
  assert_output --partial "Recovery requires published images and one container per service"
  unset RECOVERY_BUILD
  export RECOVERY_REPLICAS=2
  run_recovery widget
  assert_failure
  assert_output --partial "Recovery requires published images and one container per service"
  unset RECOVERY_REPLICAS
  export COMPOSE_PROFILES=optional
  run_recovery widget
  assert_failure
  assert_output --partial "Profile-specific recovery needs an app-specific plan"
  assert_recovery_not_stopped
}

@test "recovery_check_containers: missing expected backup container cannot complete recovery" {
  export RECOVERY_MISSING_SERVICE=widget-db-backup
  run_recovery widget
  assert_failure
  assert_output --partial "Expected exactly one container for widget-db-backup"
  assert_recovery_paused
}

@test "recovery_check_containers: an old image cannot satisfy the pulled-image check" {
  export RECOVERY_ACTUAL_IMAGE=sha256:old
  run_recovery widget
  assert_failure
  assert_output --partial "web is not using the pulled image"
  assert_recovery_paused
}

@test "recovery_check_containers: a retained container on the correct image ID need not have a new container ID" {
  export RECOVERY_RETAIN_WEB=1
  run_recovery widget
  assert_success
  assert_output --partial "widget recovered"
  assert_file_not_exists "${BASE_DIR}/.dccd-maintenance"
  assert_mock_called_with zfs '"reference":"registry.invalid/old:v1","id":"sha256:target"'
  assert_mock_called_with docker 'image inspect --format {{.Id}} registry.invalid/widget:v2'
}

@test "recovery_check_containers: moving a tag after pull must not redefine the expected image ID" {
  # A different checkout can change Docker's host-global mutable tags.
  export RECOVERY_RETAG_ON_DEPLOY=1
  run_recovery widget
  assert_failure
  assert_file_exists "${MOCK_LOG}/snapshot-name"
  assert_recovery_paused
}

@test "recovery_check_containers: an earlier successful backup cannot satisfy this deployment attempt" {
  export RECOVERY_BACKUP_STARTED=earlier
  run_recovery widget
  assert_failure
  assert_output --partial "widget-db-backup did not run during this recovery attempt"
  assert_recovery_paused
}

@test "recovery_check_containers: unhealthy runtime and failed one-shot containers keep recovery paused" {
  export RECOVERY_HEALTH=unhealthy
  run_recovery widget
  assert_failure
  assert_output --partial "web is not healthy (unhealthy)"
  assert_recovery_paused
  unset RECOVERY_HEALTH
  export RECOVERY_BACKUP_EXIT=23
  run_recovery widget
  assert_failure
  assert_output --partial "widget-db-backup did not complete successfully"
  assert_recovery_paused
}

@test "recovery_check_meilisearch: missing container fails before executing the task query" {
  export RECOVERY_IMAGE=docker.io/getmeili/meilisearch:v1
  export RECOVERY_MISSING_SERVICE=web
  export RECOVERY_MEILI_RESPONSE='{"results":[]}'
  run_recovery widget
  assert_failure
  assert_output --partial "Expected exactly one container for web"
  assert_recovery_event_absent '^meili$'
  assert_file_exists "${MOCK_LOG}/snapshot-name"
  assert_recovery_paused
}

@test "recovery_check_meilisearch: multiple containers fail before executing the task query" {
  export RECOVERY_IMAGE=docker.io/getmeili/meilisearch:v1
  export RECOVERY_DUPLICATE_SERVICE=web
  export RECOVERY_MEILI_RESPONSE='{"results":[]}'
  run_recovery widget
  assert_failure
  assert_output --partial "Expected exactly one container for web"
  assert_recovery_event_absent '^meili$'
  assert_file_exists "${MOCK_LOG}/snapshot-name"
  assert_recovery_paused
}

@test "recovery_check_meilisearch: newest failed or canceled task cannot be hidden by an earlier success" {
  export RECOVERY_IMAGE=docker.io/getmeili/meilisearch:v1
  local state
  for state in failed canceled; do
    export RECOVERY_MEILI_RESPONSE
    RECOVERY_MEILI_RESPONSE="$(jq -cn --arg state "${state}" \
      '{results:[{type:"upgradeDatabase",status:$state},{type:"upgradeDatabase",status:"succeeded"}]}')"
    run_recovery widget
    assert_failure
    assert_output --partial "web: latest migration status=${state}"
    assert_recovery_paused
  done
}

@test "recovery_check_meilisearch: malformed responses cannot clear maintenance" {
  export RECOVERY_IMAGE=docker.io/getmeili/meilisearch:v1
  local response
  for response in 'not-json' '{"results":{}}' '{"results":[{"type":"upgradeDatabase"}]}' \
    '{"results":[{"type":"documentAdditionOrUpdate","status":"succeeded"}]}'; do
    export RECOVERY_MEILI_RESPONSE="${response}"
    run_recovery widget
    assert_failure
    assert_recovery_paused
  done
}

@test "recovery_check_meilisearch: short and digest-pinned Meili references must not bypass failed migration checks" {
  export RECOVERY_MEILI_RESPONSE='{"results":[{"type":"upgradeDatabase","status":"failed"}]}'
  local image
  for image in getmeili/meilisearch:v1 \
    docker.io/getmeili/meilisearch@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; do
    export RECOVERY_IMAGE="${image}"
    recovery_seed_snapshot
    run_recovery widget
    assert_failure
    assert_output --partial "latest migration status=failed"
    assert_recovery_paused
  done
}

@test "recovery_check_meilisearch: retry times out a still-running migration before attempting another deployment" {
  recovery_seed_snapshot
  export RECOVERY_IMAGE=docker.io/getmeili/meilisearch:v1
  export RECOVERY_RUNNING_MEILI=1 RECOVERY_WAIT_TIMEOUT=1
  export RECOVERY_MEILI_RESPONSE='{"results":[{"type":"upgradeDatabase","status":"processing"}]}'
  run_recovery widget
  assert_failure
  assert_output --partial "web: migration timed out; do not interrupt it"
  assert_recovery_paused
  assert_recovery_not_stopped
  assert_mock_not_called dccd.sh
}

@test "recovery_check_meilisearch: no migration and a succeeded latest migration both allow completion" {
  export RECOVERY_IMAGE=docker.io/getmeili/meilisearch:v1
  local response
  for response in '{"results":[]}' '{"results":[{"type":"upgradeDatabase","status":"succeeded"}]}'; do
    recovery_seed_snapshot
    export RECOVERY_MEILI_RESPONSE="${response}"
    run_recovery widget
    assert_success
    assert_output --partial "widget recovered"
    assert_file_not_exists "${BASE_DIR}/.dccd-maintenance"
    assert_file_exists "${MOCK_LOG}/snapshot-name"
  done
}
