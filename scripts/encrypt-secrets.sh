#!/bin/bash
# encrypt-secrets.sh — Validate and encrypt unencrypted secret.sops.env files
#
# Scans all services/*/secret*.sops.env files for plaintext (unencrypted) secrets.
# Optionally encrypts them in-place using sops. Exits non-zero if any file is
# unencrypted and --encrypt is not passed (useful for CI checks).
#
# Usage:
#   bash scripts/encrypt-secrets.sh -d /path/to/repo            # check only
#   bash scripts/encrypt-secrets.sh -d /path/to/repo --encrypt   # encrypt unencrypted files

set -euo pipefail

_ENCRYPT_SECRETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh disable=SC1091
. "${_ENCRYPT_SECRETS_DIR}/lib/log.sh"
# shellcheck disable=SC2034
LOG_TAG="encrypt-secrets"

########################################
# Configuration
########################################
BASE_DIR=""
DO_ENCRYPT=0

usage() {
    cat <<EOF
Usage: $0 -d <base_dir> [--encrypt]

Options:
  -d <path>    Base directory of the git repository (required)
  --encrypt    Encrypt any unencrypted secret.sops.env files in-place
  -h           Show this help message

Without --encrypt, the script only reports unencrypted files and exits non-zero
if any are found. With --encrypt, it runs 'sops -e -i' on each unencrypted file.

Example:
  $0 -d /workspaces/truenas-apps
  $0 -d /workspaces/truenas-apps --encrypt
EOF
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
    -d)
        BASE_DIR="${2:?'-d requires a path argument'}"
        shift 2
        ;;
    --encrypt)
        DO_ENCRYPT=1
        shift
        ;;
    -h | --help)
        usage
        ;;
    *)
        log_error "Unknown option: $1"
        usage
        ;;
    esac
done

if [ -z "${BASE_DIR}" ]; then
    log_error "-d <base_dir> is required"
    usage
fi

if [ ! -d "${BASE_DIR}/services" ]; then
    log_error "${BASE_DIR}/services does not exist"
    exit 1
fi

########################################
# Detection
########################################

# A SOPS-encrypted dotenv file always contains metadata keys starting with
# "sops_". If a file lacks any sops_ line, it is unencrypted.
is_encrypted() {
    grep -q '^sops_' "$1"
}

unencrypted_files=()
encrypted_files=()

for secret_file in \
    "${BASE_DIR}"/services/*/secret*.sops.env \
    "${BASE_DIR}"/services/shared/*/secret*.sops.env; do
    [ -f "${secret_file}" ] || continue

    # shellcheck disable=SC2310 # is_encrypted is intentionally used in a conditional
    if is_encrypted "${secret_file}"; then
        encrypted_files+=("${secret_file}")
    else
        unencrypted_files+=("${secret_file}")
    fi
done

########################################
# Report
########################################

total=$((${#encrypted_files[@]} + ${#unencrypted_files[@]}))
log_info "Found ${total} secret.sops.env file(s):"
log_info "  ${#encrypted_files[@]} encrypted, ${#unencrypted_files[@]} unencrypted"

if [ ${#unencrypted_files[@]} -eq 0 ]; then
    log_result "All secret files are encrypted."
    exit 0
fi

log_warn "Unencrypted files:"
for f in "${unencrypted_files[@]}"; do
    log_warn "  ${f}"
done

########################################
# Encrypt (if requested)
########################################

if [ "${DO_ENCRYPT}" -eq 0 ]; then
    log_hint "Run with --encrypt to encrypt these files in-place."
    log_hint "Make sure .sops.yaml creation_rules are up to date first:"
    log_hint "  bash scripts/generate-sops-rules.sh -d ${BASE_DIR}"
    exit 1
fi

log_state "Encrypting unencrypted files..."
failed=0
for f in "${unencrypted_files[@]}"; do
    log_state "Encrypting: ${f}"
    if sops -e -i "${f}"; then
        log_result "Encrypted: ${f}"
    else
        log_error "Failed to encrypt: ${f}"
        failed=1
    fi
done

if [ "${failed}" -eq 1 ]; then
    log_error "Some files failed to encrypt. Check the output above."
    log_hint "Common causes:"
    log_hint "  - Missing .sops.yaml creation_rule for the file"
    log_hint "  - No Age key available (set SOPS_AGE_KEY_FILE or SOPS_AGE_KEY)"
    exit 1
fi

log_result "All files encrypted successfully."
log_hint "Next steps:"
log_hint "  1. Review changes: git diff"
log_hint "  2. If server-app mappings changed, regenerate SOPS rules:"
log_hint "     bash scripts/generate-sops-rules.sh -d ${BASE_DIR}"
