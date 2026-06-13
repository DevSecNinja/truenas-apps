#!/bin/bash
# host-init.sh — consolidated host-level boot-time setup for TrueNAS SCALE.
#
# TrueNAS SCALE resets host configuration on updates and reboots, so every
# host tweak required by the containerized services must be re-applied at each
# boot. This single script replaces the individual Init/Shutdown entries:
#
#   - ethtool offload fix for the Intel I219 NIC ("Hardware Unit Hang")
#   - host sysctl tuning (e.g. net.ipv4.igmp_max_memberships for matter-server)
#   - Avahi coexistence fix so matter-server can share mDNS UDP port 5353
#   - Incus dnsmasq port move off 5353
#
# Usage in TrueNAS SCALE:
#   System Settings → Advanced → Init/Shutdown Scripts
#   Type: Script  |  Command: bash /mnt/vm-pool/apps/scripts/host-init.sh
#   When: Post Init  |  Enabled: Yes
#
# Replace the legacy Post Init entries (the two ethtool commands and the old
# host-sysctl.sh script) with this single script.
#
# Runs as root under TrueNAS Post Init, so no sudo is needed. When running it
# by hand, invoke with sudo.

set -euo pipefail

_HOST_INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh disable=SC1091
. "${_HOST_INIT_DIR}/lib/log.sh"
# shellcheck disable=SC2034
LOG_TAG="host-init"

########################################
# Intel NIC offload — "Hardware Unit Hang"
########################################
# The Intel I219 (e1000e driver) periodically resets under load with
# "Detected Hardware Unit Hang" unless TCP/Generic Segmentation Offload are
# disabled. Apply to every candidate interface that is actually present.
NIC_INTERFACES=(enp0s31f6 eno1)
for nic in "${NIC_INTERFACES[@]}"; do
    if [ ! -d "/sys/class/net/${nic}" ]; then
        log_info "Interface ${nic} not present, skipping"
        continue
    fi
    if ethtool -K "${nic}" tso off gso off; then
        log_state "Disabled TSO/GSO offload on ${nic}"
    else
        log_warn "ethtool failed on ${nic}"
    fi
done

########################################
# Host sysctl tuning
########################################
# Matter Server uses Zeroconf (mDNS) for device discovery. The default
# net.ipv4.igmp_max_memberships (20) is too low — Zeroconf tries to join a
# multicast group per interface and fails with:
#   OSError: [Errno 105] No buffer space available
IGMP_KEY="net.ipv4.igmp_max_memberships"
IGMP_WANT=256
igmp_current="$(sysctl -n "${IGMP_KEY}" 2>/dev/null || echo 0)"
if [ "${igmp_current}" -lt "${IGMP_WANT}" ]; then
    sysctl -w "${IGMP_KEY}=${IGMP_WANT}" >/dev/null
    log_state "Set ${IGMP_KEY}=${IGMP_WANT} (was ${igmp_current})"
else
    log_info "${IGMP_KEY} already ${igmp_current} (>= ${IGMP_WANT}), skipping"
fi

########################################
# Avahi — allow matter-server mDNS coexistence
########################################
# matter-server runs with network_mode: host and binds its own CHIP mDNS
# responder to UDP 5353. The host's avahi-daemon already owns 5353, so the
# container fails to start with "Address already in use". Setting
# disallow-other-stacks=no lets avahi share the port (SO_REUSEPORT) so both
# mDNS responders coexist.
AVAHI_CONF="/etc/avahi/avahi-daemon.conf"
if [ ! -f "${AVAHI_CONF}" ]; then
    log_info "${AVAHI_CONF} not found, skipping Avahi tuning"
elif grep -Eq '^[[:space:]]*disallow-other-stacks=no' "${AVAHI_CONF}"; then
    log_info "Avahi disallow-other-stacks already no, skipping"
else
    # Uncomment/replace an existing key, or append it under [server] if absent.
    sed -i 's/^#*disallow-other-stacks=.*/disallow-other-stacks=no/' "${AVAHI_CONF}"
    if ! grep -Eq '^[[:space:]]*disallow-other-stacks=' "${AVAHI_CONF}"; then
        sed -i '/^\[server\]/a disallow-other-stacks=no' "${AVAHI_CONF}"
    fi
    if systemctl restart avahi-daemon; then
        log_state "Set Avahi disallow-other-stacks=no and restarted avahi-daemon"
    else
        log_warn "Updated ${AVAHI_CONF} but failed to restart avahi-daemon"
    fi
fi

########################################
# Incus — move dnsmasq off the mDNS port
########################################
# TrueNAS SCALE manages VMs and containers via Incus. The incusbr0 bridge runs
# a dnsmasq instance; pin it to port 5354 so it never contends with the
# matter-server mDNS responder on 5353.
if ! command -v incus >/dev/null 2>&1; then
    log_info "incus command not found, skipping dnsmasq tuning"
elif ! incus network info incusbr0 >/dev/null 2>&1; then
    log_info "Incus network incusbr0 not found, skipping"
else
    incus_dnsmasq=""
    if incus network get incusbr0 raw.dnsmasq >/tmp/host-init-dnsmasq 2>/dev/null; then
        incus_dnsmasq="$(cat /tmp/host-init-dnsmasq)"
    fi
    rm -f /tmp/host-init-dnsmasq
    if printf '%s\n' "${incus_dnsmasq}" | grep -Eq '(^|[[:space:]])port=5354([[:space:]]|$)'; then
        log_info "Incus incusbr0 dnsmasq already on port 5354, skipping"
    elif incus network set incusbr0 raw.dnsmasq="port=5354"; then
        log_state "Set incusbr0 raw.dnsmasq port=5354"
    else
        log_warn "Failed to set incusbr0 raw.dnsmasq port=5354"
    fi
fi

log_result "Host init complete"
