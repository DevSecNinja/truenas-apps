#!/bin/bash
# Source: https://github.com/loganmarchione/dccd/blob/d5aef3f684e5f63e8ec348652c6dc24e7447336c/dccd.sh
# Usage in TrueNAS Scale:
#   Command: bash /mnt/vm-pool/Apps/scripts/dccd.sh -d /mnt/vm-pool/Apps -x shared -t -f
#   Run As User: root
#   Unselect 'Hide Standard Output' and 'Hide Standard Error'

set -euo pipefail

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
FORCE=0                                       # Force redeploy, skip hash check
WAIT_TIMEOUT=60                               # Timeout in seconds for --wait (0 = no timeout)
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
    echo "${formatted}"
    logger -t dccd "${message}"
}

# Use sudo only when not already running as root
# shellcheck disable=SC2312  # id -u always succeeds
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

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

decrypt_sops_files() {
    local src_dir="${BASE_DIR}/src"

    if [ ! -d "${src_dir}" ]; then
        return
    fi

    local sops_files
    sops_files=$(find "${src_dir}" \( -name data -o -name backups \) -prune -o -name '*.sops.env' -type f -print)

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
        local dir
        dir=$(dirname "${sops_file}")
        local secret_env="${dir}/.env"

        log_message "STATE: Decrypting $(basename "${dir}")/$(basename "${sops_file}")"
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

# Returns sorted lines of "<service>=<image-reference>" for all running containers in a compose project.
# Uses docker inspect on container IDs for reliable image info (including digest).
get_project_image_info() {
    local project_name="$1"
    ${SUDO} docker ps -q \
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
    local src_dir="${BASE_DIR}/src"

    if [ ! -d "${src_dir}" ]; then
        log_message "ERROR: Source directory ${src_dir} does not exist, exiting..."
        exit 1
    fi

    for app_dir in "${src_dir}"/*/; do
        local app_name
        app_name=$(basename "${app_dir}")
        local project_name="ix-${app_name}"
        local app_config_dir="${TRUENAS_APPS_BASE}/${app_name}/versions"

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
        log_message "STATE: Deploying TrueNAS app ${app_name} (version ${version}, project ${project_name})"

        # Capture image state before pulling so we can report what changed
        local img_before
        # shellcheck disable=SC2310  # || true is intentional; function may fail when no containers exist
        img_before=$(get_project_image_info "${project_name}") || true

        # Pull images
        log_message "STATE: Pulling images for ${app_name}"
        ${SUDO} docker compose \
            --project-name "${project_name}" \
            --file "${compose_file}" \
            pull

        # Deploy
        log_message "STATE: Starting containers for ${app_name}"
        if ! ${SUDO} docker compose \
            --project-name "${project_name}" \
            --file "${compose_file}" \
            up \
            -d \
            --wait \
            --wait-timeout "${WAIT_TIMEOUT}"; then
            log_message "ERROR: ${app_name} failed to become healthy within ${WAIT_TIMEOUT}s - check 'docker compose --project-name ${project_name} logs' for details"
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

    # Rewrite SSH remote URLs to HTTPS so fetch/pull works without SSH keys (for public repos in cron)
    # Allow root to operate on non-root-owned repos (safe.directory)
    GIT_OPTS=(-c "url.https://github.com/.insteadOf=git@github.com:" -c "safe.directory=${dir}")

    # Check if there are any changes in the Git repository
    if ! git "${GIT_OPTS[@]}" fetch --quiet origin; then
        log_message "ERROR: Unable to fetch changes from the remote repository (the server may be offline or unreachable)"
        exit 1
    fi

    local_hash=$(git "${GIT_OPTS[@]}" rev-parse HEAD)
    remote_hash=$(git "${GIT_OPTS[@]}" rev-parse "origin/${REMOTE_BRANCH}")
    log_message "INFO:  Remote hash is ${remote_hash}"

    # Check for uncommitted local changes
    uncommitted_changes=$(git "${GIT_OPTS[@]}" status --porcelain)
    if [ -n "${uncommitted_changes}" ]; then
        log_message "ERROR: Uncommitted changes detected in ${dir}, exiting..."
        exit 1
    fi

    # Ensure we are on the expected branch before comparing hashes or pulling
    if ! git "${GIT_OPTS[@]}" checkout "${REMOTE_BRANCH}"; then
        log_message "ERROR: Unable to checkout branch ${REMOTE_BRANCH}. Verify the branch exists and there are no uncommitted changes."
        exit 1
    fi

    # Re-read local hash now that we are confirmed on the correct branch
    local_hash=$(git "${GIT_OPTS[@]}" rev-parse HEAD)
    log_message "INFO:  Local hash is  ${local_hash} (after checkout)"

    # Check if the local hash matches the remote hash (skip check in force mode)
    if [ "${FORCE}" -eq 1 ] || [ "${local_hash}" != "${remote_hash}" ]; then
        if [ "${FORCE}" -eq 1 ]; then
            log_message "STATE: Force mode enabled, skipping hash check..."
        else
            log_message "STATE: Hashes don't match, updating..."
        fi

        # Pull any changes in the Git repository
        if [ "${local_hash}" != "${remote_hash}" ]; then
            if ! git "${GIT_OPTS[@]}" pull --quiet origin "${REMOTE_BRANCH}"; then
                log_message "ERROR: Unable to pull changes from the remote repository (the server may be offline or unreachable)"
                exit 1
            else
                log_message "INFO:  Successfully pulled changes from origin/${REMOTE_BRANCH}"
            fi
        fi

        # Decrypt SOPS-encrypted secret files before deploying
        decrypt_sops_files

        if [ "${TRUENAS}" -eq 1 ]; then
            redeploy_truenas_apps
        else
            redeploy_compose_file() {
                local file=$1

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

                if [ "${GRACEFUL}" -eq 1 ]; then
                    run_compose_command -f "${file}" up -d --dry-run &>"${TMPRESTART}"
                    if grep -q "Recreate" "${TMPRESTART}"; then
                        log_message "GRACEFUL: Redeploying compose file for ${file}"
                        # shellcheck disable=SC2310  # failure is handled by the surrounding if block
                        if ! run_compose_command -f "${file}" up -d --quiet-pull; then
                            log_message "ERROR: Failed to deploy ${file} - containers may be unhealthy"
                        fi
                    else
                        log_message "GRACEFUL: Skipping Redeploying compose file for ${file} (no change)"
                    fi
                else
                    log_message "STATE: Redeploying compose file for ${file}"
                    # shellcheck disable=SC2310  # failure is handled by the surrounding if block
                    if ! run_compose_command -f "${file}" up -d --quiet-pull; then
                        log_message "ERROR: Failed to deploy ${file} - containers may be unhealthy"
                    fi
                fi
            }

            # Collect compose files; traefik must be deployed last because it
            # attaches to networks created by other projects.
            local -a traefik_files=()
            local -a other_files=()
            # shellcheck disable=SC2312  # find/sort exit codes in process substitution are non-fatal
            while IFS= read -r file; do
                if [[ "${file}" == */traefik/* ]]; then
                    traefik_files+=("${file}")
                else
                    other_files+=("${file}")
                fi
            done < <(find . \( -name data -o -name backups \) -prune -o -type f \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yaml' -o -name 'compose.yml' \) -print | sort)

            for file in "${other_files[@]}" "${traefik_files[@]}"; do
                # Extract the directory containing the file
                dir=$(dirname "${file}")

                # If EXCLUDE is set
                if [ -n "${EXCLUDE}" ]; then
                    # If the directory does not contain the exclude pattern
                    if [[ "${dir}" != *"${EXCLUDE}"* ]]; then
                        redeploy_compose_file "${file}"
                    fi
                else
                    redeploy_compose_file "${file}"
                fi
            done
        fi
    else
        log_message "STATE: Hashes match, so nothing to do"
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

    # Restore ownership when running as root (e.g. on TrueNAS)
    if [ -z "${SUDO}" ]; then
        log_message "STATE: Restoring ownership to truenas_admin:truenas_admin"
        chown -R truenas_admin:truenas_admin "${dir}"
    fi

    log_message "STATE: Done!"
}

usage() {
    cat <<EOF

    Usage: $0 [OPTIONS]

    Options:
      -b <name>       Specify the remote branch to track (default: main)
      -d <path>       Specify the base directory of the git repository (required)
      -f              Force redeploy, skip the hash comparison check (optional)
      -g              Graceful, only restart containers that will be recreated (optional)
      -h              Show this help message
      -o <options>    Additional options to pass directly to \`docker compose...\` (optional)
      -k <path>       Specify the path to the Age private key file for SOPS decryption (required when *.sops.env files exist)
      -p              Specify if you want to prune docker images (default: don't prune)
      -s <path>       Specify the directory to install the SOPS binary (default: <BASE_DIR>/bin)
      -t              TrueNAS Scale mode: deploy apps from src/ using ix-<app> project names (optional)
      -w <seconds>    Timeout in seconds to wait for containers to become healthy (default: 60, 0 = no timeout)
      -x <path>       Exclude directories matching the specified pattern (optional - relative to the base directory)

    Example: /path/to/dccd.sh -b master -d /path/to/git_repo -g -k /path/to/age/keys.txt -o "--env-file /path/to/my.env" -p -x ignore_this_directory
    TrueNAS: /path/to/dccd.sh -t -d /path/to/git_repo -k /path/to/age/keys.txt -p

EOF
    exit 1
}

########################################
# Options
########################################

while getopts ":b:d:fgk:ho:ps:tw:x:" opt; do
    case "${opt}" in
    b)
        REMOTE_BRANCH="${OPTARG}"
        ;;
    d)
        BASE_DIR="${OPTARG}"
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
    t)
        TRUENAS=1
        ;;
    w)
        WAIT_TIMEOUT="${OPTARG}"
        ;;
    x)
        EXCLUDE="${OPTARG}"
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

update_compose_files "${BASE_DIR}"
