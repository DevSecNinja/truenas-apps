#!/bin/bash

# Keep the descriptor open across DCCD's git-update re-exec and recovery's child
# deployment. Closing it, rather than unlocking it, preserves the parent's lock.
dccd_acquire_lock() {
    command -v flock >/dev/null 2>&1 || {
        log_error "flock is required for deployment coordination"
        return 1
    }
    BASE_DIR="$(cd "${BASE_DIR}" && pwd -P)" || return 1
    local lock_file="${BASE_DIR}/.dccd.lock"
    if [ -L "${lock_file}" ]; then
        log_error "Refusing a symlink at ${lock_file}"
        return 1
    fi
    if [[ ! "${DCCD_LOCK_FD:-}" =~ ^[0-9]+$ ]] ||
        [[ ! "/proc/${BASHPID}/fd/${DCCD_LOCK_FD}" -ef "${lock_file}" ]]; then
        exec {DCCD_LOCK_FD}>>"${lock_file}" || return 1
    fi
    if ! flock --exclusive --nonblock "${DCCD_LOCK_FD}"; then
        log_error "Another deployment or recovery holds ${lock_file}; retry when it finishes"
        return 75
    fi
    export DCCD_LOCK_FD
}

dccd_check_maintenance() {
    local marker="${BASE_DIR}/.dccd-maintenance"
    local app=""
    if [ -e "${marker}" ] || [ -L "${marker}" ]; then
        if [ ! -f "${marker}" ] || [ -L "${marker}" ]; then
            log_error "Invalid recovery marker: ${marker}"
            return 1
        fi
        if ! IFS= read -r app <"${marker}"; then
            log_error "Empty recovery marker: ${marker}; investigate before resuming deployments"
            return 1
        fi
        if [[ "${app}" =~ ^[a-z][a-z0-9-]*$ ]] &&
            [ "${app}" = "${APP_FILTER:-}" ] &&
            [ "${app}" = "${DCCD_RECOVERY_APP:-}" ] &&
            [ -z "${REMOVE_APP:-}" ]; then
            return 0
        fi
        log_error "Deployments are paused for ${app:-an interrupted recovery}; rerun truenas-recover-app.sh for that app"
        return 75
    fi
}
