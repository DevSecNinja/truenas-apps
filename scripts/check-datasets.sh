#!/usr/bin/env bash
# Check and fix service folders that lack a dedicated ZFS dataset.
# Run on the TrueNAS server: sudo bash scripts/check-datasets.sh /mnt/<pool>/apps/services
#
# Modes:
#   --check   (default) Report which service dirs have no dataset
#   --fix     Interactive guided workflow: stop containers, move dirs,
#             wait for dataset creation, move contents back

set -euo pipefail

_CHECK_DATASETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh disable=SC1091
. "${_CHECK_DATASETS_DIR}/lib/log.sh"
# shellcheck disable=SC2034
LOG_TAG="check-datasets"

# --- Require root ---
if [[ "${EUID}" -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)."
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
    log_info "Checking service directories under: ${SERVICES_PATH}"

    missing=()
    collect_missing missing

    for name in "${missing[@]}"; do
        log_warn "NO DATASET: ${name}  (${SERVICES_PATH}/${name})"
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_result "All service directories have a dedicated ZFS dataset."
    else
        log_result "${#missing[@]} service director(y/ies) without a dedicated dataset."
        log_hint "Run with --fix to interactively create datasets:"
        log_hint "  sudo $0 --fix ${SERVICES_PATH}"
    fi
    exit 0
fi

# --- FIX mode ---
log_banner "ZFS Dataset Fix Wizard"
log_info "Services path: ${SERVICES_PATH}"

missing=()
collect_missing missing

if [[ ${#missing[@]} -eq 0 ]]; then
    log_result "All service directories already have a dedicated ZFS dataset. Nothing to do."
    exit 0
fi

log_info "The following ${#missing[@]} service(s) have no dedicated dataset:"
for name in "${missing[@]}"; do
    log_info "  - ${name}"
done

read -r -p "Proceed with the fix workflow? [y/N] " confirm
if [[ "${confirm}" != [yY] ]]; then
    log_warn "Aborted."
    exit 0
fi

# --- Step 1: Stop Docker Compose projects ---
log_step "Step 1/4: Stopping Docker Compose projects"
for name in "${missing[@]}"; do
    compose_file="${SERVICES_PATH}/${name}/compose.yaml"
    if [[ -f "${compose_file}" ]]; then
        log_state "Stopping ${name}..."
        docker compose -f "${compose_file}" down --timeout 30 2>&1 | sed 's/^/    /'
    else
        log_warn "Skipping ${name} (no compose.yaml found)"
    fi
done

# --- Step 2: Move dirs to -tmp ---
log_step "Step 2/4: Moving directories to temporary names"
for name in "${missing[@]}"; do
    src="${SERVICES_PATH}/${name}"
    dst="${SERVICES_PATH}/${name}-tmp"
    log_state "${name}/ -> ${name}-tmp/"
    mv "${src}" "${dst}"
done

# --- Step 3: Wait for user to create datasets ---
log_step "Step 3/4: Create datasets now"
log_hint "Go to the TrueNAS UI and create a dataset for each service listed below."
log_hint "The dataset mountpoint must match the original path exactly."
log_info "Datasets to create:"
for name in "${missing[@]}"; do
    log_info "  ${SERVICES_PATH}/${name}"
done

read -r -p "Press ENTER when all datasets have been created..." _

# Verify datasets were created
log_state "Verifying datasets..."
not_created=()
for name in "${missing[@]}"; do
    if ! zfs list -H -o mountpoint 2>/dev/null | grep -qx "${SERVICES_PATH}/${name}"; then
        not_created+=("${name}")
    fi
done

if [[ ${#not_created[@]} -gt 0 ]]; then
    log_warn "The following datasets were NOT detected:"
    for name in "${not_created[@]}"; do
        log_warn "  - ${name}  (expected mountpoint: ${SERVICES_PATH}/${name})"
    done
    read -r -p "Continue anyway? Data will be moved but may not be on a dataset. [y/N] " confirm
    if [[ "${confirm}" != [yY] ]]; then
        log_error "Aborted. Your data is still in the -tmp directories."
        log_hint "To restore manually:  mv <name>-tmp <name>"
        exit 1
    fi
fi

# --- Step 4: Move contents back (including dotfiles) ---
log_step "Step 4/4: Moving contents back from temporary directories"
for name in "${missing[@]}"; do
    src="${SERVICES_PATH}/${name}-tmp"
    dst="${SERVICES_PATH}/${name}"

    # Ensure the target exists (dataset mount creates it, but just in case)
    mkdir -p "${dst}"

    log_state "${name}-tmp/ -> ${name}/"

    # Move all files including dotfiles; use find to handle both cases
    # without relying on shell globbing options
    find "${src}" -mindepth 1 -maxdepth 1 -exec mv -t "${dst}" {} +

    # Remove the now-empty temp directory
    rmdir "${src}" 2>/dev/null || log_warn "${name}-tmp/ not empty, leaving in place"
done

log_result "Done"
log_hint "Don't forget to restart your services, e.g.:"
log_hint "  cd ${SERVICES_PATH}/.."
log_hint "  bash scripts/dccd.sh -a"
