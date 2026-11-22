#!/usr/bin/env bash
set -euo pipefail

mise exec -- yq -r '.servers[].apps // [] | .[]' servers.yaml |
    sort -u |
    while IFS= read -r app; do
        app="${app%$'\r'}"
        if [[ ! -d "services/${app}" ]]; then
            printf "ERROR: App '%s' in servers.yaml has no services/%s/ directory\n" "${app}" "${app}" >&2
            exit 1
        fi
    done
