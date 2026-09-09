#!/bin/bash
# Provision host prerequisites for an app managed by this repository.
# Run on TrueNAS SCALE as root:
#   sudo bash scripts/truenas-prep-app.sh <app>

set -euo pipefail

_PREP_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh disable=SC1091
. "${_PREP_APP_DIR}/lib/log.sh"
# shellcheck disable=SC2034
LOG_TAG="truenas-prep"

ADMIN_USER="${TRUENAS_ADMIN_USER:-truenas_admin}"
REPO_ROOT="$(cd "${_PREP_APP_DIR}/.." && pwd -P)"

usage() {
    cat <<EOF
Usage: sudo bash scripts/truenas-prep-app.sh <app>

Supported apps:
EOF
    list_supported_apps

    cat <<EOF
Environment:
  TRUENAS_ADMIN_USER  Administrative user to add to app groups
                       (default: truenas_admin)
EOF
}

fail() {
    log_error "$1"
    exit 1
}

list_supported_apps() {
    local config_file="${REPO_ROOT}/truenas-apps.yaml"
    local app
    local apps

    if ! command -v yq >/dev/null 2>&1 || [ ! -f "${config_file}" ]; then
        printf '  (see truenas-apps.yaml)\n'
        return
    fi

    if ! apps="$(yq -r '.apps | keys | .[]' "${config_file}")"; then
        printf '  (unable to read truenas-apps.yaml)\n'
        return
    fi

    while IFS= read -r app; do
        printf '  %s\n' "${app}"
    done <<<"${apps}"
}

load_app_config() {
    local requested_app="$1"
    local config_file="${REPO_ROOT}/truenas-apps.yaml"
    local app_config

    [[ "${requested_app}" =~ ^[a-z][a-z0-9-]*$ ]] ||
        fail "Invalid app name: ${requested_app}"
    [ -f "${config_file}" ] ||
        fail "TrueNAS app manifest not found: ${config_file}"
    APP_NAME="${requested_app}"
    APP_NAME="${requested_app}"
    if ! app_config="$(
        yq -r \
            ".apps.\"${APP_NAME}\" | [.account_name, .account_id, .admin_group_member] | @tsv" \
            "${config_file}"
    )"; then
        fail "Unable to read TrueNAS app manifest: ${config_file}"
    fi
    IFS=$'\t' read -r ACCOUNT_NAME ACCOUNT_ID ADMIN_GROUP_MEMBER <<<"${app_config}"

    if [ "${ACCOUNT_NAME}" = "null" ] && [ "${ACCOUNT_ID}" = "null" ] &&
        [ "${ADMIN_GROUP_MEMBER}" = "null" ]; then
        usage >&2
        fail "Unsupported app: ${APP_NAME}"
    fi

    [ "${ACCOUNT_NAME}" = "svc-app-${APP_NAME}" ] ||
        fail "Invalid account_name for ${APP_NAME}: expected svc-app-${APP_NAME}"
    [[ "${ACCOUNT_ID}" =~ ^[0-9]+$ ]] ||
        fail "Invalid account_id for ${APP_NAME}: expected an integer"
    if ((ACCOUNT_ID < 3100 || ACCOUNT_ID > 3199)); then
        fail "Invalid account_id for ${APP_NAME}: expected a value from 3100 to 3199"
    fi
    case "${ADMIN_GROUP_MEMBER}" in
    true | false) ;;
    *) fail "Invalid admin_group_member for ${APP_NAME}: expected true or false" ;;
    esac
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

find_dataset_for_mountpoint() {
    local wanted_mountpoint="$1"
    local dataset=""
    local datasets
    local name
    local mountpoint

    datasets="$(zfs list -H -o name,mountpoint)"
    while IFS=$'\t' read -r name mountpoint; do
        if [ "${mountpoint}" = "${wanted_mountpoint}" ]; then
            dataset="${name}"
            break
        fi
    done <<<"${datasets}"

    printf '%s' "${dataset}"
}

load_accounts() {
    GROUPS_JSON="$(midclt call group.query)"
    USERS_JSON="$(midclt call user.query)"
}

ensure_group() {
    local group_by_name
    local group_by_gid
    local existing_gid
    local existing_group_name
    local payload

    group_by_name="$(
        jq -c --arg name "${ACCOUNT_NAME}" \
            'first(.[] | select(.local == true and .name == $name)) // empty' \
            <<<"${GROUPS_JSON}"
    )"
    group_by_gid="$(
        jq -c --argjson gid "${ACCOUNT_ID}" \
            'first(.[] | select(.local == true and .gid == $gid)) // empty' \
            <<<"${GROUPS_JSON}"
    )"

    if [ -n "${group_by_name}" ]; then
        existing_gid="$(jq -r '.gid' <<<"${group_by_name}")"
        if [ "${existing_gid}" != "${ACCOUNT_ID}" ]; then
            fail "Group ${ACCOUNT_NAME} exists with the wrong GID"
        fi
        GROUP_API_ID="$(jq -r '.id' <<<"${group_by_name}")"
        log_info "Group ${ACCOUNT_NAME} already exists with GID ${ACCOUNT_ID}"
        return
    fi

    if [ -n "${group_by_gid}" ]; then
        existing_group_name="$(jq -r '.name' <<<"${group_by_gid}")"
        fail "GID ${ACCOUNT_ID} is already assigned to group ${existing_group_name}"
    fi

    payload="$(
        jq -cn \
            --arg name "${ACCOUNT_NAME}" \
            --argjson gid "${ACCOUNT_ID}" \
            '{name: $name, gid: $gid, smb: false}'
    )"
    midclt call group.create "${payload}" >/dev/null
    GROUPS_JSON="$(midclt call group.query)"
    GROUP_API_ID="$(
        jq -r --arg name "${ACCOUNT_NAME}" \
            'first(.[] | select(.local == true and .name == $name)) | .id' \
            <<<"${GROUPS_JSON}"
    )"
    [ "${GROUP_API_ID}" != "null" ] || fail "TrueNAS did not return the created group"
    log_state "Created group ${ACCOUNT_NAME} with GID ${ACCOUNT_ID}"
}

ensure_user() {
    local user_by_name
    local user_by_uid
    local existing_uid
    local existing_username
    local payload
    local primary_group_id

    user_by_name="$(
        jq -c --arg name "${ACCOUNT_NAME}" \
            'first(.[] | select(.local == true and .username == $name)) // empty' \
            <<<"${USERS_JSON}"
    )"
    user_by_uid="$(
        jq -c --argjson uid "${ACCOUNT_ID}" \
            'first(.[] | select(.local == true and .uid == $uid)) // empty' \
            <<<"${USERS_JSON}"
    )"

    if [ -n "${user_by_name}" ]; then
        existing_uid="$(jq -r '.uid' <<<"${user_by_name}")"
        if [ "${existing_uid}" != "${ACCOUNT_ID}" ]; then
            fail "User ${ACCOUNT_NAME} exists with the wrong UID"
        fi
        primary_group_id="$(jq -r '.group.id' <<<"${user_by_name}")"
        if [ "${primary_group_id}" != "${GROUP_API_ID}" ]; then
            fail "User ${ACCOUNT_NAME} has the wrong primary group"
        fi
        log_info "User ${ACCOUNT_NAME} already exists with UID ${ACCOUNT_ID}"
        return
    fi

    if [ -n "${user_by_uid}" ]; then
        existing_username="$(jq -r '.username' <<<"${user_by_uid}")"
        fail "UID ${ACCOUNT_ID} is already assigned to user ${existing_username}"
    fi

    payload="$(
        jq -cn \
            --arg username "${ACCOUNT_NAME}" \
            --arg full_name "Service account for ${APP_NAME}" \
            --argjson uid "${ACCOUNT_ID}" \
            --argjson group "${GROUP_API_ID}" \
            '{
                username: $username,
                full_name: $full_name,
                uid: $uid,
                group: $group,
                group_create: false,
                home: "/var/empty",
                shell: "/usr/sbin/nologin",
                smb: false,
                password_disabled: true
            }'
    )"
    midclt call user.create "${payload}" >/dev/null
    USERS_JSON="$(midclt call user.query)"
    log_state "Created user ${ACCOUNT_NAME} with UID ${ACCOUNT_ID}"
}

ensure_admin_membership() {
    local admin
    local admin_id
    local groups
    local payload

    [ "${ADMIN_GROUP_MEMBER}" = true ] || return

    admin="$(
        jq -c --arg name "${ADMIN_USER}" \
            'first(.[] | select(.local == true and .username == $name)) // empty' \
            <<<"${USERS_JSON}"
    )"
    [ -n "${admin}" ] || fail "Local administrative user not found: ${ADMIN_USER}"

    if jq -e --argjson group_id "${GROUP_API_ID}" \
        '.groups | index($group_id) != null' <<<"${admin}" >/dev/null; then
        log_info "${ADMIN_USER} is already an auxiliary member of ${ACCOUNT_NAME}"
        return
    fi

    admin_id="$(jq -r '.id' <<<"${admin}")"
    groups="$(
        jq -c --argjson group_id "${GROUP_API_ID}" \
            '.groups + [$group_id] | unique' <<<"${admin}"
    )"
    payload="$(jq -cn --argjson groups "${groups}" '{groups: $groups}')"
    midclt call user.update "${admin_id}" "${payload}" >/dev/null
    USERS_JSON="$(midclt call user.query)"
    log_state "Added ${ADMIN_USER} to ${ACCOUNT_NAME}"
}

check_app_running() {
    local containers

    APP_RUNNING=false
    command -v docker >/dev/null 2>&1 || return
    containers="$(docker ps --quiet --filter "label=com.docker.compose.project=${APP_NAME}")"
    if [ -n "${containers}" ]; then
        APP_RUNNING=true
    fi
}

restore_staged_directory() {
    local staged_path="$1"
    local target_path="$2"

    if [ -e "${staged_path}" ] && [ ! -e "${target_path}" ]; then
        mv "${staged_path}" "${target_path}"
    fi
}

ensure_dataset() {
    local services_path="${REPO_ROOT}/services"
    local services_dataset
    local app_dataset
    local app_path="${services_path}/${APP_NAME}"
    local staged_path="${app_path}.truenas-prep.$$"
    local dataset_payload

    services_dataset="$(find_dataset_for_mountpoint "${services_path}")"
    [ -n "${services_dataset}" ] ||
        fail "${services_path} must be a mounted ZFS dataset before preparing apps"

    app_dataset="${services_dataset}/${APP_NAME}"
    if zfs list -H -o name "${app_dataset}" >/dev/null 2>&1; then
        log_info "Dataset ${app_dataset} already exists"
    else
        check_app_running
        if [ "${APP_RUNNING}" = true ]; then
            fail "App ${APP_NAME} is running; stop it before creating its dataset"
        fi
        [ ! -e "${staged_path}" ] || fail "Temporary path already exists: ${staged_path}"

        if [ -e "${app_path}" ]; then
            mv "${app_path}" "${staged_path}"
            log_state "Staged existing ${APP_NAME} files outside the dataset mountpoint"
        fi

        dataset_payload="$(jq -cn --arg name "${app_dataset}" '{name: $name}')"
        if ! midclt call pool.dataset.create "${dataset_payload}" >/dev/null; then
            restore_staged_directory "${staged_path}" "${app_path}"
            fail "Failed to create dataset ${app_dataset}; restored the service directory"
        fi
        log_state "Created dataset ${app_dataset}"

        if [ -e "${staged_path}" ]; then
            if ! find "${staged_path}" -mindepth 1 -maxdepth 1 -exec mv -t "${app_path}" {} +; then
                fail "Dataset created, but restoring files failed; recover them from ${staged_path}"
            fi
            rmdir "${staged_path}"
            log_state "Restored ${APP_NAME} files into the new dataset"
        fi
    fi

    chown "${ADMIN_USER}:${ADMIN_USER}" "${app_path}"
    chmod 0770 "${app_path}"
    log_state "Set ${app_path} ownership to ${ADMIN_USER}:${ADMIN_USER} with mode 770"
}

main() {
    if [ "${EUID}" -ne 0 ]; then
        fail "This script must be run as root (use sudo)"
    fi
    if [ "$#" -ne 1 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        usage
        [ "$#" -eq 1 ] && return 0
        return 1
    fi

    require_command jq
    require_command yq
    require_command midclt
    require_command zfs
    load_app_config "$1"

    [ -d "${REPO_ROOT}/services/${APP_NAME}" ] ||
        fail "Service directory not found: ${REPO_ROOT}/services/${APP_NAME}"

    log_banner "Preparing ${APP_NAME} on TrueNAS"
    load_accounts
    ensure_group
    ensure_user
    ensure_admin_membership
    ensure_dataset
    log_result "${APP_NAME} host prerequisites are ready"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
