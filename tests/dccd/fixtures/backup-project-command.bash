#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${MOCK_LOG}/docker.calls"
case "$1" in
ps)
  printf 'target-1\twidget-db-backup-1\twidget-db-backup\t\n'
  if [[ "$*" != *'--filter label=com.docker.compose.project=ix-widget '* ]]; then
    printf 'other-1\tother-db-backup-1\tother-db-backup\t\n'
  fi
  ;;
inspect)
  if [[ "${*: -1}" == target-1 ]]; then
    printf 'exited|0|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z\n'
  else
    printf 'exited|9|2026-09-06T18:59:00Z|2026-09-06T19:00:00Z\n'
  fi
  ;;
logs)
  [[ "${*: -1}" == target-1 ]] || exit 97
  printf 'Backup 01 routines finish time: 2026-09-06 19:00:00 UTC with exit code 0\n'
  ;;
*) exit 97 ;;
esac
