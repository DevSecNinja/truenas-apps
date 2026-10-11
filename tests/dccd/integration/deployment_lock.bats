#!/usr/bin/env bats
# Real flock concurrency; all dccd external side effects remain PATH-mocked.
load '../helpers/diagnostics'

setup_file() {
  diagnostics_require_helpers
  if [[ "${OSTYPE}" != linux* ]]; then
    skip "Lock inheritance tests require Linux /proc and real flock"
  fi
  command -v flock
}

setup() {
  diagnostics_setup
  unset DCCD_LOCK_FD DCCD_RECOVERY_APP DCCD_TESTING
  create_mock id 0 1000
  LOCK_WORKER="${REPO_ROOT}/tests/dccd/fixtures/deployment-lock-worker.bash"
  LOCK_LIBRARY="${REPO_ROOT}/scripts/lib/deployment-lock.sh"
  LOCK_STATE="${BASE_DIR}/lock-state"
  LOCK_PID=''
  mkdir -p "${LOCK_STATE}" "${BASE_DIR}/other-checkout"
}

teardown() {
  # A failed assertion must not leave a holder running into the next test.
  if [[ -f "${LOCK_STATE}/child.pid" ]]; then
    kill "$(<"${LOCK_STATE}/child.pid")" 2>/dev/null || true
  fi
  if [[ -n "${LOCK_PID}" ]]; then
    kill "${LOCK_PID}" 2>/dev/null || true
    wait "${LOCK_PID}" 2>/dev/null || true
  fi
  common_teardown
}

start_lock_holder() {
  bash "${LOCK_WORKER}" "${BASE_DIR}" "${LOCK_LIBRARY}" "${LOCK_STATE}" "$1" &
  LOCK_PID=$!
  local deadline=$((SECONDS + 5))
  until [[ -f "${LOCK_STATE}/ready" ]]; do
    if ((SECONDS >= deadline)); then
      fail "Lock worker '$1' never signaled readiness"
      return 1
    fi
    sleep 0.02
  done
}

assert_real_lock_held() {
  run flock --exclusive --nonblock "$1/.dccd.lock" true
  assert_failure 1
}

@test "dccd_acquire_lock: excludes another deployment for the same repository and releases on last close" {
  start_lock_holder hold
  assert_real_lock_held "${BASE_DIR}"
  run bash "${LOCK_WORKER}" "${BASE_DIR}" "${LOCK_LIBRARY}" "${LOCK_STATE}" try
  assert_failure 75
  assert_output --partial "Another deployment or recovery holds"

  touch "${LOCK_STATE}/release"
  wait "${LOCK_PID}"
  LOCK_PID=''
  run bash "${LOCK_WORKER}" "${BASE_DIR}" "${LOCK_LIBRARY}" "${LOCK_STATE}" try
  assert_success
  assert_output acquired
}

@test "dccd_acquire_lock: a different checkout is independent of the held repository lock" {
  start_lock_holder hold
  run bash "${LOCK_WORKER}" "${BASE_DIR}/other-checkout" "${LOCK_LIBRARY}" "${LOCK_STATE}" try
  assert_success
  assert_output acquired
  assert_real_lock_held "${BASE_DIR}"
}

@test "dccd_acquire_lock: inherited descriptor is revalidated by inode when switching checkouts" {
  start_lock_holder other-checkout
  assert_real_lock_held "${BASE_DIR}"
  assert_real_lock_held "${BASE_DIR}/other-checkout"
}

@test "dccd_acquire_lock: exec bash preserves both the lock and its inherited descriptor" {
  start_lock_holder reexec
  assert_real_lock_held "${BASE_DIR}"
  run bash "${LOCK_WORKER}" "${BASE_DIR}" "${LOCK_LIBRARY}" "${LOCK_STATE}" try
  assert_failure 75
}

@test "dccd_acquire_lock: borrowed child exit does not unlock its still-running parent" {
  start_lock_holder child-exit
  assert_file_exists "${LOCK_STATE}/child-done"
  assert_real_lock_held "${BASE_DIR}"
}

@test "dccd_acquire_lock: child retains the lock after the original holder exits" {
  start_lock_holder parent-exit
  wait "${LOCK_PID}"
  LOCK_PID=''
  assert_file_exists "${LOCK_STATE}/child.pid"
  assert_real_lock_held "${BASE_DIR}"
  touch "${LOCK_STATE}/release"
  # Do not race the child's final close; bounded polling also detects a leaked FD.
  run flock --exclusive --timeout 3 "${BASE_DIR}/.dccd.lock" true
  assert_success
}

@test "dccd_acquire_lock: refuses symlink lock paths instead of locking an unrelated inode" {
  touch "${BASE_DIR}/unrelated"
  ln -s "${BASE_DIR}/unrelated" "${BASE_DIR}/.dccd.lock"
  run bash "${LOCK_WORKER}" "${BASE_DIR}" "${LOCK_LIBRARY}" "${LOCK_STATE}" try
  assert_failure
  assert_output --partial "Refusing a symlink"
}

@test "dccd_acquire_lock: missing flock fails explicitly without creating a lock file" {
  run bash -c '
    source "$1"
    log_error() { printf "%s\n" "$*" >&2; }
    BASE_DIR="$2"
    PATH=""
    dccd_acquire_lock
  ' lock-test "${LOCK_LIBRARY}" "${BASE_DIR}"
  assert_failure
  assert_output --partial "flock is required"
  assert_file_not_exists "${BASE_DIR}/.dccd.lock"
}

@test "dccd_main: repository-wide lock blocks another app even for decrypt-only mode" {
  start_lock_holder hold
  run bash "${REPO_ROOT}/scripts/dccd.sh" -d "${BASE_DIR}" -D -a other
  assert_failure 75
  assert_output --partial "Another deployment or recovery holds"
  assert_mock_not_called git
  assert_mock_not_called docker
  assert_mock_not_called sudo
}

@test "dccd_check_maintenance: actual main blocks normal deploy, sync/decrypt, and removal before side effects" {
  printf 'widget\ntank/apps/widget@pre-dccd-20261010T210000Z-42\n' >"${BASE_DIR}/.dccd-maintenance"
  local mode
  for mode in deploy decrypt remove; do
    local -a args=(-a other)
    case "${mode}" in
    decrypt) args=(-D -a widget) ;;
    remove) args=(-R widget) ;;
    esac
    run bash "${REPO_ROOT}/scripts/dccd.sh" -d "${BASE_DIR}" "${args[@]}"
    assert_failure 75
    assert_output --partial "Deployments are paused for widget"
    assert_mock_not_called git
    assert_mock_not_called docker
    assert_mock_not_called sudo
  done
}

@test "dccd_check_maintenance: recovery exemption requires the same app filter and never permits removal" {
  printf 'widget\ntank/apps/widget@pre-dccd-20261010T210000Z-42\n' >"${BASE_DIR}/.dccd-maintenance"
  DCCD_RECOVERY_APP=widget
  APP_FILTER=other
  run dccd_check_maintenance
  assert_failure 75
  APP_FILTER=widget
  REMOVE_APP=widget
  run dccd_check_maintenance
  assert_failure 75
  REMOVE_APP=''
  run dccd_check_maintenance
  assert_success
  assert_output ''
}

@test "dccd_main: sourcing the guarded script requires neither lock acquisition nor external commands" {
  run bash -c 'DCCD_TESTING=1 source "$1"; printf "sourced\n"' test "${REPO_ROOT}/scripts/dccd.sh"
  assert_success
  assert_output sourced
  assert_file_not_exists "${BASE_DIR}/.dccd.lock"
  assert_mock_not_called git
  assert_mock_not_called docker
  assert_mock_not_called id
}
