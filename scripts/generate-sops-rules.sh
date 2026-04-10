#!/bin/bash
# generate-sops-rules.sh — Generate .sops.yaml creation_rules from servers.yaml
#
# Reads servers.yaml to build per-app SOPS creation rules that grant decryption
# access only to the servers that run each app. A deploy key (your dev machine)
# is always included so you can decrypt everything.
#
# Usage:
#   bash scripts/generate-sops-rules.sh -d /path/to/repo -D age1deploy...
#
# The deploy key is the Age public key of your development machine. It is always
# added as a recipient to every rule so you can encrypt/decrypt all secrets.
#
# The svlnas key is the Age public key of the TrueNAS server. Apps not explicitly
# assigned to any server in servers.yaml are assumed to run on svlnas (fallback).

set -euo pipefail

########################################
# Default configuration
########################################
BASE_DIR=""
DEPLOY_KEY=""
SVLNAS_KEY=""

usage() {
    cat <<EOF
Usage: $0 -d <base_dir> -D <deploy_age_pubkey> -N <svlnas_age_pubkey>

Options:
  -d <path>    Base directory of the git repository (required)
  -D <key>     Age public key of the deploy/dev machine (required, always a recipient)
  -N <key>     Age public key of the svlnas TrueNAS server (required)
  -h           Show this help message

Example:
  $0 -d /workspaces/truenas-apps -D age1abc...def -N age1nas...xyz
EOF
    exit 1
}

while getopts ":d:D:N:h" opt; do
    case "${opt}" in
    d) BASE_DIR="${OPTARG}" ;;
    D) DEPLOY_KEY="${OPTARG}" ;;
    N) SVLNAS_KEY="${OPTARG}" ;;
    h) usage ;;
    \?)
        echo "Invalid option: -${OPTARG}" >&2
        usage
        ;;
    :)
        echo "Option -${OPTARG} requires an argument." >&2
        usage
        ;;
    *) usage ;;
    esac
done

if [ -z "${BASE_DIR}" ] || [ -z "${DEPLOY_KEY}" ] || [ -z "${SVLNAS_KEY}" ]; then
    echo "ERROR: -d, -D, and -N are all required." >&2
    usage
fi

if ! command -v yq >/dev/null 2>&1; then
    echo "ERROR: yq is required but not found on PATH" >&2
    exit 1
fi

SERVERS_YAML="${BASE_DIR}/servers.yaml"
SOPS_YAML="${BASE_DIR}/.sops.yaml"

if [ ! -f "${SERVERS_YAML}" ]; then
    echo "ERROR: servers.yaml not found at ${SERVERS_YAML}" >&2
    exit 1
fi

########################################
# Build app → server key mapping
########################################

# Collect all server Age public keys keyed by server name
declare -A SERVER_KEYS
local_server_list=$(yq -r '.servers | keys | .[]' "${SERVERS_YAML}") || true
while IFS= read -r server; do
    key=$(yq -r ".servers.\"${server}\".age_public_key" "${SERVERS_YAML}")
    if [ -z "${key}" ] || [ "${key}" = "null" ]; then
        echo "WARNING: Server '${server}' has no age_public_key set, skipping" >&2
        continue
    fi
    SERVER_KEYS["${server}"]="${key}"
done <<<"${local_server_list}"

# For each app with a secret.sops.env, determine which keys should be recipients
declare -A APP_KEYS
for sops_file in "${BASE_DIR}"/services/*/secret.sops.env; do
    [ -f "${sops_file}" ] || continue
    app_dir=$(dirname "${sops_file}")
    app=$(basename "${app_dir}")

    # Start with deploy key + svlnas key (svlnas is the default/fallback server)
    keys="${DEPLOY_KEY},${SVLNAS_KEY}"

    # Add keys for any server in servers.yaml that lists this app
    while IFS= read -r server; do
        has_app=$(yq -r ".servers.\"${server}\".apps[] | select(. == \"${app}\")" "${SERVERS_YAML}")
        if [ -n "${has_app}" ]; then
            server_key="${SERVER_KEYS[${server}]:-}"
            if [ -n "${server_key}" ]; then
                keys="${keys},${server_key}"
            fi
        fi
    done <<<"${local_server_list}"

    # Deduplicate keys (in case svlnas key was added twice)
    keys=$(echo "${keys}" | tr ',' '\n' | sort -u | paste -sd',')
    APP_KEYS["${app}"]="${keys}"
done

########################################
# Generate .sops.yaml
########################################

# Determine the fallback key set (deploy + svlnas)
FALLBACK_KEYS="${DEPLOY_KEY},${SVLNAS_KEY}"

{
    echo "---"
    echo "creation_rules:"

    # Per-app rules (sorted for deterministic output)
    for app in $(echo "${!APP_KEYS[@]}" | tr ' ' '\n' | sort); do
        keys="${APP_KEYS[${app}]}"
        # Only emit a per-app rule if it differs from the fallback
        if [ "${keys}" != "${FALLBACK_KEYS}" ]; then
            echo "  - path_regex: services/${app}/secret\\.sops\\.env\$"
            echo "    age: >-"
            echo "      ${keys}"
        fi
    done

    # Fallback rule: catches all remaining secret.sops.env files
    # (new apps default to deploy + svlnas)
    echo "  - path_regex: secret\\.sops\\.env\$"
    echo "    age: >-"
    echo "      ${FALLBACK_KEYS}"
} >"${SOPS_YAML}"

rule_count=$(grep -c 'path_regex:' "${SOPS_YAML}") || true
echo "Generated ${SOPS_YAML} with ${rule_count} rule(s)"
echo ""
echo "Next steps:"
echo "  1. Review the generated .sops.yaml"
echo "  2. Run 'sops updatekeys services/<app>/secret.sops.env' for each app to re-encrypt"
echo "  3. Commit the updated .sops.yaml and re-encrypted secret files"
