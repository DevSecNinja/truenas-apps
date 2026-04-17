#!/bin/bash
# Applies host-level sysctl tuning required by containerized services.
# TrueNAS SCALE resets /etc/sysctl.d/ on updates, so this script must
# run at every boot (e.g. as a root cron job: @reboot or Init/Shutdown script).
#
# Usage in TrueNAS Scale:
#   System Settings → Advanced → Init/Shutdown Scripts
#   Type: Script  |  Command: bash /mnt/vm-pool/apps/scripts/host-sysctl.sh
#   When: Post Init  |  Enabled: Yes
#
# Or as a root crontab entry:
#   @reboot bash /mnt/vm-pool/apps/scripts/host-sysctl.sh

set -euo pipefail

log() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    logger -t host-sysctl "$1"
    echo "${ts} - $1"
}

########################################
# Matter Server — multicast group limit
########################################
# Python Matter Server uses Zeroconf (mDNS) for device discovery. The
# default net.ipv4.igmp_max_memberships (20) is too low — Zeroconf
# tries to join a multicast group per interface and fails with:
#   OSError: [Errno 105] No buffer space available
IGMP_KEY="net.ipv4.igmp_max_memberships"
IGMP_WANT=256
igmp_current=$(sysctl -n "${IGMP_KEY}" 2>/dev/null || echo 0)
if [ "${igmp_current}" -lt "${IGMP_WANT}" ]; then
    sysctl -w "${IGMP_KEY}=${IGMP_WANT}" >/dev/null
    log "Set ${IGMP_KEY}=${IGMP_WANT} (was ${igmp_current})"
else
    log "${IGMP_KEY} already ${igmp_current} (>= ${IGMP_WANT}), skipping"
fi

log "Host sysctl tuning complete"
