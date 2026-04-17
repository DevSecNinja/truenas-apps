#!/usr/bin/env bash
# Check and fix service folders that lack a dedicated ZFS dataset.
# Run on the TrueNAS server: sudo bash scripts/check-datasets.sh /mnt/<pool>/apps/services
#
# Modes:
#   --check   (default) Report which service dirs have no dataset
#   --fix     Interactive guided workflow: stop containers, move dirs,
#             wait for dataset creation, move contents back

set -euo pipefail

# --- Require root ---
if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: This script must be run as root (use sudo)." >&2
    exit 1
fi

MODE="check"
if [[ "${1:-}" == "--fix" ]]; then
    MODE="fix"
    shift
fi

SERVICES_PATH="${1:?Usage: sudo $0 [--fix] /mnt/<pool>/apps/services}"

# Resolve to absolute path
SERVICES_PATH="$(cd "${SERVICES_PATH}" && pwd)"

# --- Collect dirs without a dataset ---
collect_missing() {
    local -n result=$1
    for dir in "${SERVICES_PATH}"/*/; do
        [[ -d "${dir}" ]] || continue
        local dir_name
        dir_name="$(basename "${dir}")"
        if ! zfs list -H -o mountpoint 2>/dev/null | grep -qx "${dir%/}"; then
            result+=("${dir_name}")
        fi
    done
}

# --- CHECK mode ---
if [[ "${MODE}" == "check" ]]; then
    echo "Checking service directories under: ${SERVICES_PATH}"
    echo ""

    missing=()
    collect_missing missing

    for name in "${missing[@]}"; do
        echo "NO DATASET: ${name}  (${SERVICES_PATH}/${name})"
    done

    echo ""
    if [[ ${#missing[@]} -eq 0 ]]; then
        echo "All service directories have a dedicated ZFS dataset."
    else
        echo "${#missing[@]} service director(y/ies) without a dedicated dataset."
        echo ""
        echo "Run with --fix to interactively create datasets:"
        echo "  sudo $0 --fix ${SERVICES_PATH}"
    fi
    exit 0
fi

# --- FIX mode ---
echo "=== ZFS Dataset Fix Wizard ==="
echo "Services path: ${SERVICES_PATH}"
echo ""

missing=()
collect_missing missing

if [[ ${#missing[@]} -eq 0 ]]; then
    echo "All service directories already have a dedicated ZFS dataset. Nothing to do."
    exit 0
fi

echo "The following ${#missing[@]} service(s) have no dedicated dataset:"
echo ""
for name in "${missing[@]}"; do
    echo "  - ${name}"
done

echo ""
read -r -p "Proceed with the fix workflow? [y/N] " confirm
if [[ "${confirm}" != [yY] ]]; then
    echo "Aborted."
    exit 0
fi

# --- Step 1: Stop Docker Compose projects ---
echo ""
echo "=== Step 1/4: Stopping Docker Compose projects ==="
for name in "${missing[@]}"; do
    compose_file="${SERVICES_PATH}/${name}/compose.yaml"
    if [[ -f "${compose_file}" ]]; then
        echo "  Stopping ${name}..."
        docker compose -f "${compose_file}" down --timeout 30 2>&1 | sed 's/^/    /'
    else
        echo "  Skipping ${name} (no compose.yaml found)"
    fi
done

# --- Step 2: Move dirs to -tmp ---
echo ""
echo "=== Step 2/4: Moving directories to temporary names ==="
for name in "${missing[@]}"; do
    src="${SERVICES_PATH}/${name}"
    dst="${SERVICES_PATH}/${name}-tmp"
    echo "  ${name}/ -> ${name}-tmp/"
    mv "${src}" "${dst}"
done

# --- Step 3: Wait for user to create datasets ---
echo ""
echo "=== Step 3/4: Create datasets now ==="
echo ""
echo "Go to the TrueNAS UI and create a dataset for each service listed below."
echo "The dataset mountpoint must match the original path exactly."
echo ""
echo "Datasets to create:"
for name in "${missing[@]}"; do
    echo "  ${SERVICES_PATH}/${name}"
done
echo ""
echo "Press ENTER when all datasets have been created..."
read -r

# Verify datasets were created
echo "Verifying datasets..."
not_created=()
for name in "${missing[@]}"; do
    if ! zfs list -H -o mountpoint 2>/dev/null | grep -qx "${SERVICES_PATH}/${name}"; then
        not_created+=("${name}")
    fi
done

if [[ ${#not_created[@]} -gt 0 ]]; then
    echo ""
    echo "WARNING: The following datasets were NOT detected:"
    for name in "${not_created[@]}"; do
        echo "  - ${name}  (expected mountpoint: ${SERVICES_PATH}/${name})"
    done
    echo ""
    read -r -p "Continue anyway? Data will be moved but may not be on a dataset. [y/N] " confirm
    if [[ "${confirm}" != [yY] ]]; then
        echo ""
        echo "Aborted. Your data is still in the -tmp directories."
        echo "To restore manually:  mv <name>-tmp <name>"
        exit 1
    fi
fi

# --- Step 4: Move contents back (including dotfiles) ---
echo ""
echo "=== Step 4/4: Moving contents back from temporary directories ==="
for name in "${missing[@]}"; do
    src="${SERVICES_PATH}/${name}-tmp"
    dst="${SERVICES_PATH}/${name}"

    # Ensure the target exists (dataset mount creates it, but just in case)
    mkdir -p "${dst}"

    echo "  ${name}-tmp/ -> ${name}/"

    # Move all files including dotfiles; use find to handle both cases
    # without relying on shell globbing options
    find "${src}" -mindepth 1 -maxdepth 1 -exec mv -t "${dst}" {} +

    # Remove the now-empty temp directory
    rmdir "${src}" 2>/dev/null || echo "    NOTE: ${name}-tmp/ not empty, leaving in place"
done

echo ""
echo "=== Done ==="
echo ""
echo "Don't forget to restart your services, e.g.:"
echo "  cd ${SERVICES_PATH}/.."
echo "  bash scripts/dccd.sh -a"
