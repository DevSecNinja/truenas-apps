#!/bin/bash
# Quiesced, snapshot-protected recovery of one existing TrueNAS Custom App.
set -euo pipefail

_RECOVERY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/log.sh disable=SC1091
. "${_RECOVERY_SCRIPT_DIR}/lib/log.sh"
# shellcheck source=lib/deployment-lock.sh disable=SC1091
. "${_RECOVERY_SCRIPT_DIR}/lib/deployment-lock.sh"
# shellcheck disable=SC2034
LOG_TAG="app-recovery"

recovery_fail() {
    log_error "$1"
    exit 1
}

recovery_compose() {
    sudo docker compose --project-name "${RECOVERY_PROJECT}" \
        --file "${RECOVERY_COMPOSE}" "$@"
}

recovery_dccd() {
    bash "${BASE_DIR}/scripts/dccd.sh" -d "${BASE_DIR}" \
        -k "${BASE_DIR}/age.key" -t -f -a "${RECOVERY_APP}" \
        -w "${RECOVERY_WAIT_TIMEOUT}" "$@"
}

recovery_resolve_compose() {
    local versions="/mnt/.ix-apps/app_configs/${RECOVERY_APP}/versions"
    local version
    [ -d "${versions}" ] || recovery_fail "Existing TrueNAS Custom App not found: ${RECOVERY_APP}"
    version="$(find "${versions}" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
    RECOVERY_COMPOSE="${version}/templates/rendered/docker-compose.yaml"
    [ -n "${version}" ] && [ -f "${RECOVERY_COMPOSE}" ] ||
        recovery_fail "Rendered TrueNAS Compose file not found"
}

recovery_model() {
    # Retain only non-secret metadata. Never log or persist the rendered environment.
    recovery_compose config --format json | jq -ce '
        [.services | to_entries[] | select((.value.profiles // [] | length) == 0) |
         {name: .key, image: .value.image, build: (.value.build != null),
          oneshot: (.value.restart == "no"),
          replicas: (.value.deploy.replicas // 1),
          mounts: [.value.volumes[]? | select(.read_only != true) |
                   {type, source}]}] |
        if length > 0 then . else error("no active services") end'
}

recovery_validate_mounts() {
    local model="$1" source resolved sources
    if ! jq -e 'all(.[]; .build == false and (.image | type == "string") and .replicas == 1)' \
        <<<"${model}" >/dev/null; then
        recovery_fail "Recovery requires published images and one container per service"
    fi
    if ! jq -e 'all(.[].mounts[]; .type == "bind" or .type == "tmpfs")' <<<"${model}" >/dev/null; then
        recovery_fail "Named/anonymous volumes need an app-specific snapshot plan"
    fi
    sources="$(jq -r '.[].mounts[] | select(.type == "bind") | .source' <<<"${model}")"
    while IFS= read -r source; do
        [ -n "${source}" ] || continue
        resolved="$(readlink -m -- "${source}")"
        [[ "${resolved}" == "${RECOVERY_APP_DIR}" || "${resolved}" == "${RECOVERY_APP_DIR}/"* ]] ||
            recovery_fail "Writable mount is outside the app dataset: ${source}"
    done <<<"${sources}"
}

recovery_wait_backups() {
    local ids id service state
    local deadline=$((SECONDS + RECOVERY_WAIT_TIMEOUT))
    ids="$(sudo docker ps -q --filter "label=com.docker.compose.project=${RECOVERY_PROJECT}")"
    for id in ${ids}; do
        service="$(sudo docker inspect --format '{{index .Config.Labels "com.docker.compose.service"}}' "${id}")"
        [[ "${service}" == *-db-backup ]] || continue
        while :; do
            state="$(sudo docker inspect --format '{{.State.Status}}' "${id}")"
            [[ "${state}" == running || "${state}" == restarting ]] || break
            ((SECONDS < deadline)) || recovery_fail "Backup still active: ${service}; retry after it finishes"
            sleep 2
        done
    done
}

recovery_resolve_images() {
    local rows row image image_id resolved='[]'
    rows="$(jq -c '.[]' <<<"$1")"
    while IFS= read -r row; do
        image="$(jq -r '.image' <<<"${row}")"
        image_id="$(sudo docker image inspect --format '{{.Id}}' "${image}")"
        row="$(jq -c --arg image_id "${image_id}" '. + {image_id: $image_id}' <<<"${row}")"
        resolved="$(jq -c --argjson row "${row}" '. + [$row]' <<<"${resolved}")"
    done <<<"${rows}"
    printf '%s\n' "${resolved}"
}

recovery_check_containers() {
    local model="$1" deployment_epoch="$2"
    local row service oneshot ids id state exit_code health started actual expected rows metadata
    rows="$(jq -c '.[]' <<<"${model}")"
    while IFS= read -r row; do
        service="$(jq -r '.name' <<<"${row}")"
        oneshot="$(jq -r '.oneshot' <<<"${row}")"
        ids="$(recovery_compose ps --all --quiet "${service}")"
        [ -n "${ids}" ] && [[ "${ids}" != *$'\n'* ]] ||
            recovery_fail "Expected exactly one container for ${service}"
        id="${ids}"
        metadata="$(sudo docker inspect --format \
            '{{.State.Status}}|{{.State.ExitCode}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}|{{.State.StartedAt}}|{{.Image}}' "${id}")"
        IFS='|' read -r state exit_code health started actual <<<"${metadata}"
        expected="$(jq -er '.image_id | select(type == "string" and length > 0)' <<<"${row}")"
        [ "${actual}" = "${expected}" ] || recovery_fail "${service} is not using the pulled image"
        if [ "${oneshot}" = true ]; then
            [ "${state}" = exited ] && [ "${exit_code}" = 0 ] ||
                recovery_fail "${service} did not complete successfully"
        else
            [ "${state}" = running ] || recovery_fail "${service} is not running"
            case "${health}" in
            healthy) ;;
            none) log_warn "${service} has no healthcheck; only running state was verified" ;;
            *) recovery_fail "${service} is not healthy (${health})" ;;
            esac
        fi
        if [[ "${service}" == *-db-backup ]]; then
            started="$(date --date="${started}" +%s)"
            ((started >= deployment_epoch)) ||
                recovery_fail "${service} did not run during this recovery attempt"
        fi
    done <<<"${rows}"
}

recovery_check_meilisearch() {
    local model="$1" service id tasks status services
    local deadline=$((SECONDS + RECOVERY_WAIT_TIMEOUT))
    services="$(jq -r '.[] | select(.image |
        test("^((docker\\.io|index\\.docker\\.io|registry-1\\.docker\\.io)/)?getmeili/meilisearch([:@]|$)")) |
        .name' <<<"${model}")"
    while IFS= read -r service; do
        [ -n "${service}" ] || continue
        id="$(recovery_compose ps --all --quiet "${service}")"
        while :; do
            # Keep the master key inside the container and off curl's argv.
            tasks="$(sudo docker exec "${id}" sh -ec '
                printf "Authorization: Bearer %s\n" "${MEILI_MASTER_KEY:?}" |
                    curl --fail --silent --show-error --max-time 10 --header @- \
                        "http://127.0.0.1:7700/tasks?types=upgradeDatabase&limit=1"
            ')"
            status="$(jq -er '
                if (.results | type) != "array" then error("invalid task response")
                elif (.results | length) == 0 then "none"
                elif .results[0].type != "upgradeDatabase" then error("unexpected task type")
                else .results[0].status end' <<<"${tasks}")"
            case "${status}" in
            none | succeeded)
                log_result "${service}: latest migration status=${status}"
                break
                ;;
            enqueued | processing)
                ((SECONDS < deadline)) || recovery_fail "${service}: migration timed out; do not interrupt it"
                sleep 2
                ;;
            *) recovery_fail "${service}: latest migration status=${status}; inspect its task and logs" ;;
            esac
        done
    done <<<"${services}"
}

recovery_on_exit() {
    local status=$?
    if [ "${status}" -ne 0 ] && [ -f "${BASE_DIR}/.dccd-maintenance" ]; then
        log_error "Recovery incomplete. Deployments remain paused; no automatic rollback or snapshot deletion."
        log_hint "Retry: bash ${BASE_DIR}/scripts/truenas-recover-app.sh ${RECOVERY_APP}"
    fi
}

recovery_main() {
    local cleanup=0 snapshot model current_model mountpoint mounted datasets revision owner status
    local snapshots snapshot_exists=0 current_ids previous_images='[]' previous_image id resolved git_status current_revision
    local target_images saved_images
    local -a saved=()
    if [ "${1:-}" = "--help" ] || [ "$#" -eq 0 ]; then
        printf '%s\n' \
            "Usage: bash scripts/truenas-recover-app.sh <app>" \
            "       bash scripts/truenas-recover-app.sh --cleanup <app> <snapshot>" \
            "Run as the deployment user, not root. RECOVERY_WAIT_TIMEOUT defaults to 900 seconds." \
            "A failed run keeps deployments paused; rerun the same app to reuse its snapshot."
        return 0
    fi
    if [ "$1" = "--cleanup" ]; then
        cleanup=1
        shift
    fi
    if { [ "${cleanup}" -eq 0 ] && [ "$#" -ne 1 ]; } ||
        { [ "${cleanup}" -eq 1 ] && [ "$#" -ne 2 ]; }; then
        recovery_fail "Invalid arguments; use --help"
    fi
    RECOVERY_APP="$1"
    [[ "${RECOVERY_APP}" =~ ^[a-z][a-z0-9-]*$ ]] || recovery_fail "Invalid app name"
    local command
    for command in sudo zfs docker jq flock git readlink find sort tail date; do
        command -v "${command}" >/dev/null 2>&1 || recovery_fail "Required command not found: ${command}"
    done
    # shellcheck disable=SC2312
    [ "$(id -u)" -ne 0 ] || recovery_fail "Run as the deployment user, not root"
    RECOVERY_WAIT_TIMEOUT="${RECOVERY_WAIT_TIMEOUT:-900}"
    [[ "${RECOVERY_WAIT_TIMEOUT}" =~ ^[1-9][0-9]{0,4}$ ]] ||
        recovery_fail "RECOVERY_WAIT_TIMEOUT must be a positive integer of at most five digits"
    [ -z "${COMPOSE_PROFILES:-}" ] || recovery_fail "Profile-specific recovery needs an app-specific plan"
    BASE_DIR="$(cd "${_RECOVERY_SCRIPT_DIR}/.." && pwd -P)"
    RECOVERY_APP_DIR="${BASE_DIR}/services/${RECOVERY_APP}"
    RECOVERY_PROJECT="ix-${RECOVERY_APP}"
    [ -f "${RECOVERY_APP_DIR}/compose.yaml" ] || recovery_fail "Tracked Compose file not found"
    resolved="$(readlink -f "${RECOVERY_APP_DIR}")"
    [[ "${resolved}" == "${RECOVERY_APP_DIR}" ]] ||
        recovery_fail "The service directory must not be a symlink"
    dccd_acquire_lock
    sudo -v
    datasets="$(sudo zfs list -H -o name,mountpoint,mounted)"
    RECOVERY_DATASET=""
    while IFS=$'\t' read -r owner mountpoint mounted; do
        if [ "${mountpoint}" = "${RECOVERY_APP_DIR}" ] && [ "${mounted}" = yes ]; then
            [ -z "${RECOVERY_DATASET}" ] || recovery_fail "Multiple datasets report this mountpoint; investigate before recovery"
            RECOVERY_DATASET="${owner}"
        fi
    done <<<"${datasets}"
    [ -n "${RECOVERY_DATASET}" ] || recovery_fail "No dedicated ZFS dataset is mounted at ${RECOVERY_APP_DIR}"
    while IFS=$'\t' read -r owner mountpoint mounted; do
        if [ "${mounted}" = yes ] && [[ "${mountpoint}" == "${RECOVERY_APP_DIR}/"* ]] &&
            [[ "${owner}" != "${RECOVERY_DATASET}/"* ]]; then
            recovery_fail "Nested mount ${mountpoint} is not a child of ${RECOVERY_DATASET}"
        fi
    done <<<"${datasets}"

    if [ "${cleanup}" -eq 1 ]; then
        snapshot="$2"
        [[ "${snapshot}" == "${RECOVERY_DATASET}@pre-dccd-"* ]] &&
            [[ "${snapshot##*@}" =~ ^pre-dccd-[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]] ||
            recovery_fail "Snapshot is not a recovery snapshot of this app"
        [ ! -e "${BASE_DIR}/.dccd-maintenance" ] && [ ! -L "${BASE_DIR}/.dccd-maintenance" ] ||
            recovery_fail "Finish the pending recovery before cleanup"
        owner="$(sudo zfs get -H -o value org.truenas-apps:recovery-app "${snapshot}")"
        status="$(sudo zfs get -H -o value org.truenas-apps:recovery-status "${snapshot}")"
        [ "${owner}" = "${RECOVERY_APP}" ] && [ "${status}" = complete ] ||
            recovery_fail "Snapshot is not marked as a completed recovery for this app"
        sudo zfs destroy -r "${snapshot}"
        log_result "Deleted recovery snapshot ${snapshot} and matching child snapshots"
        return 0
    fi

    if [ -e "${BASE_DIR}/.dccd-maintenance" ] || [ -L "${BASE_DIR}/.dccd-maintenance" ]; then
        [ -f "${BASE_DIR}/.dccd-maintenance" ] && [ ! -L "${BASE_DIR}/.dccd-maintenance" ] ||
            recovery_fail "Invalid maintenance marker"
        mapfile -t saved <"${BASE_DIR}/.dccd-maintenance"
        [ "${#saved[@]}" -eq 2 ] && [ "${saved[0]}" = "${RECOVERY_APP}" ] ||
            recovery_fail "Another app has a pending recovery; finish it first"
        snapshot="${saved[1]}"
        [[ "${snapshot}" == "${RECOVERY_DATASET}@pre-dccd-"* ]] &&
            [[ "${snapshot##*@}" =~ ^pre-dccd-[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]] ||
            recovery_fail "Invalid snapshot in maintenance marker"
    else
        snapshot="${RECOVERY_DATASET}@pre-dccd-$(date -u +%Y%m%dT%H%M%SZ)-$$"
        (
            umask 077
            printf '%s\n%s\n' "${RECOVERY_APP}" "${snapshot}" >"${BASE_DIR}/.dccd-maintenance"
        )
    fi
    trap recovery_on_exit EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    export DCCD_RECOVERY_APP="${RECOVERY_APP}"
    git_status="$(git -C "${BASE_DIR}" status --porcelain)"
    [ -z "${git_status}" ] || recovery_fail "Commit or remove local changes before recovery"

    snapshots="$(sudo zfs list -H -t snapshot -o name -r "${RECOVERY_DATASET}")"
    while IFS= read -r owner; do
        if [ "${owner}" = "${snapshot}" ]; then snapshot_exists=1; fi
    done <<<"${snapshots}"
    if [ "${snapshot_exists}" -eq 1 ]; then
        owner="$(sudo zfs get -H -o value org.truenas-apps:recovery-app "${snapshot}")"
        [ "${owner}" = "${RECOVERY_APP}" ] || recovery_fail "Existing snapshot has the wrong owner"
        log_warn "Reusing ${snapshot}; no new snapshot will overwrite the original recovery point"
    else
        recovery_resolve_compose
        model="$(recovery_model)"
        recovery_validate_mounts "${model}"
        current_ids="$(sudo docker ps -aq --filter "label=com.docker.compose.project=${RECOVERY_PROJECT}")"
        if [ -n "${current_ids}" ]; then
            for id in ${current_ids}; do
                current_model="$(sudo docker inspect --format '{{json .Mounts}}' "${id}" |
                    jq -c '[{image:"running",build:false,replicas:1,mounts:
                        [.[] | select(.RW == true) | {type:.Type,source:.Source}]}]')"
                recovery_validate_mounts "${current_model}"
                previous_image="$(sudo docker inspect --format \
                    '{"service":{{json (index .Config.Labels "com.docker.compose.service")}},"reference":{{json .Config.Image}},"id":{{json .Image}}}' "${id}")"
                previous_images="$(jq -c --argjson image "${previous_image}" '. + [$image]' <<<"${previous_images}")"
            done
        fi
        recovery_wait_backups
        # Include orphaned services in the stop, not just today's Compose model.
        local ids
        ids="$(sudo docker ps -q --filter "label=com.docker.compose.project=${RECOVERY_PROJECT}")"
        for id in ${ids}; do sudo docker stop --time 60 "${id}"; done
        ids="$(sudo docker ps -q --filter "label=com.docker.compose.project=${RECOVERY_PROJECT}")"
        [ -z "${ids}" ] || recovery_fail "Project still has running containers; snapshot aborted"
        revision="$(git -C "${BASE_DIR}" rev-parse HEAD)"
        sudo zfs snapshot -r \
            -o "org.truenas-apps:recovery-app=${RECOVERY_APP}" \
            -o "org.truenas-apps:recovery-status=pending" \
            -o "org.truenas-apps:recovery-revision=${revision}" \
            -o "org.truenas-apps:recovery-images=${previous_images}" "${snapshot}"
        sudo zfs list -H -t snapshot -o name "${snapshot}"
        log_result "Protected recovery point: ${snapshot}"
    fi

    # Snapshot before syncing: preserve the existing config and decrypted secrets,
    # not just the database. Freeze the target revision before attempting deployment.
    revision="$(sudo zfs get -H -o value org.truenas-apps:recovery-target-revision "${snapshot}")"
    if [ "${revision}" = "-" ]; then
        recovery_dccd -D
    else
        current_revision="$(git -C "${BASE_DIR}" rev-parse HEAD)"
        [ "${revision}" = "${current_revision}" ] ||
            recovery_fail "Repository changed since the deployment attempt; review before resuming"
    fi
    recovery_resolve_compose
    model="$(recovery_model)"
    recovery_validate_mounts "${model}"
    recovery_compose pull
    model="$(recovery_resolve_images "${model}")"
    target_images="$(jq -c '[.[] | {name, image, image_id}] | sort_by(.name)' <<<"${model}")"
    if [ "${revision}" = "-" ]; then
        revision="$(git -C "${BASE_DIR}" rev-parse HEAD)"
        sudo zfs set "org.truenas-apps:recovery-target-images=${target_images}" "${snapshot}"
        sudo zfs set "org.truenas-apps:recovery-target-revision=${revision}" "${snapshot}"
    else
        saved_images="$(sudo zfs get -H -o value org.truenas-apps:recovery-target-images "${snapshot}")"
        [ "${saved_images}" = "${target_images}" ] ||
            recovery_fail "Target images changed since the deployment attempt; review before resuming"
    fi
    # Complete any migration already running after a previous timed-out attempt
    # before asking Compose to start the remaining services again.
    local running_model
    running_model="$(sudo docker ps --filter "label=com.docker.compose.project=${RECOVERY_PROJECT}" \
        --format '{{.Label "com.docker.compose.service"}}')"
    running_model="$(jq -c --arg running "${running_model}" \
        '[.[] | select(.name as $name | $running | split("\n") | index($name))]' <<<"${model}")"
    recovery_check_meilisearch "${running_model}"
    local deployment_epoch
    deployment_epoch="$(date +%s)"
    recovery_dccd -n -B
    recovery_check_meilisearch "${model}"
    recovery_check_containers "${model}" "${deployment_epoch}"
    sudo zfs set org.truenas-apps:recovery-status=complete "${snapshot}"
    rm -- "${BASE_DIR}/.dccd-maintenance"
    log_result "${RECOVERY_APP} recovered; scheduled deployments are no longer paused"
    log_hint "Snapshot retained. After checking application data, explicitly clean up with:"
    log_hint "bash ${BASE_DIR}/scripts/truenas-recover-app.sh --cleanup ${RECOVERY_APP} ${snapshot}"
}

if [[ "${RECOVERY_TESTING:-0}" != 1 ]]; then
    recovery_main "$@"
fi
