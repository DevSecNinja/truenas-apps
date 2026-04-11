#!/bin/sh
# Shell aliases and helper functions for TrueNAS NAS administration.
#
# Source this file from your shell's RC file with a one-time addition:
#   TrueNAS: echo 'source /mnt/vm-pool/apps/scripts/aliases.sh' >> ~/.zshrc
#   Bash: echo 'source /opt/apps/scripts/aliases.sh' >> ~/.bashrc
#.  Zsh:  echo 'source /opt/apps/scripts/aliases.sh' >> ~/.zshrc
#
# After that, dccd.sh keeps this file up-to-date automatically on every git pull.

########################################
# Environment Detection
########################################

if [ -d "/mnt/vm-pool/apps" ]; then
    APPS_DIR="/mnt/vm-pool/apps"
    DCCD_MODE="-t"
elif [ -d "/opt/apps" ]; then
    APPS_DIR="/opt/apps"
    # shellcheck disable=SC2139 # intentional: expand hostname at source time
    DCCD_MODE="-S $(hostname -s)"
fi

########################################
# Docker
########################################

# Show all containers with their health status
# shellcheck disable=SC2154 # $header is assigned by read inside the alias at runtime
alias dps='sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | (read -r header; echo "$header"; sort)'

# Show only unhealthy or exited containers
alias dps-bad='sudo docker ps -a --format "table {{.Names}}\t{{.Status}}" --filter "health=unhealthy" --filter "status=exited"'

# Follow logs for a container: dlog <container-name>
dlog() {
    sudo docker logs -f --tail 100 "$1"
}

# Restart a compose stack by app name: dre <appname>
# Example: dre gatus
dre() {
    sudo docker compose --project-name "ix-${1}" restart
}

# Pull and redeploy a single app via dccd: ddeploy <appname>
# Example: ddeploy gatus
# shellcheck disable=SC2086 # intentional word splitting on DCCD_MODE
ddeploy() {
    bash "${APPS_DIR}/scripts/dccd.sh" \
        -d "${APPS_DIR}" \
        -k "${APPS_DIR}/age.key" \
        -x shared ${DCCD_MODE} -f -a "$1"
}

# Bring down a compose stack by app name: ddown <appname>
# Example: ddown gatus
ddown() {
    sudo docker compose --project-name "ix-${1}" down
}

# Bring down one or more apps via dccd (server-aware with compose overrides).
# Accepts space-separated and/or comma-separated app names, or --all for every service.
# Examples:
#   dccd-down openspeedtest
#   dccd-down traefik hadiscover
#   dccd-down traefik,hadiscover
#   dccd-down --all
# shellcheck disable=SC2086 # intentional word splitting on DCCD_MODE
dccd_down() {
    if [ -z "${APPS_DIR:-}" ]; then
        echo "ERROR: APPS_DIR is not set." >&2
        return 1
    fi

    if [ "$#" -eq 0 ]; then
        echo "Usage: dccd-down <app> [<app> ...] | --all" >&2
        return 1
    fi

    local apps="" svc_dir svc_name app arg_part arg_rest

    for arg in "$@"; do
        case "${arg}" in
        --all)
            for svc_dir in "${APPS_DIR}/services"/*/; do
                svc_name="${svc_dir%/}"
                svc_name="${svc_name##*/}"
                [ "${svc_name}" = "shared" ] && continue
                apps="${apps}${svc_name}
"
            done
            ;;
        *)
            # Support comma-separated names within a single argument (e.g. "app1,app2")
            arg_rest="${arg}"
            while case "${arg_rest}" in *,*) true ;; *) false ;; esac do
                arg_part="${arg_rest%%,*}"
                arg_rest="${arg_rest#*,}"
                apps="${apps}${arg_part}
"
            done
            apps="${apps}${arg_rest}
"
            ;;
        esac
    done

    while IFS= read -r app; do
        [ -z "${app}" ] && continue
        bash "${APPS_DIR}/scripts/dccd.sh" \
            -d "${APPS_DIR}" \
            ${DCCD_MODE} -R "${app}"
    done <<EOF
${apps}
EOF
}
alias dccd-down='dccd_down'

# Show resource usage of all containers
alias dstats='sudo docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}"'

# Prune unused images
alias dprune='sudo docker image prune --all --force'

########################################
# Cleaning (confirmation-gated)
########################################

# Remove all stopped/exited/dead containers (with confirmation)
dclean_stopped() {
    local ids
    ids=$(sudo docker ps -aq --filter status=exited --filter status=dead)
    if [ -z "${ids}" ]; then
        echo "No stopped containers found."
        return 0
    fi
    echo "Stopped containers to remove:"
    # shellcheck disable=SC2086 # word splitting is intentional: $ids is a list of IDs
    sudo docker ps -a --filter status=exited --filter status=dead \
        --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
    printf "Remove all of the above? [y/N] "
    read -r reply
    case "${reply}" in
    [Yy])
        # shellcheck disable=SC2086
        sudo docker rm ${ids}
        echo "Done."
        ;;
    *)
        echo "Aborted."
        ;;
    esac
}
alias dclean-stopped='dclean_stopped'

# Remove orphaned containers — those whose Compose project has no matching
# services/<app>/ directory, and those started outside of Compose entirely.
dclean_orphans() {
    if [ -z "${APPS_DIR:-}" ]; then
        echo "ERROR: APPS_DIR is not set — cannot determine which projects are active."
        return 1
    fi

    local orphan_ids=""
    local orphan_names=""

    local raw_containers
    raw_containers=$(sudo docker ps -aq --format '{{.ID}}|{{.Names}}|{{index .Labels "com.docker.compose.project"}}') || true

    while IFS="|" read -r cid cname project; do
        # No compose project label → started outside Compose
        if [ -z "${project}" ]; then
            orphan_ids="${orphan_ids} ${cid}"
            orphan_names="${orphan_names}\n  ${cname} (no compose project)"
            continue
        fi

        # In TrueNAS mode strip the ix- prefix to get the service directory name
        local app_name="${project}"
        case "${DCCD_MODE:-}" in
        *-t*) app_name="${project#ix-}" ;;
        *) ;;
        esac

        # Flag the container if its services directory no longer exists
        if [ ! -d "${APPS_DIR}/services/${app_name}" ]; then
            orphan_ids="${orphan_ids} ${cid}"
            orphan_names="${orphan_names}\n  ${cname} (project: ${project}, dir missing: services/${app_name})"
        fi
    done <<EOF
${raw_containers}
EOF

    local trimmed_ids
    trimmed_ids=$(echo "${orphan_ids}" | tr -s ' ' | sed 's/^ //') || true
    orphan_ids="${trimmed_ids}"
    if [ -z "${orphan_ids}" ]; then
        echo "No orphaned containers found."
        return 0
    fi

    echo "Orphaned containers to remove:"
    printf '%b\n' "${orphan_names}"
    printf "Remove all of the above? [y/N] "
    read -r reply
    case "${reply}" in
    [Yy])
        # shellcheck disable=SC2086
        sudo docker rm ${orphan_ids}
        echo "Done."
        ;;
    *)
        echo "Aborted."
        ;;
    esac
}
alias dclean-orphans='dclean_orphans'

# Remove dangling (unreferenced) images (with confirmation)
dclean_images() {
    local count
    count=$(sudo docker images --filter dangling=true -q | wc -l) || true
    if [ "${count}" -eq 0 ]; then
        echo "No dangling images found."
        return 0
    fi
    echo "Dangling images to remove (${count}):"
    sudo docker images --filter dangling=true --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"
    printf "Remove all of the above? [y/N] "
    read -r reply
    case "${reply}" in
    [Yy])
        sudo docker image prune --force
        echo "Done."
        ;;
    *)
        echo "Aborted."
        ;;
    esac
}
alias dclean-images='dclean_images'

# Remove unused (dangling) volumes (with confirmation)
dclean_volumes() {
    local count
    count=$(sudo docker volume ls --filter dangling=true -q | wc -l) || true
    if [ "${count}" -eq 0 ]; then
        echo "No dangling volumes found."
        return 0
    fi
    echo "Dangling volumes to remove (${count}):"
    sudo docker volume ls --filter dangling=true
    printf "Remove all of the above? [y/N] "
    read -r reply
    case "${reply}" in
    [Yy])
        sudo docker volume prune --force
        echo "Done."
        ;;
    *)
        echo "Aborted."
        ;;
    esac
}
alias dclean-volumes='dclean_volumes'

# Remove unused custom networks (with confirmation)
dclean_networks() {
    local count
    count=$(sudo docker network ls --filter type=custom -q | wc -l) || true
    if [ "${count}" -eq 0 ]; then
        echo "No custom networks found."
        return 0
    fi
    echo "Custom networks (Docker will only remove those with no active endpoints):"
    sudo docker network ls --filter type=custom
    printf "Prune unused networks? [y/N] "
    read -r reply
    case "${reply}" in
    [Yy])
        sudo docker network prune --force
        echo "Done."
        ;;
    *)
        echo "Aborted."
        ;;
    esac
}
alias dclean-networks='dclean_networks'

# Run all cleaning steps in sequence
dclean_all() {
    echo "=== Stopped containers ==="
    dclean_stopped
    echo ""
    echo "=== Orphaned containers ==="
    dclean_orphans
    echo ""
    echo "=== Dangling images ==="
    dclean_images
    echo ""
    echo "=== Dangling volumes ==="
    dclean_volumes
    echo ""
    echo "=== Unused networks ==="
    dclean_networks
}
alias dclean-all='dclean_all'

########################################
# DCCD (Docker Compose Continuous Deploy)
########################################

# Force-deploy all apps, excluding shared
# shellcheck disable=SC2086 # intentional word splitting on DCCD_MODE
dccd_all() {
    bash "${APPS_DIR}/scripts/dccd.sh" \
        -d "${APPS_DIR}" \
        -k "${APPS_DIR}/age.key" \
        -x shared ${DCCD_MODE} -f
}
alias dccd-all='dccd_all'

# Graceful deploy: only restart containers that changed
# shellcheck disable=SC2086 # intentional word splitting on DCCD_MODE
dccd_graceful() {
    bash "${APPS_DIR}/scripts/dccd.sh" \
        -d "${APPS_DIR}" \
        -k "${APPS_DIR}/age.key" \
        -x shared ${DCCD_MODE} -g
}
alias dccd-graceful='dccd_graceful'

# Force-deploy one or more apps: dccd-app <app1> <app2> ... or dccd-app app1,app2,...
# Example: dccd-app traefik   or   dccd-app dozzle drawio traefik   or   dccd-app dozzle,drawio,traefik
# shellcheck disable=SC2086 # intentional word splitting on DCCD_MODE
dccd_app() {
    if [ "$#" -eq 0 ]; then
        echo "Usage: dccd-app <app1> [app2 ...] or dccd-app app1,app2,..."
        return 1
    fi

    # Normalize: replace commas with spaces, then iterate over each app
    local all_apps
    all_apps=$(printf '%s\n' "$@" | tr ',' ' ')
    for app in ${all_apps}; do
        bash "${APPS_DIR}/scripts/dccd.sh" \
            -d "${APPS_DIR}" \
            -k "${APPS_DIR}/age.key" \
            -x shared ${DCCD_MODE} -f -a "${app}"
    done
}
alias dccd-app='dccd_app'

# Decrypt all SOPS-encrypted env files without deploying
dccd_decrypt() {
    bash "${APPS_DIR}/scripts/dccd.sh" \
        -d "${APPS_DIR}" \
        -k "${APPS_DIR}/age.key" -D
}
alias dccd-decrypt='dccd_decrypt'

# View recent dccd cron job logs from the system journal (syslog tag set by logger -t dccd)
alias dccd-logs='sudo journalctl -t dccd -n 200 --no-pager'

########################################
# SOPS
########################################

# Regenerate .sops.yaml from servers.yaml and re-encrypt all secrets
# Run this after changing server-app mappings or Age keys
sops_rekey() {
    local base_dir
    base_dir="${1:-$(pwd)}"
    bash "${base_dir}/scripts/generate-sops-rules.sh" -d "${base_dir}" || return 1
    echo ""
    echo "Re-encrypting all secret.sops.env files..."
    for f in "${base_dir}"/services/*/secret.sops.env; do
        [ -f "${f}" ] || continue
        echo "  ${f}"
        sops updatekeys -y "${f}" || {
            echo "FAILED: ${f}"
            return 1
        }
    done
    echo "Done. Review changes with: git diff"
}
alias sops-rekey='sops_rekey'

########################################
# Help
########################################

# Show all available aliases and functions
halp() {
    cat <<'EOF'
Docker:
  dps               Show all containers (name, status, image)
  dps-bad           Show only unhealthy or exited containers
  dlog <name>       Follow logs for a container
  dre  <app>        Restart a compose stack by app name
  ddown <app>       Bring down a compose stack by app name
  dccd-down <app>   Bring down via dccd (server-aware, applies overrides)
  ddeploy <app>     Force-redeploy a single app via dccd
  dstats            Show resource usage of all containers
  dprune            Prune all unused images

DCCD:
  dccd-all          Force-deploy all apps
  dccd-graceful     Graceful deploy (only restart changed)
  dccd-app <apps>   Force-deploy one or more apps (space or comma separated)
  dccd-decrypt      Decrypt all SOPS env files (no deploy)
  dccd-logs         View recent dccd cron job logs

SOPS:
  sops-rekey [dir]  Regenerate .sops.yaml and re-encrypt all secrets

Cleaning (confirmation-gated):
  dclean-stopped    Remove all stopped/exited containers
  dclean-orphans    Remove containers with no matching services/ directory
  dclean-images     Remove dangling (unreferenced) images
  dclean-volumes    Remove dangling (unreferenced) volumes
  dclean-networks   Remove unused custom networks
  dclean-all        Run all cleaning steps in sequence

Help:
  halp              Show this help message
EOF
}
