#!/usr/bin/env bash
set -euo pipefail

command="${0##*/}"
printf '%s\n' "$*" >>"${MOCK_LOG}/${command}.calls"
bare="${DISCOVERY_IMAGE%%@*}"
title="[${bare}] Stale image detected"

case "${command}" in
crane)
  [[ "$#" == 2 && "$1" == config && "$2" == "${bare}" ]] || exit 97
  printf '{"created":"2033-05-17T00:00:00Z"}\n'
  ;;
date)
  # Deterministic age arithmetic, independent of wall clock/platform date.
  if [[ "$*" == '+%s' ]]; then
    printf '2000000000\n'
  elif [[ "$*" == '-d 2033-05-17T00:00:00Z +%s' ]]; then
    if [[ "${DISCOVERY_STALE}" == 1 ]]; then
      printf '1965440000\n'
    else
      printf '1999913600\n'
    fi
  else
    exit 97
  fi
  ;;
gh)
  case "$*" in
  'issue list --label stale-dependency --state open --json number,title')
    if [[ "${DISCOVERY_OPEN_ISSUE}" == 1 ]]; then
      printf '[{"number":41,"title":"%s"}]\n' "${title}"
    else
      printf '[]\n'
    fi
    ;;
  'issue list --label stale-dependency --state open --json title --jq .[].title')
    if [[ "${DISCOVERY_OPEN_ISSUE}" == 1 ]]; then
      printf '%s\n' "${title}"
    fi
    ;;
  'issue close 41 --comment '*)
    printf '%s\n' "$*" >>"${MOCK_LOG}/gh.close.calls"
    ;;
  *)
    exit 97
    ;;
  esac
  ;;
mise)
  [[ "$#" -ge 3 && "$1" == exec && "$2" == -- && "$3" == trivy ]] || exit 97
  shift 3
  exec "${MOCK_BIN}/trivy" "$@"
  ;;
trivy)
  [[ "$#" == 11 && "$1" == image && "${11}" == "${DISCOVERY_IMAGE}" ]] || exit 97
  [[ "$2 $3 $4 $5 $6 $7 $8 $9" == '--scanners vuln --ignore-unfixed --severity CRITICAL --format sarif --output' ]] || exit 97
  [[ "${10}" == sarif-tmp/*.sarif ]] || exit 97
  cp "${DISCOVERY_SARIF}" "${10}"
  ;;
logger) ;;
*)
  printf 'Unexpected external call blocked: %s %s\n' "${command}" "$*" >&2
  exit 97
  ;;
esac
