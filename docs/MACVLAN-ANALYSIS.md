# Macvlan Networking Analysis for Home Assistant

This document analyzes macvlan networking as an alternative or complement to the current Home Assistant bridge network setup. It covers technical implications, trade-offs, and recommendations specific to this repository's security-focused architecture.

## Table of Contents

- [Overview of Macvlan Networking](#overview-of-macvlan-networking)
- [Current Home Assistant Network Architecture](#current-home-assistant-network-architecture)
- [Macvlan Use Cases for Home Assistant](#macvlan-use-cases-for-home-assistant)
- [Benefits of Macvlan for Home Assistant](#benefits-of-macvlan-for-home-assistant)
- [Drawbacks and Limitations](#drawbacks-and-limitations)
- [Comparison with Current Bridge Setup](#comparison-with-current-bridge-setup)
- [Comparison with Techno Tim's Approach](#comparison-with-techno-tims-approach)
- [Technical Considerations](#technical-considerations)
- [Security Implications](#security-implications)
- [Implementation Options](#implementation-options)
- [Recommendations](#recommendations)

---

## Overview of Macvlan Networking

### What is Macvlan?

Macvlan is a Linux kernel driver that allows you to create virtual network interfaces with their own MAC addresses on a single physical network interface. When used with Docker, macvlan networking gives each container its own MAC address and IP address directly on the host's physical network, making the container appear as a distinct physical device on your LAN.

### How Macvlan Works

```text
Physical Network (192.168.1.0/24)
        │
        ├── Router (192.168.1.1)
        ├── TrueNAS Host (192.168.1.30)
        │   └── eno1 (physical interface)
        │       ├── Container A (192.168.1.201) — via macvlan, own MAC: 02:42:c0:a8:01:c9
        │       └── Container B (192.168.1.202) — via macvlan, own MAC: 02:42:c0:a8:01:ca
        ├── Smart TV (192.168.1.50)
        └── Thermostat (192.168.1.51)
```

Each macvlan container:
- Has its own unique MAC address (hardware address)
- Gets an IP address directly from your LAN subnet (192.168.1.x)
- Appears as a separate device to other network clients
- Can receive broadcast and multicast traffic (mDNS, SSDP, etc.)
- Bypasses Docker's NAT layer entirely

### Macvlan Modes

Docker macvlan supports multiple modes:

| Mode     | Description                                                      | Use Case                   |
|----------|------------------------------------------------------------------|----------------------------|
| bridge   | Default. Containers can talk to each other via the parent NIC    | Most common for LAN access |
| vepa     | All traffic hairpins through external switch (802.1Qbg standard) | Enterprise environments    |
| private  | Containers isolated from each other entirely                     | Strict isolation           |
| passthru | One container gets exclusive access to the parent NIC            | Single-container scenarios |

**This analysis focuses on bridge mode**, which is the standard for home lab deployments.

### Key Technical Limitation: Host Communication

**Containers on a macvlan network cannot communicate with the Docker host's IP address by default.**

This is a kernel-level limitation, not a Docker bug. The macvlan interface and the parent physical interface exist in separate L2 domains. To enable host-container communication, you must either:

1. Create a macvlan interface on the host itself (via `ip link add` + routing), or
2. Use a separate bridge network for host communication (dual-network setup)

This limitation has significant implications for the Traefik integration pattern used in this repository.

---

## Current Home Assistant Network Architecture

### Network Topology

Home Assistant currently uses **dual bridge networks**:

```yaml
networks:
  - home-assistant-frontend  # Traefik-facing (port 8123)
  - iot-backend              # Internal IoT service communication
```

```text
┌─────────────────────────────────────────────────────────────┐
│ Docker Host (TrueNAS)                                       │
│                                                             │
│  ┌────────────┐                                            │
│  │  Traefik   │◄───── home-assistant-frontend (bridge) ────┤
│  └────────────┘                                            │
│        │                                                    │
│        │                                                    │
│  ┌────────────────┐                                        │
│  │ Home Assistant │                                        │
│  │                │◄──── iot-backend (bridge, internal) ───┤
│  │  (bridged)     │                                        │
│  └────────────────┘                                        │
│        │                                                    │
│        ▼                                                    │
│  ┌─────────────┐  ┌──────────┐  ┌───────────┐            │
│  │  Mosquitto  │  │ ESPHome  │  │  Frigate  │            │
│  └─────────────┘  └──────────┘  └───────────┘            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
         │
         │ (NAT/iptables via Docker proxy)
         ▼
    Internet / LAN
```

### Key Characteristics

1. **Network Isolation**: Each service gets its own frontend network; Traefik joins them individually (see [Architecture § Networking](ARCHITECTURE.md#networking-per-service-isolation))
2. **Traefik Integration**: Home Assistant is accessed via `https://home-assistant.${DOMAINNAME}` with automatic SSL and no-auth middleware (HA enforces its own authentication)
3. **Reverse Proxy Pattern**: All external access is mediated through Traefik — no direct port publishing on the host
4. **NAT Layer**: Bridge networking uses Docker's NAT/iptables — containers get private IPs (172.x.x.x range)
5. **IoT Backend**: Internal bridge network (`iot-backend`, `internal: true`) for MQTT, ESPHome, Frigate, wmbusmeters communication
6. **Trusted Proxies**: Home Assistant config includes `trusted_proxies: 172.16.0.0/12` to accept X-Forwarded-For headers from Traefik

### Current Capabilities

**Already works:**
- Web UI access via Traefik (desktop + mobile browsers)
- Home Assistant Companion mobile app (connects via Traefik's public URL)
- MQTT communication with Mosquitto (via `iot-backend`)
- ESPHome device communication (ESPHome runs in `network_mode: host` for mDNS discovery, publishes to HA via API)
- DHCP device tracking (Home Assistant has `NET_RAW` capability for raw packet capture)

**Already works elsewhere in the repo:**
- Matter device discovery (Matter Server uses `network_mode: host` for mDNS + Thread IPv6)

### Current Limitations

**Does NOT work without workarounds:**
- Native mDNS/Zeroconf device discovery (Google Cast, HomeKit, Sonos, DLNA, AirPlay)
  - Multicast traffic (224.0.0.0/4) does not traverse Docker bridge NAT by default
  - mDNS (port 5353 UDP) is link-local multicast; bridges isolate this traffic
- Direct device-to-HA communication for local push APIs
  - Some smart devices expect to push updates to HA's IP (e.g., webhook-based integrations)
  - Bridge NAT means HA's IP is a private Docker bridge IP, unreachable from LAN devices

**Why DHCP tracking works but mDNS doesn't:**
- DHCP tracking uses raw packet capture (`AF_PACKET` sockets) on the bridge interface itself — it sees DHCP broadcast frames transiting the bridge
- mDNS requires the container to join a multicast group (224.0.0.251) and send/receive on that group — Docker bridge networking does not forward multicast traffic to/from the host's physical interface by default

---

## Macvlan Use Cases for Home Assistant

Home Assistant has several integrations that benefit from or require direct LAN network access:

### 1. mDNS/Zeroconf Discovery

**Affected integrations:**
- **Google Cast** (Chromecast, Google Home devices)
- **HomeKit** (HomeKit Controller integration for importing HomeKit accessories)
- **Apple TV** (discovery and media player control)
- **Sonos** (speaker discovery and control)
- **DLNA/UPnP** (media servers and renderers)
- **AirPlay** (media streaming)
- **Philips Hue** (bridge discovery without manual IP)
- **Spotify Connect** (speaker discovery)
- **Samsung SmartThings** (SSDP discovery)

**Technical requirement:** These protocols use mDNS (multicast DNS on 224.0.0.251:5353) or SSDP (multicast on 239.255.255.250:1900). Multicast traffic does not traverse Docker bridge NAT.

**Current workaround:** Manual IP configuration for each device (bypasses discovery).

**With macvlan:** Container joins the LAN multicast group directly; discovery works natively.

### 2. Local Push Webhooks

**Affected integrations:**
- **Netatmo** (weather station push notifications)
- **Tuya Local** (local push updates from Tuya devices)
- **Ring** (doorbell push events)
- **Unifi Protect** (motion/doorbell events)

**Technical requirement:** Devices send HTTP POST requests to Home Assistant's IP address. Bridge NAT gives HA a private IP (172.x.x.x) unreachable from the LAN.

**Current workaround:** Poll-based updates (slower, higher latency) or cloud relay.

**With macvlan:** HA gets a LAN IP (192.168.1.x); devices can reach it directly.

### 3. Wake-on-LAN

**Affected integrations:**
- **Wake on LAN** (wake computers, NAS, media servers)

**Technical requirement:** WoL magic packets are broadcast to the network's broadcast address (e.g., 192.168.1.255).

**Current workaround:** Send WoL from the host or a separate helper container with `network_mode: host`.

**With macvlan:** HA can send broadcast packets directly to the LAN broadcast address.

### 4. IGMP/Multicast Streaming

**Affected integrations:**
- **IPTV** (multicast video streams from ISP set-top boxes)
- **Roon** (lossless audio streaming protocol)

**Technical requirement:** IGMP multicast group membership and reception of multicast UDP streams.

**Current workaround:** None — not possible with bridge networking.

**With macvlan:** Container can join IGMP multicast groups and receive streams.

---

## Benefits of Macvlan for Home Assistant

### 1. Native Device Discovery (No Manual Configuration)

**Impact:** Eliminates the need to manually enter IP addresses for mDNS-based integrations. Home Assistant can discover devices on the LAN as if it were a physical machine.

**Example workflow without macvlan:**
```text
User: Add Google Chromecast integration
HA:   Discovery failed. Enter device IP manually.
User: (opens Google Home app, finds IP: 192.168.1.55)
User: Enters 192.168.1.55 in HA
```

**Example workflow with macvlan:**
```text
User: Add Google Chromecast integration
HA:   Found 3 Chromecast devices. Select one to add.
User: (clicks, done)
```

### 2. Lower Latency for Local Push Events

**Impact:** Devices can push updates directly to Home Assistant's LAN IP via HTTP webhooks. No cloud relay, no polling — events arrive in milliseconds instead of seconds.

**Benchmark comparison (typical values):**
| Method              | Latency   | Mechanism                                      |
|---------------------|-----------|------------------------------------------------|
| Macvlan local push  | 5-20 ms   | Device → HA LAN IP (direct HTTP POST)          |
| Cloud relay         | 200-800 ms| Device → cloud → HA (poll or webhook via WAN)  |
| Bridge NAT + poll   | 1-30 s    | HA polls device API every N seconds            |

**Use case:** Doorbell button press → turn on porch light. With macvlan + local push, this happens nearly instantly. With polling, there's a 1-30 second delay depending on poll interval.

### 3. Simplified Mobile App Connectivity

**Current state:** The Home Assistant Companion app works fine via Traefik's public URL. However, some users configure "internal URL" for faster local access when on the home network.

**With macvlan:** The internal URL would be `http://192.168.1.x:8123` (direct LAN IP). The app can auto-detect this via mDNS.

**Trade-off:** This bypasses Traefik's SSL termination. You'd need to either:
- Accept HTTP for internal access (less secure, but common in home labs), or
- Configure Home Assistant's own SSL termination (extra complexity)

**Recommendation for this repo:** Continue using Traefik for all access (internal and external). Macvlan's benefit here is minimal since the Companion app already works well via Traefik.

### 4. Compatibility with Techno Tim's Guides

Many Home Assistant tutorials and integration guides assume HA has a LAN IP. Using macvlan aligns with these community resources, reducing troubleshooting friction.

**Example:** The [Techno Tim Docker on TrueNAS guide](https://technotim.com/posts/truenas-docker-pro/) uses macvlan for device discovery.

### 5. Future-Proofing for Multicast Protocols

**Emerging protocols:**
- **Matter over Wi-Fi** (already handled by Matter Server with `network_mode: host` in this repo)
- **Thread Border Router** (already handled by Matter Server)
- **Alexa Local Voice Control** (requires mDNS and local LAN reachability)

Macvlan ensures HA can natively support new integrations that rely on multicast or direct LAN addressing without additional workarounds.

---

## Drawbacks and Limitations

### 1. Cannot Communicate with Docker Host by Default

**The core problem:** Containers on a macvlan network cannot reach the Docker host's IP address (192.168.1.30 in this setup). This is a kernel-level limitation of macvlan.

**Why this matters for this repository:**
- **Traefik integration breaks.** Traefik runs on the host network stack. If HA is on macvlan and cannot reach Traefik, the entire reverse proxy pattern (SSL termination, auth middleware, Gatus monitoring) collapses.
- **Gatus monitoring breaks.** Gatus checks HA via Traefik's internal monitoring entrypoint (172.30.100.6:8444). Macvlan containers cannot reach Docker bridge IPs.
- **No host services access.** HA cannot call APIs on the TrueNAS host itself (e.g., TrueNAS API for dataset snapshots, SMB share management).

**Potential workaround: Dual-Network Setup**
```yaml
networks:
  home-assistant-macvlan:
    driver: macvlan
    # ... macvlan config for LAN access
  home-assistant-frontend:
    driver: bridge
    # ... existing Traefik bridge
```

Home Assistant joins **both** networks:
- **macvlan** for mDNS discovery, local device push, broadcasts
- **bridge** for Traefik communication, Gatus monitoring, `iot-backend` IoT services

**Routing consideration:** Docker assigns one network as the default route. You'd need to ensure:
- Default route goes to macvlan (for internet access via LAN gateway)
- Static routes or policy routing send Traefik traffic to the bridge network

This is complex and fragile. Any misconfiguration could break either LAN discovery or Traefik access.

### 2. Breaks Network Isolation Model

This repository's core security principle: **per-service network isolation** (see [Architecture § Networking](ARCHITECTURE.md#networking-per-service-isolation)).

**Current model:**
- Each service has its own `<service>-frontend` bridge network
- Traefik joins each network individually
- Compromised containers cannot reach other services (only Traefik)

**With macvlan:**
- Home Assistant is directly on the LAN (192.168.1.x)
- Any LAN device can reach HA directly (bypasses Traefik's auth middleware if you expose port 8123)
- HA can reach any LAN device (including other Docker containers if they also use macvlan)

**Network isolation is lost at the LAN level.** This contradicts the principle that containers should only communicate via Traefik or explicitly defined backend networks.

### 3. Exposes Container Directly to LAN Threats

**Current security layers:**
1. **Firewall (host-level iptables/nftables):** Blocks untrusted traffic before it reaches Docker
2. **Traefik reverse proxy:** Enforces SSL, rate limiting, IP allowlists, auth middleware
3. **Docker bridge NAT:** Containers have private IPs; not directly routable from LAN
4. **Container hardening:** `cap_drop: ALL`, `no-new-privileges`, `read_only: true`

**With macvlan:**
- Layer 3 (Docker bridge NAT) is removed
- Container has a LAN IP; any device on LAN can attempt to connect
- If port 8123 is exposed, HA's web UI is reachable directly (bypassing Traefik)

**Mitigation strategies:**
- **Do not publish port 8123 in the compose file** (rely on Traefik via the bridge network in a dual-network setup)
- **Use Home Assistant's own firewall/ban features** (e.g., fail2ban integration, IP banning)
- **VLAN isolation** (put IoT devices on a separate VLAN with firewall rules restricting access to only HA's IP)

**Trade-off:** Mitigations add complexity and shift security enforcement from the infrastructure layer (Traefik, Docker) to the application layer (Home Assistant config).

### 4. IP Address Management Overhead

**With bridge networking:** Docker's IPAM automatically assigns IPs from the bridge subnet. No manual allocation needed.

**With macvlan:** You must either:
- **Reserve a static IP in your DHCP server** (common approach), or
- **Use Docker's IPAM with a restricted range** (e.g., 192.168.1.200-192.168.1.210 reserved for Docker), or
- **Use DHCP inside the container** (fragile; container gets a different IP on restart)

**Best practice:** Reserve a static IP (e.g., 192.168.1.200) in your router's DHCP server, then configure it in the compose file:

```yaml
networks:
  home-assistant-macvlan:
    ipv4_address: 192.168.1.200
    mac_address: "02:42:c0:a8:01:c8"  # Optional: pin MAC for consistent DHCP behavior
```

**Ongoing maintenance:** Every macvlan container needs IP tracking. In this repo, the arr-stack already does this (see `EGRESS_IP` in `.env` files), so the pattern is established — but it's still manual overhead.

### 5. Cannot Use `internal: true` for Isolation

Docker's `internal: true` flag (used extensively in this repo, e.g., `iot-backend`, `arr-stack-backend`) prevents a bridge network from routing to the outside world. This is not applicable to macvlan networks — they are inherently external (attached to the physical LAN).

**Impact:** You cannot create an "internal macvlan" network for isolated inter-service communication. Services on macvlan can always reach the LAN and internet (subject to host firewall rules).

**Current `iot-backend` pattern would break:** Mosquitto, ESPHome, Frigate, wmbusmeters currently share an internal bridge network. If you moved them to macvlan for mDNS (e.g., ESPHome device discovery), they'd all be directly LAN-accessible — a broader attack surface.

**Recommendation:** Keep `iot-backend` as an internal bridge. Only move Home Assistant to macvlan if absolutely necessary for discovery, not the entire IoT stack.

### 6. Docker Compose Complexity (Multi-Network Routing)

**Dual-network Home Assistant compose excerpt (hypothetical):**

```yaml
services:
  home-assistant:
    networks:
      home-assistant-macvlan:
        ipv4_address: 192.168.1.200
        priority: 1000  # Default route via macvlan
      home-assistant-frontend:
        priority: 900   # Lower priority; Traefik reachable via this network
      iot-backend:
        # Internal bridge for MQTT, ESPHome, Frigate
```

**Challenges:**
- **Docker's `priority` is a recent feature** (Compose v2.20+). Older Docker versions don't support it; you'd need manual `ip route` commands in the entrypoint.
- **Routing policies are fragile.** If the default route goes to the bridge by mistake, mDNS discovery breaks (but Traefik works). If it goes to macvlan, Traefik may be unreachable (depending on your LAN topology).
- **Debugging is hard.** When connectivity breaks, you're troubleshooting routing tables inside the container — less transparent than "it works because it's on the same bridge as Traefik."

### 7. TrueNAS Apps UI Visibility

TrueNAS SCALE's Apps UI is designed around bridge networking. Macvlan containers may not appear correctly in the network topology views or may show as "external" devices. This is cosmetic, not functional, but reduces the operational benefit of using TrueNAS's built-in container management.

---

## Comparison with Current Bridge Setup

| Aspect                       | Current Bridge Setup                         | Macvlan Setup                                      |
|------------------------------|----------------------------------------------|----------------------------------------------------|
| **mDNS Discovery**           | ✗ Does not work (multicast isolation)        | ✓ Works natively                                   |
| **Traefik Integration**      | ✓ Native (same bridge network)               | ⚠ Requires dual-network + routing config            |
| **Gatus Monitoring**         | ✓ Works via internal entrypoint              | ⚠ Requires bridge network for Gatus access         |
| **Network Isolation**        | ✓ Per-service frontend networks              | ✗ LAN-level exposure (isolation via VLAN/firewall) |
| **Security Layers**          | ✓ Traefik + Docker NAT + container hardening | ⚠ Traefik + container hardening (no NAT layer)     |
| **IP Management**            | ✓ Automatic (Docker IPAM)                    | ⚠ Manual reservation or DHCP                       |
| **Companion App**            | ✓ Works via Traefik public URL               | ✓ Works via Traefik or direct LAN IP               |
| **Local Push Webhooks**      | ✗ Requires port forwarding or cloud relay    | ✓ Direct LAN IP reachable                          |
| **Broadcast (WoL)**          | ✗ Requires `network_mode: host` workaround   | ✓ Container can send broadcasts                    |
| **IoT Backend Integration**  | ✓ Internal bridge (`iot-backend`)            | ✓ Can still use `iot-backend` bridge               |
| **Complexity**               | ✓ Simple, well-documented                    | ⚠ Complex (dual-network routing)                   |
| **Alignment with Repo Goals**| ✓ Security-first, network isolation          | ⚠ Trade-off: functionality vs. isolation           |

**Summary:** The bridge setup is simpler, more secure, and better aligned with this repository's architecture. Macvlan adds functionality (mDNS, local push) at the cost of complexity and reduced isolation.

---

## Comparison with Techno Tim's Approach

### Techno Tim's Setup

From [technotim.com/posts/truenas-docker-pro](https://technotim.com/posts/truenas-docker-pro/):

**Network mode:** Macvlan (gives containers LAN IPs)

**Rationale:**
- **Device discovery "just works"** (mDNS, SSDP, etc.)
- **Simplified access model** (no reverse proxy for local access; containers have LAN IPs like `192.168.1.x`)
- **Familiar to users migrating from bare-metal or VMs** (container IP = device IP)

**Security model:**
- Relies on LAN-level security (router firewall, VLANs if configured)
- Does not use Traefik or a reverse proxy for internal access
- External access (from WAN) is handled via port forwarding or a separate VPN

**Apps in scope:** Home Assistant, AdGuard Home, and other services where direct LAN access is beneficial.

### This Repository's Setup

**Network mode:** Bridge with Traefik reverse proxy

**Rationale:**
- **Security-first architecture** (network isolation, defense-in-depth, `cap_drop: ALL`)
- **Centralized SSL termination** (Traefik with Let's Encrypt via Cloudflare DNS)
- **SSO integration** (Traefik Forward Auth with Microsoft Entra ID for non-HA services)
- **Monitoring via Gatus** (internal entrypoint for health checks without exposing auth bypass)

**Security model:**
- Per-service network isolation (Traefik joins each `<service>-frontend` network individually)
- No direct container-to-container communication unless explicitly defined (e.g., `iot-backend`)
- Secrets encrypted with SOPS + Age, not stored in plaintext
- Automated deployments via GitOps (dccd.sh) — infrastructure as code

**Apps in scope:** 26+ services including Home Assistant, Immich, Plex, arr-stack, Unifi, Outline, etc.

### Key Differences

| Aspect                  | Techno Tim's Approach                  | This Repository's Approach                        |
|-------------------------|----------------------------------------|---------------------------------------------------|
| **Primary Goal**        | Simplicity, device discovery           | Security, isolation, infrastructure as code       |
| **Network Model**       | Macvlan (LAN IPs)                      | Bridge (NAT) + Traefik reverse proxy              |
| **SSL/TLS**             | Optional (Caddy or Traefik if needed)  | Mandatory (Traefik with Let's Encrypt)            |
| **Authentication**      | Per-app (HA login, etc.)               | Centralized SSO (Traefik Forward Auth) + per-app  |
| **Discovery**           | Native (mDNS works out of the box)     | Manual IP config (mDNS does not work)             |
| **Security Layers**     | LAN firewall, app-level auth           | Traefik + Docker NAT + network isolation + caps   |
| **Complexity**          | Low (closer to bare-metal networking)  | Medium (Docker networks, Traefik config, SOPS)    |
| **Ideal Use Case**      | Home Assistant-centric home lab        | Multi-service home lab with strict security model |

### When to Prefer Techno Tim's Approach

Use macvlan (Techno Tim's model) if:

1. **Device discovery is critical** and you don't want to manually configure IPs for every mDNS device
2. **You're running primarily Home Assistant** with a few other services (not 26+ like this repo)
3. **Your LAN is already segmented with VLANs** and you handle security at the network level (router firewall, IoT VLAN isolation)
4. **You don't need centralized SSO** (each app handles its own authentication)
5. **Simplicity > defense-in-depth** for your threat model

### When to Prefer This Repository's Approach

Use bridge networking with Traefik (this repo's model) if:

1. **You run many services** (20+) and want centralized SSL + auth
2. **Network isolation is a priority** (you want compromised containers contained)
3. **You need SSO** (Traefik Forward Auth with Microsoft Entra ID, Google, etc.)
4. **You can live with manual IP configuration** for mDNS devices (or use `network_mode: host` for specific services like Matter Server)
5. **You value GitOps** (infrastructure as code, SOPS secrets, Renovate auto-updates)

### Hybrid Approach: Best of Both Worlds?

**Option 1: Macvlan for Home Assistant, Bridge for Everything Else**

- Home Assistant gets macvlan (for mDNS discovery) + bridge (for Traefik access)
- All other services stay on bridge-only (existing architecture unchanged)

**Pros:**
- Minimal disruption to existing services
- HA gains device discovery without sacrificing Traefik/Gatus integration

**Cons:**
- Dual-network complexity for HA (routing, config)
- HA's network isolation is weakened (LAN-accessible)

**Option 2: `network_mode: host` for Discovery-Critical Services Only**

- Home Assistant stays on bridge for Traefik/Gatus
- Add a lightweight mDNS reflector/proxy container with `network_mode: host`
  - Example: [avahi-reflector](https://github.com/flungo-docker/avahi) (reflects mDNS between LAN and Docker bridges)
  - Or: [mdns-repeater](https://github.com/kennylevinsen/mdns-repeater)

**Pros:**
- Preserves bridge networking for HA (simpler, more secure)
- Adds mDNS reflection without giving HA a LAN IP

**Cons:**
- Another moving part (the reflector container)
- May not work for all protocols (SSDP, IGMP)

**Recommendation for this repo:** Option 2 (mDNS reflector) if discovery is needed. Otherwise, accept manual IP configuration as the trade-off for security and simplicity.

---

## Technical Considerations

### 1. Traefik Integration

**Challenge:** Traefik runs on Docker bridge networks. Home Assistant on macvlan cannot reach Traefik by default.

**Solution: Dual-Network Setup**

```yaml
services:
  home-assistant:
    networks:
      home-assistant-macvlan:
        ipv4_address: 192.168.1.200
        mac_address: "02:42:c0:a8:01:c8"
      home-assistant-frontend:
        # Traefik joins this network
      iot-backend:
        # Mosquitto, ESPHome, Frigate, wmbusmeters

networks:
  home-assistant-macvlan:
    name: home-assistant-macvlan
    driver: macvlan
    driver_opts:
      parent: eno1
    ipam:
      driver: default
      config:
        - subnet: 192.168.1.0/24
          gateway: 192.168.1.1
          ip_range: 192.168.1.200/29  # Reserve 192.168.1.200-207 for Docker
  home-assistant-frontend:
    name: home-assistant-frontend
    driver: bridge
  iot-backend:
    name: iot-backend
    driver: bridge
    internal: true
```

**Routing configuration (required):**

Docker's default behavior is to assign the **first** network in the list as the default route. To ensure:
- **Internet traffic** uses macvlan (via LAN gateway 192.168.1.1)
- **Traefik traffic** uses the bridge network

You need to set routing priorities in Compose v2.20+:

```yaml
networks:
  home-assistant-macvlan:
    priority: 1000  # Default route
  home-assistant-frontend:
    priority: 900   # Secondary route
```

Or, for older Docker versions, add a custom entrypoint script:

```yaml
entrypoint:
  - /bin/sh
  - -c
  - |
    # Delete default route via bridge
    ip route del default via 172.x.x.1
    # Add default route via macvlan
    ip route add default via 192.168.1.1
    # Add static route for Traefik network
    ip route add 172.x.x.0/24 via 172.x.x.1
    # Start Home Assistant
    exec /init
```

**Testing:** After deploying, exec into the container and verify:

```bash
docker exec -it home-assistant sh
ip route show
# Expected output:
# default via 192.168.1.1 dev eth0
# 172.x.x.0/24 via 172.x.x.1 dev eth1
# 192.168.1.0/24 dev eth0 proto kernel scope link
```

### 2. Gatus Monitoring

Gatus currently checks Home Assistant via Traefik's internal monitoring entrypoint (172.30.100.6:8444). This requires Home Assistant to be on a Docker bridge network.

**With macvlan-only:** Gatus cannot reach HA (macvlan containers can't reach bridge IPs).

**Solution:** Keep the `home-assistant-frontend` bridge network (dual-network setup as above). Gatus continues checking via Traefik on the bridge.

**Alternative (not recommended):** Change Gatus to check HA's macvlan IP directly. This bypasses Traefik entirely, defeating the purpose of the monitoring entrypoint's IP allowlist security model.

### 3. IoT Backend Communication

The `iot-backend` network is an internal bridge shared by:
- Home Assistant
- Mosquitto (MQTT broker)
- ESPHome (firmware builder, publishes to HA via API)
- Frigate (NVR, sends MQTT events)
- wmbusmeters (smart meter reader, publishes to MQTT)

**Good news:** This is unaffected by macvlan. Home Assistant can be on **both** macvlan and `iot-backend` simultaneously.

```yaml
networks:
  - home-assistant-macvlan
  - home-assistant-frontend
  - iot-backend
```

All MQTT communication continues to work via the internal bridge.

### 4. Matter Server Integration

Matter Server currently runs with `network_mode: host` for mDNS device discovery (see [services/matter-server/compose.yaml](../services/matter-server/compose.yaml)).

**With macvlan Home Assistant:**
- Matter Server stays as-is (`network_mode: host`)
- Home Assistant connects to Matter Server via the host's LAN IP (e.g., `ws://192.168.1.30:5580/ws`)

**No change needed.** Matter Server already bypasses Docker networking for discovery.

### 5. ESPHome Device Discovery

ESPHome also uses `network_mode: host` for mDNS discovery of ESP devices (not explicitly in the compose file in this repo, but common practice).

**If ESPHome were on macvlan instead:**
- ESPHome would get a LAN IP (e.g., 192.168.1.201)
- ESP devices could discover it via mDNS
- Home Assistant would call ESPHome's API via the LAN IP

**Trade-off:** ESPHome currently uses `network_mode: host` which gives it full host network access (all ports, all interfaces). Macvlan would be **more restrictive** (container isolated from host) while still providing mDNS.

**Recommendation:** If you move HA to macvlan for discovery, consider moving ESPHome to macvlan too (instead of `network_mode: host`) for better isolation.

### 6. Home Assistant Configuration Changes

**trusted_proxies update:**

Current config:
```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
    - 172.16.0.0/12  # Docker bridge range
```

**With macvlan:** Traefik is still on a bridge network. If HA is on both macvlan and bridge, the bridge IP remains in the `172.16.0.0/12` range. **No change needed.**

**If Traefik were also on macvlan (not recommended):** Add Traefik's macvlan IP to `trusted_proxies`.

**External URL / Internal URL:**

- **external_url:** Continue using `https://home-assistant.${DOMAINNAME}` (Traefik)
- **internal_url:** Can optionally set to `http://192.168.1.200:8123` (macvlan IP) for LAN clients to bypass Traefik

**Trade-off:** Internal URL bypasses SSL unless you configure HA's own SSL cert. For this repo's security model, **do not set internal_url** — continue routing all traffic through Traefik.

---

## Security Implications

### 1. Attack Surface Expansion

**Current model:** Home Assistant is isolated behind Traefik. To reach HA, an attacker must:
1. Compromise Traefik, or
2. Compromise another container on the `home-assistant-frontend` bridge, or
3. Exploit a vulnerability in HA's web UI accessible via Traefik

**With macvlan:** Home Assistant has a LAN IP. Any device on the LAN can attempt to connect to HA's web UI (port 8123) or API.

**Threat scenarios:**
- **Compromised IoT device** (smart TV, thermostat) scans LAN and finds HA at 192.168.1.200:8123
- **Rogue device on guest Wi-Fi** (if guest network is not VLAN-isolated) can reach HA
- **ARP spoofing / MITM** on the LAN can intercept traffic to HA's macvlan IP

**Mitigations:**
1. **Do not publish port 8123** in the compose file — only allow access via Traefik on the bridge network
   - **Problem:** This defeats the purpose of macvlan (LAN devices can't reach HA directly for webhooks)
   - **Alternative:** Publish port 8123 but use HA's `ip_ban_enabled` and `login_attempts_threshold` to auto-ban attackers
2. **VLAN segmentation:** Put IoT devices on a separate VLAN (e.g., VLAN 20 IoT) with firewall rules:
   - Allow IoT → HA (192.168.1.200:8123)
   - Deny IoT → everything else
3. **Home Assistant firewall integration:** Enable fail2ban-style IP banning in HA's config
4. **Use `cap_drop: ALL`** even with macvlan (already in place in this repo) to limit container escape risks

**Recommendation for this repo:** The current bridge + Traefik model is more secure. If you must use macvlan, implement VLAN isolation.

### 2. Container Escape Impact

**Current model:** If an attacker exploits a container escape vulnerability (e.g., CVE in Docker or the HA application), they gain access to:
- The host's root filesystem (if they break out of the container)
- Other containers on the same Docker bridge (limited by network isolation)

**With macvlan:** If an attacker escapes the container, they gain access to:
- The host's root filesystem (same as before)
- **Direct LAN access** (can scan/attack other devices on 192.168.1.x)
- Other containers on the same macvlan subnet (if any)

**Impact:** The blast radius is larger — an escaped container can pivot to LAN devices, not just Docker bridges.

**Mitigation:** Same as current model:
- `cap_drop: ALL` (already in place)
- `read_only: true` (currently omitted for s6-overlay images like HA, but enforced where possible)
- `no-new-privileges: true` (already in place)
- Regular image updates via Renovate (already in place)

**Recommendation:** Macvlan does not increase escape risk, but it increases post-escape impact. Ensure HA's image is always up-to-date.

### 3. Traefik Bypass Risk

**Scenario:** If port 8123 is published on the macvlan network, users (and attackers) can bypass Traefik entirely by accessing `http://192.168.1.200:8123`.

**Consequences:**
- **No SSL** (HTTP only, unless HA is configured with its own cert)
- **No Traefik rate limiting** (middleware not applied)
- **No Gatus monitoring** (Gatus checks via Traefik, not direct IP)
- **No centralized logging** (Traefik's access logs don't capture direct IP access)

**Mitigation:**
- **Do not publish port 8123** in the compose file (rely on Traefik via the bridge network)
- **Or:** Accept that LAN clients can bypass Traefik (common in home labs; trade-off for functionality)

**Recommendation for this repo:** Do not publish port 8123 on macvlan. If local devices need to push webhooks, publish it but document the trade-off clearly.

### 4. Defense-in-Depth Erosion

This repository's security model is **defense-in-depth** (multiple layers):
1. Host firewall (nftables/iptables)
2. Traefik (SSL, auth, rate limiting)
3. Docker bridge NAT (private IPs, port isolation)
4. Container hardening (`cap_drop`, `no-new-privileges`, etc.)

**With macvlan:** Layer 3 (Docker NAT) is removed. If Traefik or HA has a vulnerability, there's one less barrier.

**Philosophical question:** Is the functionality gain (mDNS discovery, local push) worth weakening the security model?

**Answer for this repo:** Probably not. The existing architecture prioritizes security. If discovery is critical, use workarounds (manual IPs, mDNS reflector, `network_mode: host` for specific services) rather than macvlan.

---

## Implementation Options

### Option 1: Status Quo (Bridge Only)

**What:** Continue using the current bridge + Traefik setup. Accept that mDNS discovery does not work.

**Pros:**
- Simple, well-tested, secure
- No changes needed
- Aligns with repository's architecture and goals

**Cons:**
- Manual IP configuration for mDNS devices
- Local push webhooks require cloud relay or polling

**Recommendation:** **Preferred for this repository.** The current setup is mature and secure.

---

### Option 2: Dual-Network (Bridge + Macvlan)

**What:** Add macvlan for LAN access while keeping bridge networks for Traefik and `iot-backend`.

**Compose excerpt:**

```yaml
services:
  home-assistant:
    networks:
      home-assistant-macvlan:
        ipv4_address: 192.168.1.200
        mac_address: "02:42:c0:a8:01:c8"
        priority: 1000  # Default route
      home-assistant-frontend:
        priority: 900   # Traefik access
      iot-backend:
        # MQTT, ESPHome, etc.
    ports:
      - "8123:8123"  # Optional: publish on macvlan for local devices
    labels:
      # Traefik labels unchanged
```

**Required changes:**
1. Add macvlan network definition to `compose.yaml`
2. Add `MACVLAN_IP`, `MACVLAN_MAC`, `MACVLAN_PARENT_INTERFACE` to `.env`
3. Reserve IP 192.168.1.200 in router's DHCP settings
4. Update `configuration.yaml` if needed (probably not)
5. Test Traefik access, Gatus monitoring, MQTT communication, mDNS discovery

**Pros:**
- mDNS discovery works (Google Cast, HomeKit, etc.)
- Local push webhooks work (devices can reach 192.168.1.200:8123)
- Traefik integration preserved (via bridge network)
- Gatus monitoring continues working

**Cons:**
- Complex routing configuration (priority or manual `ip route`)
- HA exposed directly to LAN (weakened isolation)
- IP management overhead (manual reservation)
- Dual-network adds cognitive load for debugging

**Recommendation:** **Use only if mDNS discovery is critical** and you cannot use workarounds.

---

### Option 3: Macvlan Only (No Traefik for HA)

**What:** Move Home Assistant entirely to macvlan. Remove Traefik integration; access HA directly via LAN IP.

**Compose excerpt:**

```yaml
services:
  home-assistant:
    networks:
      home-assistant-macvlan:
        ipv4_address: 192.168.1.200
        mac_address: "02:42:c0:a8:01:c8"
      iot-backend:
        # MQTT, ESPHome, etc.
    ports:
      - "8123:8123"
    # Remove all Traefik labels
```

**Required changes:**
1. Remove `home-assistant-frontend` network
2. Remove Traefik labels from compose file
3. Update DNS to point `home-assistant.${DOMAINNAME}` to 192.168.1.200 (or remove DNS entry)
4. Configure HA's own SSL cert (via Let's Encrypt addon) if you want HTTPS
5. Remove Gatus monitoring (or change it to check `http://192.168.1.200:8123` directly)

**Pros:**
- Simplest macvlan setup (no dual-network routing)
- mDNS discovery works
- Local push webhooks work
- Lower latency (no Traefik reverse proxy hop)

**Cons:**
- **Breaks Traefik integration entirely** (no SSL via Traefik, no SSO, no Gatus monitoring)
- **Breaks repository's architecture** (every other service uses Traefik; HA would be the exception)
- HA must handle its own SSL cert (via HA's SSL addon or reverse proxy elsewhere)
- No centralized auth (HA's own login only)
- **Not recommended for this repository**

**Recommendation:** **Do not use.** This contradicts the repository's core principles.

---

### Option 4: mDNS Reflector (Bridge + Host-Mode Proxy)

**What:** Keep Home Assistant on bridge. Add a lightweight mDNS reflector container with `network_mode: host` to bridge LAN mDNS traffic to Docker bridges.

**Compose excerpt (new service):**

```yaml
services:
  mdns-reflector:
    image: docker.io/flungo/avahi:latest
    container_name: mdns-reflector
    network_mode: host
    restart: unless-stopped
    environment:
      - REFLECTOR_ENABLE_REFLECTOR=yes
    cap_add:
      - NET_ADMIN  # Required for mDNS multicast
```

**How it works:**
- `avahi-daemon` runs with `network_mode: host`
- It joins the mDNS multicast group (224.0.0.251) on both the LAN interface and Docker bridge interfaces
- Reflects mDNS queries/responses between them
- Home Assistant on bridge receives mDNS traffic as if it were on the LAN

**Pros:**
- No changes to Home Assistant's network config (stays on bridge)
- Traefik, Gatus, `iot-backend` all unchanged
- mDNS discovery works
- Minimal complexity (one extra container)

**Cons:**
- Another moving part (the reflector)
- `network_mode: host` for the reflector (less isolated than bridge, but read-only + `cap_drop` can mitigate)
- May not work for non-mDNS protocols (SSDP, IGMP)
- Reflector performance overhead (negligible for home use)

**Recommendation:** **Best compromise** if mDNS discovery is needed without sacrificing security architecture.

---

### Option 5: Per-Integration `network_mode: host` Helpers

**What:** Keep Home Assistant on bridge. For specific integrations that need LAN access, run lightweight helper containers with `network_mode: host`.

**Example: Wake-on-LAN helper**

```yaml
services:
  wol-helper:
    image: docker.io/library/alpine:3.23
    container_name: wol-helper
    network_mode: host
    restart: unless-stopped
    command: ["sh", "-c", "while true; do nc -luk 9 | etherwake -i eno1 -b <MAC>; done"]
    cap_drop:
      - ALL
    cap_add:
      - NET_RAW  # Required for Wake-on-LAN
```

Home Assistant calls the helper's API to send WoL packets.

**Pros:**
- Scoped to specific use cases (WoL, mDNS, etc.)
- Home Assistant stays on bridge (secure, simple)
- Helpers can be hardened individually

**Cons:**
- Multiple helpers = multiple containers to manage
- HA needs to integrate with each helper (HTTP API, MQTT, etc.)
- Not a general solution (each integration needs custom logic)

**Recommendation:** **Use sparingly** for edge cases (e.g., WoL). Not practical for mDNS (dozens of integrations).

---

## Recommendations

### For This Repository: Keep Bridge Networking

**Recommendation: Do not migrate Home Assistant to macvlan.**

**Rationale:**
1. **Security first:** This repository prioritizes defense-in-depth. Macvlan weakens network isolation.
2. **Architecture alignment:** Every service uses Traefik + bridge. Making HA an exception adds complexity.
3. **Functionality trade-off:** The current setup already supports:
   - Web UI access (Traefik)
   - Companion mobile app (Traefik)
   - MQTT communication (`iot-backend`)
   - DHCP device tracking (`NET_RAW` capability)
   - Matter/Thread (Matter Server uses `network_mode: host`)
4. **Workarounds exist:** For integrations that need mDNS, use manual IP configuration (one-time setup per device).

**When to reconsider:**
- If you add 10+ mDNS-based integrations and manual IP config becomes unmanageable
- If local push webhooks are critical for latency-sensitive automations (e.g., doorbell → light < 100ms)
- If you implement VLAN segmentation for IoT devices (mitigates LAN exposure risk)

---

### If You Must Use Macvlan: Dual-Network Setup

**If mDNS discovery is critical:**

1. **Use Option 2 (dual-network: macvlan + bridge)**
   - Preserves Traefik, Gatus, `iot-backend` integration
   - Enables mDNS discovery and local push webhooks
   - Requires routing config (Docker Compose `priority` or manual `ip route`)

2. **Reserve a static IP in your router's DHCP**
   - Example: 192.168.1.200 for Home Assistant

3. **Add macvlan network to `compose.yaml`:**

```yaml
networks:
  home-assistant-macvlan:
    name: home-assistant-macvlan
    driver: macvlan
    driver_opts:
      parent: eno1  # Your LAN interface
    ipam:
      driver: default
      config:
        - subnet: 192.168.1.0/24
          gateway: 192.168.1.1
          ip_range: 192.168.1.200/29  # Reserve .200-.207 for Docker
```

4. **Update `home-assistant` service:**

```yaml
services:
  home-assistant:
    networks:
      home-assistant-macvlan:
        ipv4_address: 192.168.1.200
        mac_address: "02:42:c0:a8:01:c8"
        priority: 1000  # Default route via macvlan
      home-assistant-frontend:
        priority: 900   # Traefik reachable via bridge
      iot-backend:
```

5. **Test thoroughly:**
   - Traefik access: `curl -k https://home-assistant.${DOMAINNAME}`
   - Gatus monitoring: Check Gatus dashboard
   - mDNS discovery: Try adding a Google Cast device
   - MQTT: Check Mosquitto logs for HA connections
   - Routing: `docker exec -it home-assistant ip route show`

6. **Document the exception:** Add a comment block in `compose.yaml` explaining why HA uses macvlan (for mDNS) and the security trade-offs.

---

### Alternative: mDNS Reflector (Recommended Compromise)

**If you need mDNS but want to keep the bridge model:**

1. **Deploy an mDNS reflector with `network_mode: host`** (Option 4)
   - Example image: `flungo/avahi` or `geekduck/mdns-repeater`
   - Reflects mDNS between LAN and Docker bridges
   - Home Assistant stays on bridge (no changes)

2. **Add the reflector service to `_bootstrap/compose.yaml`** (or a dedicated `services/mdns-reflector/compose.yaml`)

3. **Harden the reflector:**
   - `cap_drop: ALL` + `cap_add: NET_ADMIN`
   - `read_only: true`
   - `no-new-privileges: true`

4. **Test mDNS discovery** (Google Cast, HomeKit, etc.)

**Trade-off:** One `network_mode: host` container (reflector) vs. many macvlan containers. The reflector is simpler and preserves the existing architecture.

---

### Not Recommended: Macvlan-Only

**Do not use Option 3 (macvlan-only without Traefik).** This breaks the repository's core architecture and removes critical security layers (SSL via Traefik, Gatus monitoring, centralized auth for future services).

---

## Conclusion

Macvlan networking offers clear benefits for Home Assistant — native mDNS discovery, local push webhooks, and lower latency. However, it introduces significant complexity (dual-network routing), weakens security (LAN exposure), and contradicts this repository's defense-in-depth architecture.

**For this repository, the recommendation is:**

1. **Default: Keep bridge networking** (status quo). Accept manual IP configuration for mDNS devices as a trade-off for security and simplicity.

2. **If mDNS is critical: Use an mDNS reflector** (Option 4) to bridge LAN and Docker networks without changing Home Assistant's network config.

3. **If reflector is insufficient: Use dual-network macvlan** (Option 2) with careful routing configuration and VLAN segmentation for IoT devices.

4. **Never use macvlan-only** (Option 3) — this breaks Traefik, Gatus, and the repository's architecture.

Macvlan is a powerful tool, but it's best suited for simpler setups (like Techno Tim's Home Assistant-centric lab) or environments where network-level security (VLANs, firewalls) is already mature. For this repository's multi-service, security-first model, bridge networking with Traefik is the right choice.

---

## References

- [Docker Macvlan Networking Documentation](https://docs.docker.com/network/macvlan/)
- [Techno Tim: Docker on TrueNAS Like a PRO](https://technotim.com/posts/truenas-docker-pro/)
- [Home Assistant Network Requirements](https://www.home-assistant.io/installation/docker#network)
- [Home Assistant mDNS Discovery](https://www.home-assistant.io/integrations/zeroconf/)
- [This Repository: Architecture](ARCHITECTURE.md)
- [This Repository: Infrastructure](INFRASTRUCTURE.md)
- [Avahi mDNS Reflector](https://github.com/lathiat/avahi)
