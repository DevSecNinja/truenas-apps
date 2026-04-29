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
        echo "Unknown option: $1" >&2
        usage
        ;;
    esac
done

if [ -z "${BASE_DIR}" ]; then
    echo "Error: -d <base_dir> is required" >&2
    usage
fi

if [ ! -d "${BASE_DIR}/services" ]; then
    echo "Error: ${BASE_DIR}/services does not exist" >&2
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
echo "Found ${total} secret.sops.env file(s):"
echo "  ✓ ${#encrypted_files[@]} encrypted"
echo "  ✗ ${#unencrypted_files[@]} unencrypted"
echo ""

if [ ${#unencrypted_files[@]} -eq 0 ]; then
    echo "All secret files are encrypted."
    exit 0
fi

echo "Unencrypted files:"
for f in "${unencrypted_files[@]}"; do
    echo "  ${f}"
done
echo ""

########################################
# Encrypt (if requested)
########################################

if [ "${DO_ENCRYPT}" -eq 0 ]; then
    echo "Run with --encrypt to encrypt these files in-place."
    echo "Make sure .sops.yaml creation_rules are up to date first:"
    echo "  bash scripts/generate-sops-rules.sh -d ${BASE_DIR}"
    exit 1
fi

echo "Encrypting unencrypted files..."
failed=0
for f in "${unencrypted_files[@]}"; do
    echo "  Encrypting: ${f}"
    if sops -e -i "${f}"; then
        echo "    ✓ Done"
    else
        echo "    ✗ FAILED"
        failed=1
    fi
done

echo ""
if [ "${failed}" -eq 1 ]; then
    echo "Some files failed to encrypt. Check the output above."
    echo "Common causes:"
    echo "  - Missing .sops.yaml creation_rule for the file"
    echo "  - No Age key available (set SOPS_AGE_KEY_FILE or SOPS_AGE_KEY)"
    exit 1
fi

echo "All files encrypted successfully."
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff"
echo "  2. If server-app mappings changed, regenerate SOPS rules:"
echo "     bash scripts/generate-sops-rules.sh -d ${BASE_DIR}"
