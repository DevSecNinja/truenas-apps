#!/bin/bash
# Source: https://github.com/loganmarchione/dccd/blob/d5aef3f684e5f63e8ec348652c6dc24e7447336c/dccd.sh
# Usage in TrueNAS Scale:
#   Command: bash /mnt/vm-pool/apps/scripts/dccd.sh -d /mnt/vm-pool/apps -x shared -t -f
#   Run As User: truenas_admin (requires passwordless sudo for /usr/bin/docker)
#   Unselect 'Hide Standard Output' and 'Hide Standard Error'

set -euo pipefail

# Guard: refuse to run as root to prevent git/file ownership issues
# shellcheck disable=SC2312  # id -u always succeeds
if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Do not run this script as root. Run as truenas_admin instead." >&2
    echo "       Ensure passwordless sudo is configured for docker:" >&2
    echo "       truenas_admin ALL=(ALL) NOPASSWD: /usr/bin/docker" >&2
    exit 1
fi

########################################
# Default configuration values
########################################
BASE_DIR=""                                   # Initialize empty variable
PRUNE=0                                       # Default prune setting
GRACEFUL=0                                    # Default graceful setting
TMPRESTART="/tmp/dccd.restart"                # Default log file for graceful setting
REMOTE_BRANCH="main"                          # Default remote branch name
COMPOSE_OPTS=""                               # Additional options for docker compose
EXCLUDE=""                                    # Exclude pattern for directories
TRUENAS=0                                     # TrueNAS Scale mode
TRUENAS_APPS_BASE="/mnt/.ix-apps/app_configs" # Base path for TrueNAS app configs
DECRYPT_ONLY=0                                # Decrypt SOPS files and exit (skip deploy)
FORCE=0                                       # Force redeploy, skip hash check
NO_PULL=0                                     # Skip pulling images (for local testing)
APP_FILTER=""                                 # Only deploy this specific app (empty = all)
SERVER_NAME=""                                # Server name from servers.yaml (empty = deploy all)
SERVER_APPS=()                                # Apps assigned to the server (populated by parse_server_apps)
WAIT_TIMEOUT=120                              # Timeout in seconds for --wait (0 = no timeout)
GATUS_URL=""                                  # Gatus instance URL for CD status reporting (e.g., https://status.example.com)
GATUS_DNS_SERVER=""                           # DNS server for Gatus curl calls (e.g., 192.168.1.1 — overrides system resolver just for Gatus)
# GATUS_URL, GATUS_CD_TOKEN, and GATUS_DNS_SERVER can also be sourced from services/gatus/.env (already decrypted on disk)
# GATUS_DNS_SERVER falls back to IP_DNS_SERVER_1 from the same .env file if -r is not supplied
_DEPLOY_ERRORS=0       # Count of deployment failures (non-fatal errors logged during deploy)
_DEPLOY_ATTEMPTED=0    # Count of deployment attempts
_DEPLOY_FAILED_APPS=() # Names of failed apps
# renovate: datasource=github-releases depName=getsops/sops
SOPS_VERSION="v3.12.2" # SOPS version for secret decryption
SOPS_INSTALL_DIR=""    # Directory to install SOPS binary (default: <BASE_DIR>/bin)
SOPS_AGE_KEY_FILE=""   # Path to Age private key file for SOPS decryption (default: <BASE_DIR>/age.key)
SOPS_BIN=""            # Path to SOPS binary (set by ensure_sops)

########################################
# Functions
########################################

log_message() {
    local message="$1"
    local formatted
    formatted="$(date +'%Y-%m-%d %H:%M:%S') - ${message}"

    # Colorize output when writing to a terminal
    if [ -t 1 ]; then
        local color=""
        local reset=$'\033[0m'
        case "${message}" in
        ERROR:*) color=$'\033[1;31m' ;;   # bold red
        WARNING:*) color=$'\033[1;33m' ;; # bold yellow
        STATE:*) color=$'\033[36m' ;;     # cyan
        RESULT:*) color=$'\033[32m' ;;    # green
        *) color="" ;;                    # default
        esac
        if [ -n "${color}" ]; then
            echo "${color}${formatted}${reset}"
        else
            echo "${formatted}"
        fi
    else
        echo "${formatted}"
    fi
    logger -t dccd "${message}"
}

# Non-root execution: always use sudo for docker commands
SUDO="sudo"

ensure_sops() {
    mkdir -p "${SOPS_INSTALL_DIR}"
    local sops_bin="${SOPS_INSTALL_DIR}/sops-${SOPS_VERSION}"
    if [ -x "${sops_bin}" ]; then
        SOPS_BIN="${sops_bin}"
        return
    fi

    local arch
    arch=$(uname -m)
    case "${arch}" in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *)
        log_message "ERROR: Unsupported architecture: ${arch}"
        exit 1
        ;;
    esac

    local binary_name="sops-${SOPS_VERSION}.linux.${arch}"
    local url="https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/${binary_name}"
    local checksums_url="https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.checksums.txt"
    local tmp_bin="/tmp/sops-${SOPS_VERSION}"
    local tmp_checksums="/tmp/sops-${SOPS_VERSION}.checksums.txt"

    log_message "STATE: Downloading SOPS ${SOPS_VERSION}..."
    if ! curl -fsSL -o "${tmp_bin}" "${url}"; then
        log_message "ERROR: Failed to download SOPS from ${url}"
        rm -f "${tmp_bin}"
        exit 1
    fi

    log_message "STATE: Verifying SOPS ${SOPS_VERSION} checksum..."
    if ! curl -fsSL -o "${tmp_checksums}" "${checksums_url}"; then
        log_message "ERROR: Failed to download SOPS checksums from ${checksums_url}"
        rm -f "${tmp_bin}" "${tmp_checksums}"
        exit 1
    fi

    local expected_hash
    expected_hash=$(grep "${binary_name}$" "${tmp_checksums}" | awk '{print $1}')
    rm -f "${tmp_checksums}"

    if [ -z "${expected_hash}" ]; then
        log_message "ERROR: Could not find checksum for ${binary_name} in checksums file"
        rm -f "${tmp_bin}"
        exit 1
    fi

    local actual_hash
    actual_hash=$(sha256sum "${tmp_bin}" | awk '{print $1}')

    if [ "${expected_hash}" != "${actual_hash}" ]; then
        log_message "ERROR: SOPS checksum mismatch for ${binary_name} (expected: ${expected_hash}, got: ${actual_hash})"
        rm -f "${tmp_bin}"
        exit 1
    fi

    log_message "INFO:  SOPS ${SOPS_VERSION} checksum verified"

    if ! ${SUDO} mv "${tmp_bin}" "${sops_bin}"; then
        log_message "ERROR: Failed to move SOPS binary to ${sops_bin} (permission denied?)"
        exit 1
    fi
    if ! ${SUDO} chmod +x "${sops_bin}"; then
        log_message "ERROR: Failed to make ${sops_bin} executable"
        exit 1
    fi
    SOPS_BIN="${sops_bin}"
    log_message "INFO:  SOPS ${SOPS_VERSION} installed to ${sops_bin}"
}

# Parse the apps assigned to a server from servers.yaml.
# Populates the global SERVER_APPS array.
# Requires yq on PATH.
parse_server_apps() {
    if ! command -v yq >/dev/null 2>&1; then
        log_message "ERROR: yq is required for server mode (-S) but not found on PATH"
        log_message "ERROR: Install yq: https://github.com/mikefarah/yq or run 'mise install'"
        exit 1
    fi

    local servers_yaml="${BASE_DIR}/servers.yaml"
    if [ ! -f "${servers_yaml}" ]; then
        log_message "ERROR: servers.yaml not found at ${servers_yaml}"
        exit 1
    fi

    # Validate the server name exists in servers.yaml
    local server_exists
    server_exists=$(yq -r ".servers.\"${SERVER_NAME}\" // \"\"" "${servers_yaml}")
    if [ -z "${server_exists}" ] || [ "${server_exists}" = "null" ]; then
        log_message "ERROR: Server '${SERVER_NAME}' not found in ${servers_yaml}"
        local available
        available=$(yq -r '.servers | keys | .[]' "${servers_yaml}" | paste -sd', ') || true
        log_message "ERROR: Available servers: ${available}"
        exit 1
    fi

    # Read apps into array (if the server has an explicit apps list)
    local has_apps
    has_apps=$(yq -r ".servers.\"${SERVER_NAME}\" | has(\"apps\")" "${servers_yaml}")
    if [ "${has_apps}" != "true" ]; then
        log_message "INFO:  Server '${SERVER_NAME}' has no apps list — deploying all apps"
        return
    fi

    local app_list
    app_list=$(yq -r ".servers.\"${SERVER_NAME}\".apps[]" "${servers_yaml}")
    if [ -z "${app_list}" ]; then
        log_message "ERROR: Server '${SERVER_NAME}' has an empty apps list in ${servers_yaml}"
        exit 1
    fi

    while IFS= read -r app; do
        if [ ! -d "${BASE_DIR}/services/${app}" ]; then
            log_message "ERROR: App '${app}' listed for server '${SERVER_NAME}' but services/${app}/ does not exist"
            exit 1
        fi
        SERVER_APPS+=("${app}")
    done <<<"${app_list}"

    log_message "INFO:  Server '${SERVER_NAME}' has ${#SERVER_APPS[@]} app(s): ${SERVER_APPS[*]}"
}

decrypt_sops_files() {
    local src_dir="${BASE_DIR}/services"

    if [ ! -d "${src_dir}" ]; then
        return
    fi

    local sops_files
    if [ "${#SERVER_APPS[@]}" -gt 0 ]; then
        # Server mode: only decrypt SOPS files for apps assigned to this server
        sops_files=""
        for app in "${SERVER_APPS[@]}"; do
            local app_dir="${src_dir}/${app}"
            if [ -d "${app_dir}" ]; then
                local found
                found=$(find "${app_dir}" \( -name config -o -name data -o -name backups \) -prune -o -name '*.sops.env' -type f -print)
                if [ -n "${found}" ]; then
                    if [ -n "${sops_files}" ]; then
                        sops_files="${sops_files}"$'\n'"${found}"
                    else
                        sops_files="${found}"
                    fi
                fi
            fi
        done
    else
        sops_files=$(find "${src_dir}" \( -name config -o -name data -o -name backups \) -prune -o -name '*.sops.env' -type f -print)
    fi

    if [ -z "${sops_files}" ]; then
        log_message "INFO:  No *.sops.env files found, skipping decryption"
        return
    fi

    if [ -z "${SOPS_AGE_KEY_FILE}" ]; then
        log_message "ERROR: SOPS_AGE_KEY_FILE is not set; use -k to specify the Age private key file"
        exit 1
    fi

    if [ ! -f "${SOPS_AGE_KEY_FILE}" ]; then
        log_message "ERROR: SOPS Age key file not found: ${SOPS_AGE_KEY_FILE}"
        exit 1
    fi

    export SOPS_AGE_KEY_FILE

    ensure_sops

    local count=0
    while IFS= read -r sops_file; do
        local dir sops_basename
        dir=$(dirname "${sops_file}")
        sops_basename=$(basename "${sops_file}")

        # Per-server secret file handling:
        #   secret.sops.env            → base secrets (all servers without a per-server file)
        #   secret.<server>.sops.env   → server-specific secrets (credential isolation)
        if [ -n "${SERVER_NAME}" ]; then
            # Server mode: select the right secret file per app
            if [ "${sops_basename}" != "secret.sops.env" ] && [ "${sops_basename}" != "secret.${SERVER_NAME}.sops.env" ]; then
                # Skip other servers' secret files (can't decrypt with this server's key)
                log_message "INFO:  Skipping ${sops_basename} (not for server ${SERVER_NAME})"
                continue
            elif [ "${sops_basename}" = "secret.sops.env" ]; then
                local server_specific="${dir}/secret.${SERVER_NAME}.sops.env"
                if [ -f "${server_specific}" ]; then
                    # Skip base when server-specific exists (credential isolation)
                    log_message "INFO:  Skipping base secret.sops.env for $(basename "${dir}") (using server-specific file)"
                    continue
                fi
            fi
        else
            # Non-server mode: skip server-specific files (anything not named secret.sops.env)
            if [ "${sops_basename}" != "secret.sops.env" ]; then
                continue
            fi
        fi

        # All secret files (base and server-specific) decrypt to .env so
        # compose env_file references work without changes.
        local secret_env="${dir}/.env"

        log_message "STATE: Decrypting $(basename "${dir}")/${sops_basename}"
        if "${SOPS_BIN}" -d "${sops_file}" >"${secret_env}"; then
            chmod 600 "${secret_env}"
            count=$((count + 1))
        else
            log_message "ERROR: Failed to decrypt ${sops_file}"
            exit 1
        fi
    done <<<"${sops_files}"

    log_message "INFO:  Decrypted ${count} secret file(s)"
}

# Returns sorted lines of "<service>=<image-reference>" for all containers in a compose project.
# Uses docker inspect on container IDs for reliable image info (including digest).
# Includes stopped/exited containers (-a) so one-shot services (e.g. backup sidecars) are
# captured in the "before" snapshot and not falsely reported as "new".
get_project_image_info() {
    local project_name="$1"
    ${SUDO} docker ps -aq \
        --filter "label=com.docker.compose.project=${project_name}" \
        2>/dev/null |
        xargs -r "${SUDO}" docker inspect \
            --format '{{index .Config.Labels "com.docker.compose.service"}}={{.Config.Image}}' \
            2>/dev/null |
        sort
}

# Log image changes between two snapshots captured by get_project_image_info
log_image_changes() {
    local app_name="$1"
    local before="$2"
    local after="$3"

    if [ -z "${before}" ] && [ -z "${after}" ]; then
        return
    fi

    local sep="========================================"
    log_message "${sep}"

    if [ -z "${before}" ]; then
        log_message "RESULT: ${app_name}: Initial deployment:"
        while IFS= read -r line; do
            local svc="${line%%=*}"
            local img="${line#*=}"
            log_message "RESULT:   ${svc}: ${img}"
        done <<<"${after}"
        log_message "${sep}"
        return
    fi

    if [ "${before}" = "${after}" ]; then
        log_message "RESULT: ${app_name}: No updates (images unchanged)"
        log_message "${sep}"
        return
    fi

    log_message "RESULT: ${app_name}: Image changes detected!"
    while IFS= read -r after_line; do
        local svc="${after_line%%=*}"
        local after_img="${after_line#*=}"
        local before_line
        before_line=$(echo "${before}" | grep "^${svc}=" | head -1) || true
        local before_img="${before_line#*=}"
        if [ -z "${before_img}" ]; then
            log_message "RESULT:   ${svc}: new -> ${after_img}"
        elif [ "${before_img}" = "${after_img}" ]; then
            log_message "RESULT:   ${svc}: unchanged (${after_img})"
        else
            log_message "RESULT:   ${svc}: UPDATED"
            log_message "RESULT:     from: ${before_img}"
            log_message "RESULT:     to:   ${after_img}"
        fi
    done <<<"${after}"
    log_message "${sep}"
}

redeploy_truenas_apps() {
    local src_dir="${BASE_DIR}/services"

    if [ ! -d "${src_dir}" ]; then
        log_message "ERROR: Source directory ${src_dir} does not exist, exiting..."
        exit 1
    fi

    for app_dir in "${src_dir}"/*/; do
        local app_name
        app_name=$(basename "${app_dir}")

        # TrueNAS does not allow underscores in app names. Strip leading
        # underscores so directory names like _bootstrap map to the TrueNAS
        # app name "bootstrap" while preserving the sort-first behaviour.
        local truenas_app_name="${app_name#_}"
        local project_name="ix-${truenas_app_name}"
        local app_config_dir="${TRUENAS_APPS_BASE}/${truenas_app_name}/versions"

        # If APP_FILTER is set, only deploy the matching app
        if [ -n "${APP_FILTER}" ] && [ "${app_name}" != "${APP_FILTER}" ]; then
            continue
        fi

        # If EXCLUDE is set and the app matches, skip it
        if [ -n "${EXCLUDE}" ] && [[ "${app_name}" == *"${EXCLUDE}"* ]]; then
            log_message "STATE: Skipping excluded app '${app_name}'"
            continue
        fi

        if [ ! -d "${app_config_dir}" ]; then
            log_message "ERROR: TrueNAS app config directory not found: ${app_config_dir}, skipping..."
            continue
        fi

        # Auto-detect the version directory (use the latest/only version)
        local version_dir
        version_dir=$(find "${app_config_dir}" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)

        if [ -z "${version_dir}" ]; then
            log_message "ERROR: No version directory found in ${app_config_dir}, skipping..."
            continue
        fi

        local rendered_dir="${version_dir}/templates/rendered"
        local compose_file="${rendered_dir}/docker-compose.yaml"

        if [ ! -f "${compose_file}" ]; then
            log_message "ERROR: Compose file not found: ${compose_file}, skipping..."
            continue
        fi

        local version
        version=$(basename "${version_dir}")

        # Validate the compose file before touching any running containers
        if ! ${SUDO} docker compose --project-name "${project_name}" --file "${compose_file}" config --quiet 2>/dev/null; then
            log_message "WARNING: ${app_name}: Skipping deployment — compose config validation failed"
            continue
        fi

        log_message "STATE: Deploying TrueNAS app ${app_name} (version ${version}, project ${project_name})"
        _DEPLOY_ATTEMPTED=$((_DEPLOY_ATTEMPTED + 1))

        # Capture image state before pulling so we can report what changed
        local img_before
        # shellcheck disable=SC2310  # || true is intentional; function may fail when no containers exist
        img_before=$(get_project_image_info "${project_name}") || true

        # Pull images (unless NO_PULL is set)
        if [ "${NO_PULL}" -eq 0 ]; then
            log_message "STATE: Pulling images for ${app_name}"
            ${SUDO} docker compose \
                --project-name "${project_name}" \
                --file "${compose_file}" \
                pull
        else
            log_message "STATE: Skipping image pull for ${app_name} (no-pull mode)"
        fi

        # Deploy
        log_message "STATE: Starting containers for ${app_name}"
        if [[ "${project_name}" == *bootstrap* ]]; then
            # One-shot project: run in foreground and abort when the container exits.
            # --abort-on-container-exit is incompatible with -d, which is fine — we
            # want to block until the init work is done before deploying later apps.
            log_message "INFO:  ${app_name} output suppressed — check 'sudo docker compose --project-name ${project_name} logs' if needed"
            if ! ${SUDO} docker compose \
                --project-name "${project_name}" \
                --file "${compose_file}" \
                up \
                --build \
                --abort-on-container-exit \
                >/dev/null 2>&1; then
                log_message "ERROR: ${app_name} one-shot container failed - check 'sudo docker compose --project-name ${project_name} logs' for details"
                _DEPLOY_ERRORS=$((_DEPLOY_ERRORS + 1))
                _DEPLOY_FAILED_APPS+=("${app_name}")
            fi
        else
            if ! ${SUDO} docker compose \
                --project-name "${project_name}" \
                --file "${compose_file}" \
                up \
                -d \
                --build \
                --wait \
                --wait-timeout "${WAIT_TIMEOUT}"; then
                log_message "ERROR: ${app_name} failed to become healthy within ${WAIT_TIMEOUT}s - check 'sudo docker compose --project-name ${project_name} logs' for details"
                _DEPLOY_ERRORS=$((_DEPLOY_ERRORS + 1))
                _DEPLOY_FAILED_APPS+=("${app_name}")
            fi
        fi

        # Report which images changed (or not)
        local img_after
        # shellcheck disable=SC2310  # || true is intentional; function may fail when no containers exist
        img_after=$(get_project_image_info "${project_name}") || true
        log_image_changes "${app_name}" "${img_before}" "${img_after}"
    done
}

update_compose_files() {
    local dir="$1"

    cd "${dir}" || {
        log_message "ERROR: Directory doesn't exist, exiting..."
        exit 127
    }

    # Make sure we're in a git repo
    if [ ! -d .git ]; then
        log_message "ERROR: Directory is not a git repository, exiting..."
        exit 1
    else
        log_message "INFO:  Git repository found!"
    fi

    local SHOULD_DEPLOY=0

    if [ "${NO_PULL}" -eq 1 ]; then
        log_message "STATE: No-pull mode enabled, skipping git sync..."
        SHOULD_DEPLOY=1
    else
        # Rewrite SSH remote URLs to HTTPS so fetch/pull works without SSH keys (for public repos in cron)
        # Allow root to operate on non-root-owned repos (safe.directory)
        # Ignore file permission changes (init containers chown/chmod volumes, which should not dirty the working tree)
        GIT_OPTS=(-c "url.https://github.com/.insteadOf=git@github.com:" -c "safe.directory=${dir}" -c "core.filemode=false")

        # Pre-flight: detect .git/ files not owned by the current user (e.g. FETCH_HEAD
        # created by a previous root run). git fetch will fail to write to these files.
        local bad_git_files current_user
        current_user=$(whoami) || true
        bad_git_files=$(find "${dir}/.git" -maxdepth 2 ! -user "$(id -u)" -print 2>/dev/null) || true
        if [ -n "${bad_git_files}" ]; then
            log_message "ERROR: .git/ contains files not owned by the current user (${current_user}):"
            local file_owner
            while IFS= read -r f; do
                file_owner=$(stat -c '%U' "${f}" 2>/dev/null) || file_owner="unknown"
                log_message "ERROR:   ${f}  (owner: ${file_owner})"
            done <<<"${bad_git_files}"
            log_message "ERROR: Fix with: sudo chown -R ${current_user} ${dir}/.git"
            exit 1
        fi

        # Pre-flight: detect git-tracked files not owned by the current user.
        # Init containers must never chown ./config (git-tracked) — but if one
        # does, git pull fails with "unable to unlink old '...': Permission denied".
        # Skip ./data and ./backups (runtime dirs legitimately owned by app UIDs).
        local bad_tracked_files
        bad_tracked_files=$(git "${GIT_OPTS[@]}" ls-files -z |
            xargs -0 -I{} find "${dir}/{}" -maxdepth 0 ! -user "$(id -u)" -print 2>/dev/null |
            grep -v '/data/' | grep -v '/backups/') || true
        if [ -n "${bad_tracked_files}" ]; then
            log_message "ERROR: Git-tracked files not owned by the current user (${current_user}):"
            while IFS= read -r f; do
                file_owner=$(stat -c '%U(%u)' "${f}" 2>/dev/null) || file_owner="unknown"
                log_message "ERROR:   ${f}  (owner: ${file_owner})"
            done <<<"${bad_tracked_files}"
            log_message "ERROR: git pull will fail. Fix with: sudo chown -R ${current_user} <affected-dirs>"
            exit 1
        fi

        # Check if there are any changes in the Git repository
        if ! git "${GIT_OPTS[@]}" fetch --quiet origin; then
            log_message "ERROR: Unable to fetch changes from the remote repository (the server may be offline or unreachable)"
            exit 1
        fi

        local_hash=$(git "${GIT_OPTS[@]}" rev-parse HEAD)
        remote_hash=$(git "${GIT_OPTS[@]}" rev-parse "origin/${REMOTE_BRANCH}")

        # Check for uncommitted local changes
        uncommitted_changes=$(git "${GIT_OPTS[@]}" status --porcelain)
        if [ -n "${uncommitted_changes}" ]; then
            log_message "ERROR: Uncommitted changes detected in ${dir}, exiting..."
            exit 1
        fi

        # Ensure we are on the expected branch before comparing hashes or pulling
        if ! git "${GIT_OPTS[@]}" checkout --quiet "${REMOTE_BRANCH}"; then
            log_message "ERROR: Unable to checkout branch ${REMOTE_BRANCH}. Verify the branch exists and there are no uncommitted changes."
            exit 1
        fi

        # Re-read local hash now that we are confirmed on the correct branch
        local_hash=$(git "${GIT_OPTS[@]}" rev-parse HEAD)
        local short_local="${local_hash:0:7}"
        local short_remote="${remote_hash:0:7}"

        # Check if the local hash matches the remote hash (skip check in force mode)
        if [ "${FORCE}" -eq 1 ] || [ "${local_hash}" != "${remote_hash}" ]; then
            # Pull any changes in the Git repository
            if [ "${local_hash}" != "${remote_hash}" ]; then
                log_message "STATE: New commits available on origin/${REMOTE_BRANCH} — pulling (local: ${short_local}, remote: ${short_remote})"
                if ! git "${GIT_OPTS[@]}" pull --quiet origin "${REMOTE_BRANCH}"; then
                    log_message "ERROR: Unable to pull changes from the remote repository (the server may be offline or unreachable)"
                    exit 1
                fi
                log_message "INFO:  Pulled latest commits from origin/${REMOTE_BRANCH} (now at ${short_remote})"
            else
                log_message "INFO:  Already up-to-date on origin/${REMOTE_BRANCH} (${short_local}) — force mode, redeploying"
            fi

            SHOULD_DEPLOY=1
        else
            # Even when up-to-date, deploy if no containers are running (fresh server)
            local running_containers
            running_containers=$(${SUDO} docker ps --quiet 2>/dev/null | head -1) || true
            if [ -z "${running_containers}" ]; then
                log_message "STATE: Already up-to-date on origin/${REMOTE_BRANCH} (${short_local}) but no containers running — deploying"
                SHOULD_DEPLOY=1
            else
                log_message "STATE: Already up-to-date on origin/${REMOTE_BRANCH} (${short_local}) — nothing to do"
            fi
        fi
    fi

    # In decrypt-only mode always run decryption, even when there are no new commits
    if [ "${DECRYPT_ONLY}" -eq 1 ]; then
        SHOULD_DEPLOY=1
    fi

    if [ "${SHOULD_DEPLOY}" -eq 1 ]; then
        # Decrypt SOPS-encrypted secret files before deploying
        decrypt_sops_files

        if [ "${DECRYPT_ONLY}" -eq 1 ]; then
            log_message "INFO:  Decrypt-only mode enabled, skipping deployment"
            return 0
        fi

        if [ "${TRUENAS}" -eq 1 ]; then
            redeploy_truenas_apps
        else
            redeploy_compose_file() {
                local file=$1
                local -a extra_files=("${@:2}") # Optional override compose files
                local app_name
                app_name=$(basename "$(dirname "${file}")")

                # Build the compose file arguments
                local -a compose_file_args=(-f "${file}")
                for ef in "${extra_files[@]}"; do
                    compose_file_args+=(-f "${ef}")
                done

                # Validate the compose file(s) before touching any running containers
                if ! ${SUDO} docker compose "${compose_file_args[@]}" config --quiet 2>/dev/null; then
                    log_message "WARNING: ${app_name}: Skipping deployment — compose config validation failed"
                    return 0
                fi

                _DEPLOY_ATTEMPTED=$((_DEPLOY_ATTEMPTED + 1))

                # Build the command as an array to avoid eval and command injection
                run_compose_command() {
                    local -a cmd=()
                    if [ -n "${SUDO}" ]; then
                        cmd+=("${SUDO}")
                    fi
                    cmd+=(docker compose)
                    if [ -n "${COMPOSE_OPTS}" ]; then
                        # Word-split is intentional: COMPOSE_OPTS is a controlled CLI flag (-o)
                        # shellcheck disable=SC2206
                        cmd+=(${COMPOSE_OPTS})
                    fi
                    cmd+=("$@")
                    "${cmd[@]}"
                }

                # Pull images unless NO_PULL is set
                if [ "${NO_PULL}" -eq 0 ]; then
                    run_compose_command "${compose_file_args[@]}" pull --quiet
                else
                    log_message "STATE: Skipping image pull for ${file} (no-pull mode)"
                fi

                if [ "${GRACEFUL}" -eq 1 ]; then
                    run_compose_command "${compose_file_args[@]}" up -d --dry-run &>"${TMPRESTART}"
                    if grep -q "Recreate" "${TMPRESTART}"; then
                        log_message "GRACEFUL: Redeploying compose file for ${file}"
                        # shellcheck disable=SC2310  # failure is handled by the surrounding if block
                        if ! run_compose_command "${compose_file_args[@]}" up -d --build --quiet-pull; then
                            log_message "ERROR: Failed to deploy ${file} - containers may be unhealthy"
                            _DEPLOY_ERRORS=$((_DEPLOY_ERRORS + 1))
                            _DEPLOY_FAILED_APPS+=("${app_name}")
                        fi
                    else
                        log_message "GRACEFUL: Skipping Redeploying compose file for ${file} (no change)"
                    fi
                else
                    log_message "STATE: Redeploying compose file for ${file}"
                    # shellcheck disable=SC2310  # failure is handled by the surrounding if block
                    if ! run_compose_command "${compose_file_args[@]}" up -d --build --quiet-pull; then
                        log_message "ERROR: Failed to deploy ${file} - containers may be unhealthy"
                        _DEPLOY_ERRORS=$((_DEPLOY_ERRORS + 1))
                        _DEPLOY_FAILED_APPS+=("${app_name}")
                    fi
                fi
            }

            # Collect compose files; traefik must be deployed last because it
            # attaches to networks created by other projects.
            local -a traefik_files=()
            local -a other_files=()

            if [ "${#SERVER_APPS[@]}" -gt 0 ]; then
                # Server mode: build file list from the server's app list only
                for app in "${SERVER_APPS[@]}"; do
                    local compose_file="./services/${app}/compose.yaml"
                    if [ ! -f "${compose_file}" ]; then
                        log_message "WARNING: ${app}: compose.yaml not found, skipping"
                        continue
                    fi
                    if [[ "${app}" == *traefik* ]]; then
                        traefik_files+=("${compose_file}")
                    else
                        other_files+=("${compose_file}")
                    fi
                done
            else
                # Default mode: discover all compose files via find
                # shellcheck disable=SC2312  # find/sort exit codes in process substitution are non-fatal
                while IFS= read -r file; do
                    if [[ "${file}" == */traefik/* ]]; then
                        traefik_files+=("${file}")
                    else
                        other_files+=("${file}")
                    fi
                done < <(find . \( -name data -o -name backups \) -prune -o -type f \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yaml' -o -name 'compose.yml' \) -print | sort)
            fi

            for file in "${other_files[@]}" "${traefik_files[@]}"; do
                # Extract the directory containing the file
                dir=$(dirname "${file}")

                # If APP_FILTER is set, only deploy the matching app
                if [ -n "${APP_FILTER}" ]; then
                    if [[ "${dir}" != *"${APP_FILTER}"* ]]; then
                        continue
                    fi
                fi

                # If EXCLUDE is set
                if [ -n "${EXCLUDE}" ]; then
                    # If the directory does not contain the exclude pattern
                    if [[ "${dir}" == *"${EXCLUDE}"* ]]; then
                        continue
                    fi
                fi

                # Check for a server-specific compose override file
                local -a override_args=()
                if [ -n "${SERVER_NAME}" ]; then
                    local override_file="${dir}/compose.${SERVER_NAME}.yaml"
                    if [ -f "${override_file}" ]; then
                        log_message "INFO:  Applying server override: ${override_file}"
                        override_args=("${override_file}")
                    fi
                fi

                redeploy_compose_file "${file}" "${override_args[@]}"
            done
        fi
    fi

    # Check if PRUNE is provided
    if [ "${PRUNE}" -eq 1 ]; then
        log_message "STATE: Pruning images"
        ${SUDO} docker image prune --all --force
    fi

    # Cleanup graceful file.
    if [ "${GRACEFUL}" -eq 1 ]; then
        rm -f "${TMPRESTART}"
    fi

    # Check for root-owned files (excluding data/ and backups/).
    # Git fetch/pull and SOPS decryption can create files owned by root when ran with root.
    local root_owned
    root_owned=$(find "${BASE_DIR}" \( -name data -o -name backups \) -prune -o -user root -print 2>/dev/null) || true
    if [ -n "${root_owned}" ]; then
        log_message "WARNING: Files owned by root detected (git fetch/pull or SOPS may have created them):"
        while IFS= read -r f; do
            log_message "WARNING:   ${f}"
        done <<<"${root_owned}"
        local current_user
        current_user=$(whoami) || true
        log_message "WARNING: To fix, run manually:"
        log_message "WARNING:   find \"${BASE_DIR}\" \\( -name data -o -name backups \\) -prune -o -user root -print0 | xargs -0 -r sudo chown ${current_user}:${current_user}"
    fi

    if [ "${SHOULD_DEPLOY}" -eq 1 ]; then
        local sep="========================================"
        log_message "${sep}"
        local succeeded
        succeeded=$((_DEPLOY_ATTEMPTED - _DEPLOY_ERRORS))
        if [ "${_DEPLOY_ERRORS}" -eq 0 ]; then
            log_message "RESULT: All ${_DEPLOY_ATTEMPTED} app(s) deployed successfully"
        else
            log_message "RESULT: ${succeeded}/${_DEPLOY_ATTEMPTED} app(s) deployed successfully, ${_DEPLOY_ERRORS} failed:"
            if [ "${#_DEPLOY_FAILED_APPS[@]}" -gt 0 ]; then
                for app in "${_DEPLOY_FAILED_APPS[@]}"; do
                    log_message "RESULT:   FAILED: ${app}"
                done
            fi
        fi
        log_message "${sep}"
    fi

    local end_time elapsed_time
    end_time=$(date +%s)
    elapsed_time=$((end_time - _CD_START_TIME))
    log_message "INFO:  Total execution time: ${elapsed_time}s"

    log_message "STATE: Done!"
}

# Report the CD pipeline status to a Gatus external endpoint.
# Requires GATUS_URL (-G flag) and GATUS_CD_TOKEN (env var) to be set.
report_cd_status_to_gatus() {
    local success="$1"
    local error_msg="${2:-}"
    local duration="${3:-}"

    if [ -z "${GATUS_URL}" ] || [ -z "${GATUS_CD_TOKEN:-}" ]; then
        return
    fi

    # Simple URL encoding for query string values (handles spaces and common special chars)
    url_encode_simple() {
        printf '%s' "$1" | sed 's/ /+/g; s/&/%26/g; s/=/%3D/g; s/#/%23/g'
    }

    # Key format: <GROUP>_<NAME> — must match the external-endpoint definition in Gatus config
    local key="Webhooks_docker-compose-cd"
    local query="success=${success}"
    [ -n "${error_msg}" ] && query="${query}&error=$(url_encode_simple "${error_msg}")"
    [ -n "${duration}" ] && query="${query}&duration=${duration}"

    local -a curl_opts=(-fsSL --max-time 30 -X POST -H "Authorization: Bearer ${GATUS_CD_TOKEN}")
    # --dns-servers requires curl built with c-ares (AsynchDNS), which is not universal.
    # Instead, pre-resolve the hostname via dig and use --resolve (works on all curl builds).
    if [ -n "${GATUS_DNS_SERVER}" ]; then
        local gatus_host gatus_ip
        gatus_host=$(printf '%s' "${GATUS_URL%/}" | sed 's|^https\?://||' | cut -d'/' -f1 | cut -d':' -f1)
        gatus_ip=$(dig +short "${gatus_host}" "@${GATUS_DNS_SERVER}" 2>/dev/null | grep -E '^[0-9]{1,3}\.' | head -n1) || true
        [ -n "${gatus_ip}" ] && curl_opts+=(--resolve "${gatus_host}:443:${gatus_ip}" --resolve "${gatus_host}:80:${gatus_ip}")
    fi

    local curl_output
    if curl_output=$(curl "${curl_opts[@]}" \
        "${GATUS_URL%/}/api/v1/endpoints/${key}/external?${query}" 2>&1 >/dev/null); then
        log_message "INFO:  CD status (success=${success}) reported to Gatus"
    else
        log_message "WARNING: Failed to report CD status to Gatus${curl_output:+: ${curl_output}}"
    fi
}

# EXIT trap handler: report final CD status to Gatus including duration.
_handle_gatus_exit() {
    local exit_code="$1"
    [ -z "${_CD_START_TIME:-}" ] && return
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - _CD_START_TIME))
    if [ "${exit_code}" -eq 0 ] && [ "${_DEPLOY_ERRORS}" -eq 0 ]; then
        report_cd_status_to_gatus "true" "" "${duration}s"
    elif [ "${_DEPLOY_ERRORS}" -gt 0 ]; then
        report_cd_status_to_gatus "false" "${_DEPLOY_ERRORS} deployment(s) failed - check logs for details" "${duration}s"
    else
        report_cd_status_to_gatus "false" "CD pipeline exited with code ${exit_code}" "${duration}s"
    fi
}

usage() {
    cat <<EOF

    Usage: $0 [OPTIONS]

    Options:
      -a <name>       Only deploy the specified app (optional - matches directory name)
      -b <name>       Specify the remote branch to track (default: main)
      -d <path>       Specify the base directory of the git repository (required)
      -D              Decrypt-only: git sync then decrypt all SOPS secret files, skip deploying
      -f              Force redeploy, skip the hash comparison check (optional)
      -g              Graceful, only restart containers that will be recreated (optional)
      -h              Show this help message
      -k <path>       Specify the path to the Age private key file for SOPS decryption (required when *.sops.env files exist)
      -n              No-pull mode: skip pulling images, use local images only (optional)
      -o <options>    Additional options to pass directly to \`docker compose...\` (optional)
      -p              Specify if you want to prune docker images (default: don't prune)
      -s <path>       Specify the directory to install the SOPS binary (default: <BASE_DIR>/bin)
      -t              TrueNAS Scale mode: deploy apps from services/ using ix-<app> project names (optional)
      -w <seconds>    Timeout in seconds to wait for containers to become healthy (default: 60, 0 = no timeout)
      -x <path>       Exclude directories matching the specified pattern (optional - relative to the base directory)
      -G <url>        Gatus instance URL to report CD status to (optional - falls back to GATUS_URL/GATUS_CD_TOKEN from services/gatus/.env)
      -r <ip>         DNS server to use for Gatus curl calls (optional - overrides system resolver for Gatus only, requires curl with c-ares)
      -S <server>     Server mode: deploy only apps assigned to <server> in servers.yaml (mutually exclusive with -a and -t)

    Example: /path/to/dccd.sh -b master -d /path/to/git_repo -g -k /path/to/age/keys.txt -o "--env-file /path/to/my.env" -p -x ignore_this_directory
    TrueNAS: /path/to/dccd.sh -t -d /path/to/git_repo -k /path/to/age/keys.txt -p
    Local:   /path/to/dccd.sh -d /path/to/git_repo -f -n -a plex
    Server:  /path/to/dccd.sh -d /path/to/git_repo -S svlazext -k /path/to/age.key -f

EOF
    exit 1
}

########################################
# Options
########################################

while getopts ":a:b:d:DfgG:k:hno:pr:s:S:tw:x:" opt; do
    case "${opt}" in
    a)
        APP_FILTER="${OPTARG}"
        ;;
    b)
        REMOTE_BRANCH="${OPTARG}"
        ;;
    d)
        BASE_DIR="${OPTARG}"
        ;;
    D)
        DECRYPT_ONLY=1
        ;;
    f)
        FORCE=1
        ;;
    g)
        GRACEFUL=1
        ;;
    h)
        usage
        ;;
    n)
        NO_PULL=1
        ;;
    k)
        SOPS_AGE_KEY_FILE="${OPTARG}"
        ;;
    o)
        COMPOSE_OPTS="${OPTARG}"
        ;;
    p)
        PRUNE=1
        ;;
    s)
        SOPS_INSTALL_DIR="${OPTARG}"
        ;;
    S)
        SERVER_NAME="${OPTARG}"
        ;;
    t)
        TRUENAS=1
        ;;
    w)
        WAIT_TIMEOUT="${OPTARG}"
        ;;
    x)
        EXCLUDE="${OPTARG}"
        ;;
    G)
        GATUS_URL="${OPTARG}"
        ;;
    r)
        GATUS_DNS_SERVER="${OPTARG}"
        ;;
    \?)
        echo "Invalid option: -${OPTARG}" >&2
        usage
        ;;
    :)
        echo "Option -${OPTARG} requires an argument." >&2
        usage
        ;;
    *)
        usage
        ;;
    esac
done

########################################
# Script starts here
########################################

# Check if BASE_DIR is provided
if [ -z "${BASE_DIR}" ]; then
    log_message "ERROR: The base directory (-d) is required, exiting..."
    usage
else
    log_message "INFO:  Base directory is set to ${BASE_DIR}"
fi

# Check if REMOTE_BRANCH is provided
if [ -z "${REMOTE_BRANCH}" ]; then
    log_message "INFO:  The remote branch isn't specified, so using ${REMOTE_BRANCH}"
else
    log_message "INFO:  The remote branch is set to ${REMOTE_BRANCH}"
fi

# Check if COMPOSE_OPTS is provided
if [ -n "${COMPOSE_OPTS}" ]; then
    log_message "INFO:  Using additional docker compose options: ${COMPOSE_OPTS}"
fi

# Check if EXCLUDE is provided
if [ -n "${EXCLUDE}" ]; then
    log_message "INFO:  Will be excluding pattern ${EXCLUDE}"
fi

# Check if FORCE mode is enabled
if [ "${FORCE}" -eq 1 ]; then
    log_message "INFO:  Force mode enabled, will redeploy regardless of hash match"
fi

# Check if NO_PULL mode is enabled
if [ "${NO_PULL}" -eq 1 ]; then
    log_message "INFO:  No-pull mode enabled, will skip pulling images"
fi

# Check if APP_FILTER is provided
if [ -n "${APP_FILTER}" ]; then
    log_message "INFO:  Will only deploy app '${APP_FILTER}'"
fi

# Check if SERVER_NAME is provided and validate mutual exclusivity
if [ -n "${SERVER_NAME}" ]; then
    if [ -n "${APP_FILTER}" ]; then
        log_message "ERROR: -S (server mode) and -a (app filter) are mutually exclusive"
        exit 1
    fi
    if [ "${TRUENAS}" -eq 1 ]; then
        log_message "ERROR: -S (server mode) and -t (TrueNAS mode) are mutually exclusive"
        exit 1
    fi
    log_message "INFO:  Server mode enabled for '${SERVER_NAME}'"
fi

# Resolve SOPS install directory now that BASE_DIR is known
if [ -z "${SOPS_INSTALL_DIR}" ]; then
    SOPS_INSTALL_DIR="${BASE_DIR}/bin"
fi
log_message "INFO:  SOPS install directory is set to ${SOPS_INSTALL_DIR}"

# Resolve SOPS Age key file now that BASE_DIR is known
if [ -z "${SOPS_AGE_KEY_FILE}" ]; then
    SOPS_AGE_KEY_FILE="${BASE_DIR}/age.key"
fi
log_message "INFO:  SOPS Age key file is set to ${SOPS_AGE_KEY_FILE}"

# Check if TRUENAS mode is enabled
if [ "${TRUENAS}" -eq 1 ]; then
    log_message "INFO:  TrueNAS Scale mode enabled (apps base: ${TRUENAS_APPS_BASE})"
fi

log_message "INFO:  Wait timeout is set to ${WAIT_TIMEOUT}s (0 = no timeout)"

# Source the already-decrypted gatus .env to pick up GATUS_CD_TOKEN and
# DOMAINNAME. The -G flag takes precedence over the derived URL.
_gatus_env="${BASE_DIR}/services/gatus/.env"
if [ -f "${_gatus_env}" ]; then
    _saved_gatus_url="${GATUS_URL}"
    _saved_gatus_dns="${GATUS_DNS_SERVER}"
    set -a
    # shellcheck disable=SC1090
    source "${_gatus_env}"
    set +a
    # Restore CLI-supplied URL so -G always takes precedence over the file
    if [ -n "${_saved_gatus_url}" ]; then
        GATUS_URL="${_saved_gatus_url}"
    elif [ -n "${DOMAINNAME:-}" ] && [ -z "${GATUS_URL}" ]; then
        GATUS_URL="https://status.${DOMAINNAME}"
    fi
    # Restore CLI-supplied DNS server so -r always takes precedence over the file
    if [ -n "${_saved_gatus_dns}" ]; then
        GATUS_DNS_SERVER="${_saved_gatus_dns}"
    else
        GATUS_DNS_SERVER=""
    fi
fi

# Check if Gatus CD reporting is configured
if [ -n "${GATUS_URL}" ]; then
    if [ -n "${GATUS_CD_TOKEN:-}" ]; then
        if [ -n "${GATUS_DNS_SERVER}" ]; then
            log_message "INFO:  Gatus CD reporting enabled (${GATUS_URL}, DNS: ${GATUS_DNS_SERVER})"
        else
            log_message "INFO:  Gatus CD reporting enabled (${GATUS_URL})"
        fi
    else
        log_message "WARNING: GATUS_URL is set but GATUS_CD_TOKEN is missing - Gatus reporting disabled"
    fi
fi

# Parse server app list if server mode is enabled
if [ -n "${SERVER_NAME}" ]; then
    parse_server_apps
fi

_CD_START_TIME=$(date +%s)
trap '_handle_gatus_exit $?' EXIT

update_compose_files "${BASE_DIR}"
