#!/bin/bash
# A child with no subprocesses. A FIFO makes readiness/exit injection explicit
# and avoids races from fixed sleeps or immortal background sleep processes.
set -eu
role="${CHILD_ROLE:-${0##*/}}"
if [[ "${role}" == 'browser executable' ]]; then
  role=browser
fi
trap 'printf "%s\n" TERM >"${TEST_TMPDIR}/${role}.terminated"; exit 0' TERM
printf '%s\n' "$$" >"${TEST_TMPDIR}/${role}.pid"
printf '%s\0' "$@" >"${TEST_TMPDIR}/${role}.argv"
exec 7<>"${TEST_TMPDIR}/${role}.control"
printf '%s\n' ready >"${TEST_TMPDIR}/${role}.ready"
while true; do
  if IFS= read -r -t 0.1 -u 7 instruction; then
    case "${instruction}" in
    exit:*) exit "${instruction#exit:}" ;;
    *)
      printf 'Invalid test child instruction: %s\n' "${instruction}" >&2
      exit 98
      ;;
    esac
  fi
done
