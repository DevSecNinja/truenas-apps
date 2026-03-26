#!/bin/bash
# Source: https://github.com/loganmarchione/dccd/blob/d5aef3f684e5f63e8ec348652c6dc24e7447336c/dccd.sh

########################################
# Default configuration values
########################################
BASE_DIR=""                    # Initialize empty variable
LOG_FILE="/tmp/dccd-$(id -un).log" # Default log file name (per-user)
PRUNE=0                        # Default prune setting
GRACEFUL=0                     # Default graceful setting
TMPRESTART="/tmp/dccd.restart" # Default log file for graceful setting
REMOTE_BRANCH="main"           # Default remote branch name
COMPOSE_OPTS=""                # Additional options for docker compose
TRUENAS=0                      # TrueNAS Scale mode
TRUENAS_APPS_BASE="/mnt/.ix-apps/app_configs" # Base path for TrueNAS app configs
FORCE=0                        # Force redeploy, skip hash check

########################################
# Functions
########################################

log_message() {
    local message="$1"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# Use sudo only when not already running as root
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

redeploy_truenas_apps() {
    local src_dir="$BASE_DIR/src"

    if [ ! -d "$src_dir" ]; then
        log_message "ERROR: Source directory $src_dir does not exist, exiting..."
        exit 1
    fi

    for app_dir in "$src_dir"/*/; do
        local app_name
        app_name=$(basename "$app_dir")
        local project_name="ix-${app_name}"
        local app_config_dir="${TRUENAS_APPS_BASE}/${app_name}/versions"

        # If EXCLUDE is set and the app matches, skip it
        if [ -n "$EXCLUDE" ] && [[ "$app_name" == *"$EXCLUDE"* ]]; then
            log_message "STATE: Skipping excluded app $app_name"
            continue
        fi

        if [ ! -d "$app_config_dir" ]; then
            log_message "ERROR: TrueNAS app config directory not found: $app_config_dir, skipping..."
            continue
        fi

        # Auto-detect the version directory (use the latest/only version)
        local version_dir
        version_dir=$(find "$app_config_dir" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)

        if [ -z "$version_dir" ]; then
            log_message "ERROR: No version directory found in $app_config_dir, skipping..."
            continue
        fi

        local rendered_dir="${version_dir}/templates/rendered"
        local compose_file="${rendered_dir}/docker-compose.yaml"

        if [ ! -f "$compose_file" ]; then
            log_message "ERROR: Compose file not found: $compose_file, skipping..."
            continue
        fi

        local version
        version=$(basename "$version_dir")
        log_message "STATE: Deploying TrueNAS app $app_name (version $version, project $project_name)"

        # Pull images
        log_message "STATE: Pulling images for $app_name"
        $SUDO docker compose \
            --project-name "$project_name" \
            --file "$compose_file" \
            pull

        # Deploy
        log_message "STATE: Starting containers for $app_name"
        $SUDO docker compose \
            --project-name "$project_name" \
            --file "$compose_file" \
            up -d
    done
}

update_compose_files() {
    local dir="$1"

    cd "$dir" || {
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
    GIT_OPTS=(-c "url.https://github.com/.insteadOf=git@github.com:" -c "safe.directory=$dir")

    # Check if there are any changes in the Git repository
    if ! git "${GIT_OPTS[@]}" fetch --quiet origin; then
        log_message "ERROR: Unable to fetch changes from the remote repository (the server may be offline or unreachable)"
        exit 1
    fi

    local_hash=$(git "${GIT_OPTS[@]}" rev-parse HEAD)
    remote_hash=$(git "${GIT_OPTS[@]}" rev-parse "origin/$REMOTE_BRANCH")
    log_message "INFO:  Local hash is  $local_hash"
    log_message "INFO:  Remote hash is $remote_hash"

    # Check for uncommitted local changes
    uncommitted_changes=$(git "${GIT_OPTS[@]}" status --porcelain)
    if [ -n "$uncommitted_changes" ]; then
        log_message "ERROR: Uncommitted changes detected in $dir, exiting..."
        exit 1
    fi

    # Check if the local hash matches the remote hash (skip check in force mode)
    if [ $FORCE -eq 1 ] || [ "$local_hash" != "$remote_hash" ]; then
        if [ $FORCE -eq 1 ]; then
            log_message "STATE: Force mode enabled, skipping hash check..."
        else
            log_message "STATE: Hashes don't match, updating..."
        fi

        # Pull any changes in the Git repository
        if [ "$local_hash" != "$remote_hash" ]; then
            if ! git "${GIT_OPTS[@]}" pull --quiet origin "$REMOTE_BRANCH"; then
                log_message "ERROR: Unable to pull changes from the remote repository (the server may be offline or unreachable)"
                exit 1
            fi
        fi

        if [ $TRUENAS -eq 1 ]; then
            redeploy_truenas_apps
        else
            redeploy_compose_file() {
                local file=$1

                # Build the command based on whether we have extra options
                run_compose_command() {
                    local cmd_args="$1"
                    if [ -n "$COMPOSE_OPTS" ]; then
                        eval "$SUDO docker compose $COMPOSE_OPTS $cmd_args"
                    else
                        eval "$SUDO docker compose $cmd_args"
                    fi
                }

                if [ $GRACEFUL -eq 1 ]; then
                    run_compose_command "-f \"$file\" up -d --dry-run" &> $TMPRESTART
                    if grep -q "Recreate" $TMPRESTART; then
                        log_message "GRACEFUL: Redeploying compose file for $file"
                        run_compose_command "-f \"$file\" up -d --quiet-pull"
                    else
                        log_message "GRACEFUL: Skipping Redeploying compose file for $file (no change)"
                    fi
                else
                    log_message "STATE: Redeploying compose file for $file"
                    run_compose_command "-f \"$file\" up -d --quiet-pull"
                fi
            }

            find . -type f \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yaml' -o -name 'compose.yml' \) | sort | while IFS= read -r file; do
                # Extract the directory containing the file
                dir=$(dirname "$file")

                # If EXCLUDE is set
                if [ -n "$EXCLUDE" ]; then
                    # If the directory does not contain the exclude pattern
                    if [[ "$dir" != *"$EXCLUDE"* ]]; then
                        redeploy_compose_file "$file"
                    fi
                else
                    redeploy_compose_file "$file"
                fi
            done
        fi
    else
        log_message "STATE: Hashes match, so nothing to do"
    fi

    # Check if PRUNE is provided
    if [ $PRUNE -eq 1 ]; then
        log_message "STATE: Pruning images"
        $SUDO docker image prune --all --force
    fi

    # Cleanup graceful file.
    if [ $GRACEFUL -eq 1 ]; then
        rm -f $TMPRESTART
    fi

    log_message "STATE: Done!"
}

usage() {
    printf "
    Usage: $0 [OPTIONS]

    Options:
      -b <name>       Specify the remote branch to track (default: main)
      -d <path>       Specify the base directory of the git repository (required)
      -f              Force redeploy, skip the hash comparison check (optional)
      -g              Graceful, only restart containers that will be recreated (optional)
      -h              Show this help message
      -l <path>       Specify the path to the log file (default: /tmp/dccd.log)
      -o <options>    Additional options to pass directly to \`docker compose...\` (optional)
      -p              Specify if you want to prune docker images (default: don't prune)
      -t              TrueNAS Scale mode: deploy apps from src/ using ix-<app> project names (optional)
      -x <path>       Exclude directories matching the specified pattern (optional - relative to the base directory)

    Example: /path/to/dccd.sh -b master -d /path/to/git_repo -g -l /tmp/dccd.txt -o \"--env-file /path/to/my.env\" -p -x ignore_this_directory
    TrueNAS: /path/to/dccd.sh -t -d /path/to/git_repo -p

"
    exit 1
}

########################################
# Options
########################################

while getopts ":b:d:fghl:o:ptx:" opt; do
    case "$opt" in
    b)
        REMOTE_BRANCH="$OPTARG"
        ;;
    d)
        BASE_DIR="$OPTARG"
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
    l)
        LOG_FILE="$OPTARG"
        ;;
    o)
        COMPOSE_OPTS="$OPTARG"
        ;;
    p)
        PRUNE=1
        ;;
    t)
        TRUENAS=1
        ;;
    x)
        EXCLUDE="$OPTARG"
        ;;
    \?)
        echo "Invalid option: -$OPTARG" >&2
        usage
        ;;
    :)
        echo "Option -$OPTARG requires an argument." >&2
        usage
        ;;
    esac
done

########################################
# Script starts here
########################################

touch "$LOG_FILE"
{
    echo "########################################"
    echo "# Starting!"
    echo "########################################"
} >> "$LOG_FILE"

# Redirect all stderr to the log file so command errors (e.g., sudo, docker) are captured
exec 2>> "$LOG_FILE"

# Check if BASE_DIR is provided
if [ -z "$BASE_DIR" ]; then
    log_message "ERROR: The base directory (-d) is required, exiting..."
    usage
else
    log_message "INFO:  Base directory is set to $BASE_DIR"
fi

# Check if REMOTE_BRANCH is provided
if [ -z "$REMOTE_BRANCH" ]; then
    log_message "INFO:  The remote branch isn't specified, so using $REMOTE_BRANCH"
else
    log_message "INFO:  The remote branch is set to $REMOTE_BRANCH"
fi

# Check if COMPOSE_OPTS is provided
if [ -n "$COMPOSE_OPTS" ]; then
    log_message "INFO:  Using additional docker compose options: $COMPOSE_OPTS"
fi

# Check if EXCLUDE is provided
if [ -n "$EXCLUDE" ]; then
    log_message "INFO:  Will be excluding pattern $EXCLUDE"
fi

# Check if FORCE mode is enabled
if [ $FORCE -eq 1 ]; then
    log_message "INFO:  Force mode enabled, will redeploy regardless of hash match"
fi

# Check if TRUENAS mode is enabled
if [ $TRUENAS -eq 1 ]; then
    log_message "INFO:  TrueNAS Scale mode enabled (apps base: $TRUENAS_APPS_BASE)"
fi

update_compose_files "$BASE_DIR"
