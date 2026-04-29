#!/bin/bash
# generate-sops-rules.sh — Generate .sops.yaml creation_rules from servers.yaml
#
# Reads servers.yaml to build per-app SOPS creation rules that grant decryption
# access only to the servers that run each app. The deploy key is extracted from
# age.key (the "# public key:" comment line) and is always included so you can
# encrypt/decrypt all secrets from your dev machine.
#
# Servers without an 'apps' list (e.g. svlnas) are treated as all-access — their
# key is added to every app's rule.
#
# Usage:
#   bash scripts/generate-sops-rules.sh -d /path/to/repo
#
# Run this script whenever server-app mappings or Age keys change in servers.yaml.

set -euo pipefail

########################################
# Default configuration
########################################
BASE_DIR=""
UPDATE_KEYS=0

usage() {
    cat <<EOF
Usage: $0 -d <base_dir> [-u]

Options:
  -d <path>    Base directory of the git repository (required)
  -u           Run 'sops updatekeys' on all secret files after generating rules
  -h           Show this help message

The deploy key is read from <base_dir>/age.key (the "# public key:" comment).
Server keys are read from <base_dir>/servers.yaml (age_public_key fields).

Example:
  $0 -d /workspaces/truenas-apps
  $0 -d /workspaces/truenas-apps -u
EOF
    exit 1
}

while getopts ":d:uh" opt; do
    case "${opt}" in
    d) BASE_DIR="${OPTARG}" ;;
    u) UPDATE_KEYS=1 ;;
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

if [ -z "${BASE_DIR}" ]; then
    echo "ERROR: -d is required." >&2
    usage
fi

if ! command -v yq >/dev/null 2>&1; then
    echo "ERROR: yq is required but not found on PATH" >&2
    exit 1
fi

SERVERS_YAML="${BASE_DIR}/servers.yaml"
SOPS_YAML="${BASE_DIR}/.sops.yaml"
AGE_KEY="${BASE_DIR}/age.key"

if [ ! -f "${SERVERS_YAML}" ]; then
    echo "ERROR: servers.yaml not found at ${SERVERS_YAML}" >&2
    exit 1
fi

if [ ! -f "${AGE_KEY}" ]; then
    echo "ERROR: age.key not found at ${AGE_KEY}" >&2
    exit 1
fi

########################################
# Extract deploy key from age.key
########################################

DEPLOY_KEY=$(grep -oP '# public key: \K(age1[a-z0-9]+)' "${AGE_KEY}") || true
if [ -z "${DEPLOY_KEY}" ]; then
    echo "ERROR: Could not extract public key from ${AGE_KEY}" >&2
    echo "ERROR: Expected a line like: # public key: age1..." >&2
    exit 1
fi
echo "Deploy key: ${DEPLOY_KEY}"

########################################
# Build app → server key mapping
########################################

# Collect all server Age public keys and their access mode
declare -A SERVER_KEYS
declare -a ALL_ACCESS_KEYS=()

local_server_list=$(yq -r '.servers | keys | .[]' "${SERVERS_YAML}") || true
while IFS= read -r server; do
    key=$(yq -r ".servers.\"${server}\".age_public_key" "${SERVERS_YAML}")
    if [ -z "${key}" ] || [ "${key}" = "null" ]; then
        echo "WARNING: Server '${server}' has no age_public_key set, skipping" >&2
        continue
    fi
    SERVER_KEYS["${server}"]="${key}"

    # Servers without an 'apps' list get access to all apps
    has_apps=$(yq -r ".servers.\"${server}\" | has(\"apps\")" "${SERVERS_YAML}")
    if [ "${has_apps}" != "true" ]; then
        ALL_ACCESS_KEYS+=("${key}")
        echo "Server '${server}': all-access (no apps list)"
    else
        app_count=$(yq -r ".servers.\"${server}\".apps | length" "${SERVERS_YAML}")
        echo "Server '${server}': ${app_count} app(s)"
    fi
done <<<"${local_server_list}"

# Build the base key set: deploy key + all-access server keys
BASE_KEYS="${DEPLOY_KEY}"
for k in "${ALL_ACCESS_KEYS[@]}"; do
    BASE_KEYS="${BASE_KEYS},${k}"
done

# Build the all-servers key set: deploy + every server key (regardless of apps list).
# Used for shared secret files that every server must be able to decrypt.
ALL_SERVERS_KEYS="${DEPLOY_KEY}"
for server in "${!SERVER_KEYS[@]}"; do
    ALL_SERVERS_KEYS="${ALL_SERVERS_KEYS},${SERVER_KEYS[${server}]}"
done
ALL_SERVERS_KEYS=$(echo "${ALL_SERVERS_KEYS}" | tr ',' '\n' | sort -u | paste -sd',')

# For each app with a secret.sops.env, determine which keys should be recipients
declare -A APP_KEYS

# Detect per-server secret files (secret.<server>.sops.env) for credential isolation.
# When a server has its own file, its key is excluded from the base secret.sops.env rule.
declare -A HAS_SERVER_SECRETS # "app:server" → "1"
for server_sops_file in "${BASE_DIR}"/services/*/secret.*.sops.env; do
    [ -f "${server_sops_file}" ] || continue
    server_basename=$(basename "${server_sops_file}")
    # Extract server name: secret.<server>.sops.env
    server_name="${server_basename#secret.}"
    server_name="${server_name%.sops.env}"
    # Validate it's a known server (not empty / not the base file)
    if [ -z "${server_name}" ] || [ -z "${SERVER_KEYS[${server_name}]:-}" ]; then
        continue
    fi
    app_name=$(basename "$(dirname "${server_sops_file}")")
    HAS_SERVER_SECRETS["${app_name}:${server_name}"]="1"
    echo "  Per-server secret: ${app_name}/secret.${server_name}.sops.env"
done

for sops_file in "${BASE_DIR}"/services/*/secret.sops.env; do
    [ -f "${sops_file}" ] || continue
    app_dir=$(dirname "${sops_file}")
    app=$(basename "${app_dir}")

    # Start with deploy key + all-access server keys
    keys="${BASE_KEYS}"

    # Add keys for servers that explicitly list this app
    while IFS= read -r server; do
        has_apps=$(yq -r ".servers.\"${server}\" | has(\"apps\")" "${SERVERS_YAML}")
        if [ "${has_apps}" != "true" ]; then
            continue # Already included via ALL_ACCESS_KEYS
        fi
        has_app=$(yq -r ".servers.\"${server}\".apps[] | select(. == \"${app}\")" "${SERVERS_YAML}")
        if [ -n "${has_app}" ]; then
            # Skip servers that have their own per-server secret file
            # (they don't need access to the base file — credential isolation)
            if [ -n "${HAS_SERVER_SECRETS["${app}:${server}"]:-}" ]; then
                continue
            fi
            server_key="${SERVER_KEYS[${server}]:-}"
            if [ -n "${server_key}" ]; then
                keys="${keys},${server_key}"
            fi
        fi
    done <<<"${local_server_list}"

    # Deduplicate keys
    keys=$(echo "${keys}" | tr ',' '\n' | sort -u | paste -sd',')
    APP_KEYS["${app}"]="${keys}"
done

# Build per-server secret file rules: only that server's key + deploy + all-access
declare -A SERVER_SECRET_KEYS # "app/server" → comma-separated keys
for server_sops_file in "${BASE_DIR}"/services/*/secret.*.sops.env; do
    [ -f "${server_sops_file}" ] || continue
    server_basename=$(basename "${server_sops_file}")
    server_name="${server_basename#secret.}"
    server_name="${server_name%.sops.env}"

    server_key="${SERVER_KEYS[${server_name}]:-}"
    if [ -z "${server_key}" ]; then
        echo "WARNING: Server '${server_name}' in filename ${server_basename} not found in servers.yaml, skipping" >&2
        continue
    fi

    app_name=$(basename "$(dirname "${server_sops_file}")")

    # Keys: deploy + all-access + this specific server only
    keys="${BASE_KEYS},${server_key}"
    keys=$(echo "${keys}" | tr ',' '\n' | sort -u | paste -sd',')
    SERVER_SECRET_KEYS["${app_name}/${server_name}"]="${keys}"
done

########################################
# Generate .sops.yaml
########################################

# Format comma-separated keys as multi-line YAML (one key per line under >-)
# Usage: format_age_keys "key1,key2,key3" "      " → indented lines
format_age_keys() {
    local keys="${1}"
    local indent="${2}"
    local formatted
    formatted=$(echo "${keys}" | tr ',' '\n' | sed '$!s/$/,/')
    while IFS= read -r line; do
        echo "${indent}${line}"
    done <<<"${formatted}"
}

# Determine the fallback key set (deploy + all-access keys)
FALLBACK_KEYS=$(echo "${BASE_KEYS}" | tr ',' '\n' | sort -u | paste -sd',')

{
    echo "---"
    echo "creation_rules:"

    # Per-server-specific rules first (most specific path_regex — SOPS matches first hit)
    for key in $(echo "${!SERVER_SECRET_KEYS[@]}" | tr ' ' '\n' | sort); do
        keys="${SERVER_SECRET_KEYS[${key}]}"
        app_part="${key%%/*}"
        server_part="${key##*/}"
        echo "  - path_regex: services/${app_part}/secret\\.${server_part}\\.sops\\.env\$"
        echo "    age: >-"
        format_age_keys "${keys}" "      "
    done

    # Per-app base rules (sorted for deterministic output)
    for app in $(echo "${!APP_KEYS[@]}" | tr ' ' '\n' | sort); do
        keys="${APP_KEYS[${app}]}"
        # Only emit a per-app rule if it differs from the fallback
        if [ "${keys}" != "${FALLBACK_KEYS}" ]; then
            echo "  - path_regex: services/${app}/secret\\.sops\\.env\$"
            echo "    age: >-"
            format_age_keys "${keys}" "      "
        fi
    done

    # Shared secret files (services/shared/*/secret.sops.env): every server
    # must be able to decrypt these, so include all server keys.
    echo "  - path_regex: services/shared/.*/secret\\.sops\\.env\$"
    echo "    age: >-"
    format_age_keys "${ALL_SERVERS_KEYS}" "      "

    # Fallback rule: catches all remaining secret.sops.env files
    echo "  - path_regex: secret\\.sops\\.env\$"
    echo "    age: >-"
    format_age_keys "${FALLBACK_KEYS}" "      "
} >"${SOPS_YAML}"

rule_count=$(grep -c 'path_regex:' "${SOPS_YAML}") || true
echo ""
echo "Generated ${SOPS_YAML} with ${rule_count} rule(s)"

########################################
# Update keys on existing encrypted files
########################################

if [ "${UPDATE_KEYS}" -eq 1 ]; then
    if ! command -v sops >/dev/null 2>&1; then
        echo "ERROR: sops is required for -u but not found on PATH" >&2
        exit 1
    fi

    echo ""
    echo "Updating keys on all secret files..."
    update_count=0
    update_errors=0

    for sops_file in \
        "${BASE_DIR}"/services/*/secret*.sops.env \
        "${BASE_DIR}"/services/shared/*/secret*.sops.env; do
        [ -f "${sops_file}" ] || continue
        echo "  Updating: ${sops_file}"
        if sops updatekeys -y "${sops_file}"; then
            update_count=$((update_count + 1))
        else
            echo "  WARNING: Failed to update keys for ${sops_file}" >&2
            update_errors=$((update_errors + 1))
        fi
    done

    echo ""
    if [ "${update_errors}" -eq 0 ]; then
        echo "Updated keys on ${update_count} file(s)"
    else
        echo "Updated keys on ${update_count} file(s), ${update_errors} failed"
    fi
else
    echo ""
    echo "Next steps:"
    echo "  1. Review the generated .sops.yaml"
    echo "  2. Run '$0 -d ${BASE_DIR} -u' or 'sops updatekeys' on each secret file"
    echo "  3. For new per-server files, create them plaintext then encrypt:"
    echo "     sops -e -i services/<app>/secret.<server>.sops.env"
    echo "  4. Commit the updated .sops.yaml and re-encrypted secret files"
fi
