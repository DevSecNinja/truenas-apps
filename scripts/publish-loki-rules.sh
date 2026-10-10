#!/usr/bin/env bash
# publish-loki-rules.sh - Push Loki ruler YAML files to Grafana Cloud.
#
# Uploads every rule file under services/alloy/rules/*.yaml to the Grafana
# Cloud Loki ruler API, one namespace per file (namespace is read from each
# file's top-level `namespace:` key).
#
# Required environment:
#   GRAFANA_LOKI_URL    e.g. https://logs-prod-012.grafana.net
#   GRAFANA_LOKI_USER   numeric tenant / user id (Loki "username")
#   GRAFANA_LOKI_TOKEN  Grafana Cloud access policy token with `logs:write`
#
# Usage:
#   ./scripts/publish-loki-rules.sh           # publish all rule files
#   ./scripts/publish-loki-rules.sh dccd      # publish a specific rule file
#
# This is a one-shot uploader; rerun it after editing any rule file.

set -euo pipefail

: "${GRAFANA_LOKI_URL:?GRAFANA_LOKI_URL is required}"
: "${GRAFANA_LOKI_USER:?GRAFANA_LOKI_USER is required}"
: "${GRAFANA_LOKI_TOKEN:?GRAFANA_LOKI_TOKEN is required}"

repo_root=$(git rev-parse --show-toplevel)
rules_dir="${repo_root}/services/alloy/rules"

if [ ! -d "${rules_dir}" ]; then
    echo "ERROR: rules directory not found: ${rules_dir}" >&2
    exit 1
fi

files=()
if [ "$#" -gt 0 ]; then
    for name in "$@"; do
        f="${rules_dir}/${name%.yaml}.yaml"
        if [ ! -f "${f}" ]; then
            echo "ERROR: rule file not found: ${f}" >&2
            exit 1
        fi
        files+=("${f}")
    done
else
    # shellcheck disable=SC2312  # find/sort exit codes in process substitution are non-fatal
    while IFS= read -r -d '' f; do
        files+=("${f}")
    done < <(find "${rules_dir}" -maxdepth 1 -type f -name '*.yaml' -print0 | sort -z)
fi

if [ "${#files[@]}" -eq 0 ]; then
    echo "No rule files to publish."
    exit 0
fi

api="${GRAFANA_LOKI_URL%/}/loki/api/v1/rules"

for f in "${files[@]}"; do
    namespace=$(awk '/^namespace:/ { print $2; exit }' "${f}")
    if [ -z "${namespace}" ]; then
        echo "ERROR: ${f} has no top-level 'namespace:' key" >&2
        exit 1
    fi

    # Strip the namespace key and upload only the `groups:` body, which is
    # the format the Loki ruler API expects under /rules/<namespace>.
    body=$(awk '
        /^namespace:/ { skip=1; next }
        /^[^[:space:]#]/ { skip=0 }
        skip { next }
        { print }
    ' "${f}")

    echo "Publishing ${f} -> namespace=${namespace}"
    printf '%s\n' "${body}" | curl -fsSL \
        --user "${GRAFANA_LOKI_USER}:${GRAFANA_LOKI_TOKEN}" \
        -H "Content-Type: application/yaml" \
        --data-binary @- \
        "${api}/${namespace}"
    echo "  ok"
done
