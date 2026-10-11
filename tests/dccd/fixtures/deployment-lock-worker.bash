#!/usr/bin/env bash
# Real Linux flock holder with bounded, file-based handshakes. No Docker/ZFS.
set -euo pipefail
exec 3>&-
BASE_DIR="$1"
library="$2"
state="$3"
mode="$4"
# shellcheck disable=SC1090
source "${library}"
log_error() { printf '%s\n' "$*" >&2; }

hold() {
  touch "${state}/ready"
  local deadline=$((SECONDS + 10))
  until [[ -f "${state}/release" ]]; do
    ((SECONDS < deadline)) || exit 98
    sleep 0.02
  done
}

case "${mode}" in
try)
  dccd_acquire_lock
  printf 'acquired\n'
  ;;
hold)
  dccd_acquire_lock
  hold
  ;;
reexec)
  dccd_acquire_lock
  export EXPECTED_LOCK_FD="${DCCD_LOCK_FD}"
  exec bash "$0" "${BASE_DIR}" "${library}" "${state}" inherited-hold
  ;;
inherited-hold | borrowed-exit)
  dccd_acquire_lock
  [[ "${DCCD_LOCK_FD}" == "${EXPECTED_LOCK_FD}" ]] || exit 96
  if [[ "${mode}" == inherited-hold ]]; then hold; fi
  ;;
child-exit)
  dccd_acquire_lock
  export EXPECTED_LOCK_FD="${DCCD_LOCK_FD}"
  bash "$0" "${BASE_DIR}" "${library}" "${state}" borrowed-exit
  touch "${state}/child-done"
  hold
  ;;
parent-exit)
  dccd_acquire_lock
  export EXPECTED_LOCK_FD="${DCCD_LOCK_FD}"
  bash "$0" "${BASE_DIR}" "${library}" "${state}" inherited-hold &
  printf '%s\n' "$!" >"${state}/child.pid"
  ;;
other-checkout)
  dccd_acquire_lock
  BASE_DIR="${BASE_DIR}/other-checkout"
  dccd_acquire_lock
  hold
  ;;
*) exit 97 ;;
esac
