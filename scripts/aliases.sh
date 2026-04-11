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

# Bring down a single app via dccd (server-aware with compose overrides): dccd-down <appname>
# Example: dccd-down openspeedtest
# shellcheck disable=SC2086 # intentional word splitting on DCCD_MODE
dccd_down() {
    bash "${APPS_DIR}/scripts/dccd.sh" \
        -d "${APPS_DIR}" \
        ${DCCD_MODE} -R "$1"
}
alias dccd-down='dccd_down'

# Show resource usage of all containers
alias dstats='sudo docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}"'

# Prune unused images
alias dprune='sudo docker image prune --all --force'

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

# Force-deploy a single app: dccd-app <appname>
# Example: dccd-app traefik
# shellcheck disable=SC2086 # intentional word splitting on DCCD_MODE
dccd_app() {
    bash "${APPS_DIR}/scripts/dccd.sh" \
        -d "${APPS_DIR}" \
        -k "${APPS_DIR}/age.key" \
        -x shared ${DCCD_MODE} -f -a "$1"
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
  dccd-app <app>    Force-deploy a single app by name
  dccd-decrypt      Decrypt all SOPS env files (no deploy)
  dccd-logs         View recent dccd cron job logs

SOPS:
  sops-rekey [dir]  Regenerate .sops.yaml and re-encrypt all secrets

Help:
  halp              Show this help message
EOF
}
