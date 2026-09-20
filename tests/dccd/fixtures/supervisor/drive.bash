#!/bin/bash
# Execute the real supervisor with controlled PATH children. Exit with the
# supervisor's status only after all lifecycle assertions have succeeded.
set -uo pipefail
scenario="$1"
shift
supervisor_pid=''
sentinel_pid=''
sleep_bin="$(command -v sleep)"

fail() {
  printf 'HARNESS FAILURE: %s\n' "$*" >&2
  exit 98
}

await() {
  local attempt
  for ((attempt = 0; attempt < 250; attempt++)); do
    if "$@"; then
      return 0
    fi
    "${sleep_bin}" 0.02
  done
  return 1
}

# shellcheck disable=SC2329 # Called indirectly through await's "$@" dispatcher.
dead() {
  ! kill -0 "$1" 2>/dev/null
}

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
  local role pid
  # Only PIDs created/recorded by this harness; never pkill, killall or
  # process-group signalling. Do not leave processes behind on assertion
  # failure or timeout.
  for role in socat browser; do
    if [[ -s "${TEST_TMPDIR}/${role}.pid" ]]; then
      pid="$(<"${TEST_TMPDIR}/${role}.pid")"
      kill -TERM "${pid}" 2>/dev/null || true
      await dead "${pid}" || kill -KILL "${pid}" 2>/dev/null || true
    fi
  done
  for pid in "${supervisor_pid}" "${sentinel_pid}"; do
    if [[ -n "${pid}" ]]; then
      kill -TERM "${pid}" 2>/dev/null || true
      await dead "${pid}" || kill -KILL "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
    fi
  done
}

trap 'cleanup' EXIT
trap 'exit 98' TERM INT

for role in socat browser sentinel; do
  mkfifo "${TEST_TMPDIR}/${role}.control" || fail "mkfifo ${role}"
done

# The unrelated process is the very same browser stub. A name-based cleanup
# would kill it as well; it must remain alive until the harness cleans it up.
CHILD_ROLE=sentinel "${MOCK_BIN}/browser executable" 3>&- &
sentinel_pid=$!
await test -f "${TEST_TMPDIR}/sentinel.ready" || fail 'sentinel never became ready'

# Without job control Bash makes asynchronous commands inherit ignored INT.
# Enable it only while launching the supervisor, so INT exercises its trap
# rather than that shell-launch artifact. Disable it before polling/waiting to
# avoid job notifications on stderr. All signals still target individual PIDs.
if [[ "${scenario}" == int ]]; then
  set -m
fi
case "${scenario}" in
missing-args)
  PATH="${MOCK_BIN}" "${BASH}" "${SUPERVISOR_SCRIPT}" 3>&- &
  ;;
missing-socat)
  # Isolate PATH: never accidentally execute a host-installed socat.
  rm "${MOCK_BIN}/socat"
  PATH="${MOCK_BIN}" "${BASH}" "${SUPERVISOR_SCRIPT}" "${MOCK_BIN}/browser executable" 3>&- &
  ;;
missing-browser)
  PATH="${MOCK_BIN}" "${BASH}" "${SUPERVISOR_SCRIPT}" "${MOCK_BIN}/nonexistent-browser" 3>&- &
  ;;
*)
  PATH="${MOCK_BIN}" "${BASH}" "${SUPERVISOR_SCRIPT}" "${MOCK_BIN}/browser executable" "$@" 3>&- &
  ;;
esac
supervisor_pid=$!
set +m

case "${scenario}" in
socat:* | browser:* | term | int)
  await test -f "${TEST_TMPDIR}/socat.ready" || fail 'socat never became ready'
  await test -f "${TEST_TMPDIR}/browser.ready" || fail 'browser never became ready'
  kill -0 "${supervisor_pid}" 2>/dev/null || fail 'supervisor exited while both children were live'
  if [[ "${scenario}" == term ]]; then
    kill -TERM "${supervisor_pid}" || fail 'could not stop supervisor'
  elif [[ "${scenario}" == int ]]; then
    kill -INT "${supervisor_pid}" || fail 'could not interrupt supervisor'
  else
    role="${scenario%%:*}"
    printf 'exit:%s\n' "${scenario#*:}" >"${TEST_TMPDIR}/${role}.control"
  fi
  ;;
missing-args | missing-socat | missing-browser) ;;
*) fail "unknown scenario ${scenario}" ;;
esac

await dead "${supervisor_pid}" || fail 'supervisor did not exit within 5s'
wait "${supervisor_pid}"
rc=$?
supervisor_pid=''

for role in socat browser; do
  if [[ -s "${TEST_TMPDIR}/${role}.pid" ]]; then
    pid="$(<"${TEST_TMPDIR}/${role}.pid")"
    await dead "${pid}" || fail "${role} left running after supervisor exit"
  fi
done
kill -0 "${sentinel_pid}" 2>/dev/null || fail 'unrelated browser was terminated'

# Readiness was observed before injection, so TERM receipt by the sibling is
# deterministic. Immediate exec failures may happen before a child sets traps.
case "${scenario}" in
socat:*) [[ -f "${TEST_TMPDIR}/browser.terminated" ]] || fail 'browser sibling did not receive TERM' ;;
browser:*) [[ -f "${TEST_TMPDIR}/socat.terminated" ]] || fail 'socat sibling did not receive TERM' ;;
term | int)
  [[ -f "${TEST_TMPDIR}/socat.terminated" ]] || fail 'socat did not receive TERM'
  [[ -f "${TEST_TMPDIR}/browser.terminated" ]] || fail 'browser did not receive TERM'
  ;;
*) ;; # Immediate exec failures can precede the child's TERM trap.
esac
printf 'supervisor-status=%s\nchildren-stopped\nunrelated-browser-alive\n' "${rc}"
exit "${rc}"
