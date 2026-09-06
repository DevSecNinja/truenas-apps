#!/bin/bash
# Fails scheduled dependency monitoring when Renovate reports package lookup
# failures in its open Dependency Dashboard issue.

set -euo pipefail

_RENOVATE_HEALTH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh disable=SC1091
. "${_RENOVATE_HEALTH_DIR}/lib/log.sh"
# shellcheck disable=SC2034
LOG_TAG="renovate-health-check"

dashboard_json=$(
    gh issue list \
        --state open \
        --search '"Renovate Dashboard" in:title' \
        --limit 2 \
        --json number,title,url,body
)

dashboard_count=$(printf '%s' "${dashboard_json}" | jq 'length')
if [ "${dashboard_count}" -ne 1 ]; then
    log_error "Expected one open Renovate Dashboard issue, found ${dashboard_count}"
    exit 1
fi

dashboard_url=$(printf '%s' "${dashboard_json}" | jq -r '.[0].url')
dashboard_body=$(printf '%s' "${dashboard_json}" | jq -r '.[0].body')

if printf '%s\n' "${dashboard_body}" |
    grep -Eq 'Package lookup failures|Renovate failed to look up|Error obtaining docker token'; then
    log_error "Renovate reports package lookup failures: ${dashboard_url}"
    exit 1
fi

log_result "Renovate reports no package lookup failures: ${dashboard_url}"
