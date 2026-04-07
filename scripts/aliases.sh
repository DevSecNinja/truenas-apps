#!/bin/sh
# Shell aliases and helper functions for TrueNAS NAS administration.
#
# Source this file from ~/.zshrc with a one-time addition:
#   echo 'source /mnt/vm-pool/apps/scripts/aliases.sh' >> ~/.zshrc
#
# After that, dccd.sh keeps this file up-to-date automatically on every git pull.

########################################
# Docker
########################################

# Show all containers with their health status
alias dps='sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"'

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
ddeploy() {
    bash /mnt/vm-pool/apps/scripts/dccd.sh \
        -d /mnt/vm-pool/apps \
        -k /mnt/vm-pool/apps/age.key \
        -x shared -t -f -a "$1"
}

# Bring down a compose stack by app name: ddown <appname>
# Example: ddown gatus
ddown() {
    sudo docker compose --project-name "ix-${1}" down
}

# Show resource usage of all containers
alias dstats='sudo docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}"'

# Prune unused images
alias dprune='sudo docker image prune --all --force'

########################################
# DCCD (Docker Compose Continuous Deploy)
########################################

# Force-deploy all apps (TrueNAS mode, excluding shared)
alias dccd-all='bash /mnt/vm-pool/apps/scripts/dccd.sh -d /mnt/vm-pool/apps -k /mnt/vm-pool/apps/age.key -x shared -t -f'

# Graceful deploy: only restart containers that changed
alias dccd-graceful='bash /mnt/vm-pool/apps/scripts/dccd.sh -d /mnt/vm-pool/apps -k /mnt/vm-pool/apps/age.key -x shared -t -g'

# Force-deploy a single app: dccd-app <appname>
# Example: dccd-app traefik
dccd_app() {
    bash /mnt/vm-pool/apps/scripts/dccd.sh \
        -d /mnt/vm-pool/apps \
        -k /mnt/vm-pool/apps/age.key \
        -x shared -t -f -a "$1"
}
alias dccd-app='dccd_app'

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
  ddeploy <app>     Force-redeploy a single app via dccd
  dstats            Show resource usage of all containers
  dprune            Prune all unused images

DCCD:
  dccd-all          Force-deploy all apps (TrueNAS mode)
  dccd-graceful     Graceful deploy (only restart changed)
  dccd-app <app>    Force-deploy a single app by name

Help:
  halp              Show this help message
EOF
}
