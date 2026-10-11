#!/usr/bin/env bash
# Exercise the real recovery main in a fresh strict-mode shell. Only the
# TrueNAS rendered-file lookup is replaced; never create /mnt/.ix-apps paths.

recovery_require_tools() {
  diagnostics_require_helpers
  if [[ "${OSTYPE}" != linux* ]]; then
    skip "Recovery coordination tests require Linux /proc and real flock"
  fi
  local tool
  for tool in jq flock; do
    command -v "${tool}" || return 1
  done
}

recovery_setup() {
  diagnostics_setup
  unset DCCD_LOCK_FD DCCD_RECOVERY_APP DCCD_TESTING RECOVERY_TESTING COMPOSE_PROFILES
  export TEST_BASE_DIR="${BASE_DIR}"
  export RECOVERY_WAIT_TIMEOUT=900
  export TEST_SNAPSHOT='tank/apps/widget@pre-dccd-20261010T210000Z-42'
  mkdir -p "${BASE_DIR}/scripts/lib" "${BASE_DIR}/services/widget"
  touch "${BASE_DIR}/services/widget/compose.yaml"
  cp "${REPO_ROOT}/scripts/truenas-recover-app.sh" "${BASE_DIR}/scripts/"
  cp "${REPO_ROOT}/scripts/lib/"{log,deployment-lock}.sh "${BASE_DIR}/scripts/lib/"
  local fixture="${REPO_ROOT}/tests/dccd/fixtures/recovery-command.bash" command
  for command in sudo docker zfs git id date; do
    cp "${fixture}" "${MOCK_BIN}/${command}"
    chmod +x "${MOCK_BIN}/${command}"
  done
  cp "${fixture}" "${BASE_DIR}/scripts/dccd.sh"
}

run_recovery() {
  run bash -c '
    RECOVERY_TESTING=1 source "$1"
    recovery_resolve_compose() {
      RECOVERY_COMPOSE="${BASE_DIR}/services/${RECOVERY_APP}/compose.yaml"
    }
    recovery_main "${@:2}"
  ' recovery-test "${BASE_DIR}/scripts/truenas-recover-app.sh" "$@"
}

recovery_seed_snapshot() {
  printf 'widget\n%s\n' "${TEST_SNAPSHOT}" >"${BASE_DIR}/.dccd-maintenance"
  printf '%s\n' "${TEST_SNAPSHOT}" >"${MOCK_LOG}/snapshot-name"
  printf 'revision-target\n' >"${MOCK_LOG}/target-revision"
  touch "${MOCK_LOG}/synced"
  rm -f "${MOCK_LOG}/target-images"
}

assert_recovery_event_absent() {
  local pattern="$1"
  if [[ -f "${MOCK_LOG}/events" ]]; then
    run grep -E -- "${pattern}" "${MOCK_LOG}/events"
    assert_failure 1
  fi
}

assert_recovery_paused() {
  assert_file_exists "${BASE_DIR}/.dccd-maintenance"
  assert_recovery_event_absent '^(complete|destroy) '
}

assert_recovery_not_stopped() {
  assert_recovery_event_absent '^(stop|snapshot|deploy|destroy)( |$)'
}
