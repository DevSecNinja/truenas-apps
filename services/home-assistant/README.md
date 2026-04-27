# Home Assistant

Home Assistant is an open-source home automation platform that integrates with thousands of smart home devices and services.

## Why

Home Assistant consolidates control of all your smart home devices — lights, sensors, locks, thermostats, media players — into a single local interface. Running it locally means automations execute without internet latency or cloud dependency, and your device data stays on your network. The self-hosted approach also avoids vendor lock-in from closed-ecosystem hubs.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/home-assistant/compose.yaml)

## Access

| URL                                    | Description                                                          |
| -------------------------------------- | -------------------------------------------------------------------- |
| `https://home-assistant.${DOMAINNAME}` | Web UI and API (no forward-auth — HA handles its own authentication) |

## Architecture

- **Image**: [home-assistant/home-assistant](https://github.com/home-assistant/core) (s6-overlay)
- **Networks**: `ha-macvlan` (primary — real LAN MAC/IP for device discovery), `home-assistant-frontend` (Traefik-facing bridge, `internal: true`), `iot-backend` (internal IoT communication — connects to Mosquitto, ESPHome, Frigate, wmbusmeters)
- **Reverse proxy**: Traefik with `chain-no-auth@file` middleware — HA enforces its own login, MFA, and long-lived access tokens. Forward-auth would break the Companion mobile app's direct OAuth flow.

### s6-overlay Exceptions

Home Assistant uses s6-overlay internally. See [Architecture](../ARCHITECTURE.md) for the full rationale:

- **`user:` is omitted**: s6-overlay starts as root and drops privileges internally
- **`read_only` is omitted**: s6-overlay needs a writable root filesystem
- **`cap_add`**: `CHOWN`, `SETUID`, `SETGID`, `SETPCAP` (standard s6-overlay set) + `NET_RAW` (required by HA's DHCP watcher integration for raw `AF_PACKET` sockets — without it HA logs `[Errno 1] Operation not permitted`)

### Init Container

`home-assistant-init` seeds template config files from `./config` into `./data/config/` on first deploy only (`cp -n` — never overwrites). These templates include `configuration.yaml` (with `http: trusted_proxies` for Traefik), and empty stub files (`automations.yaml`, `scripts.yaml`, `scenes.yaml`) required by HA's `!include` directives. Without these stubs, HA enters recovery mode and ignores the `http:` block.

## Macvlan Networking

Home Assistant is assigned a dedicated static IP and MAC address on the LAN via a `ha-macvlan` Docker network, making it a real Layer-2 citizen on the network. macvlan was chosen:

- **Over `network_mode: host`** (used by Matter Server): HA also needs Traefik reverse-proxy access, which requires a shared bridge network — host-mode removes the container from all Docker bridge networks.
- **Over bridge-only** (the previous setup): bridge containers are isolated from the Layer-2 broadcast domain — they cannot receive mDNS multicast, UPnP/SSDP, or LAN broadcast packets.

### Pros

- **mDNS/Bonjour discovery**: Chromecast, Apple TV, Philips Hue, ESPHome devices, HomeKit bridges, and other Zeroconf services are auto-discovered without manual IP configuration
- **UPnP/SSDP discovery**: media players, smart TVs, and network routers are visible
- **DHCP device tracking**: HA receives DHCP broadcast packets as a real LAN citizen (requires `NET_RAW` for raw socket capture regardless of network mode)
- **Wake-on-LAN**: WoL magic packets are delivered directly on the LAN broadcast domain
- **Matter/Thread**: IP-based commissioning and communication work without a separate mDNS reflector
- **Stable identity**: the HA instance always appears on the LAN with its own DHCP reservation or static IP, not behind the TrueNAS host IP

### Cons / Trade-offs

- **Host isolation**: the TrueNAS host cannot reach HA's macvlan IP directly (Linux kernel macvlan limitation). A `macvlan` shim interface on the TrueNAS host is required if direct host-to-HA access is needed (e.g. `ssh` or host-level `curl`). Traefik and Docker service-to-service communication are unaffected because they use the bridge networks.
- **Static IP required**: HA needs a dedicated static IP on the LAN subnet (reserve it in the DHCP server or set it statically)
- **IP/MAC allocation**: two more variables (`HA_LAN_IP`, `HA_LAN_MAC`) must be added to `secret.sops.env`
- **Network config complexity**: four environment variables describe the macvlan network (`HA_LAN_PARENT`, `HA_LAN_SUBNET`, `HA_LAN_GATEWAY`, `HA_LAN_IP`)

### Network Ordering

`ha-macvlan` is listed first in `networks:` so Docker assigns it as `eth0` and uses `HA_LAN_GATEWAY` as the default route. `home-assistant-frontend` and `iot-backend` are listed second and third — Docker adds only specific /16 bridge routes for them, leaving the macvlan default route intact.

### Host Macvlan Shim

If direct TrueNAS host → HA communication is needed (e.g. for diagnostics), a host-side macvlan shim interface is required:

```sh
ip link add ha-macvlan-shim link <parent> type macvlan mode bridge
ip addr add <host-ip-in-same-subnet>/24 dev ha-macvlan-shim
ip link set ha-macvlan-shim up
```

Docker Compose deploys via `dccd.sh` use the Docker socket directly and do not require this shim.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing
- `HA_LAN_IP` — HA's static IP address on the LAN (e.g. `192.168.1.200`) — must be outside the DHCP pool or reserved
- `HA_LAN_MAC` — HA's MAC address for the macvlan interface (use a locally administered MAC, e.g. `02:42:c0:a8:01:c8`) — register in the DHCP server for consistent assignment
- `HA_LAN_PARENT` — host NIC to attach the macvlan to (e.g. `eth0`, `bond0`) — must be the interface on the same LAN segment as IoT devices
- `HA_LAN_SUBNET` — LAN subnet in CIDR notation (e.g. `192.168.1.0/24`)
- `HA_LAN_GATEWAY` — LAN default gateway (e.g. `192.168.1.1`)
- `NOTIFICATIONS_EMAIL_HOST` — SMTP server hostname for db-backup notifications
- `NOTIFICATIONS_EMAIL_DOMAIN` — SMTP domain
- `NOTIFICATIONS_EMAIL_PORT` — SMTP port
- `NOTIFICATIONS_EMAIL_USERNAME` — SMTP username
- `NOTIFICATIONS_EMAIL_PASSWORD` — SMTP password
- `NOTIFICATIONS_EMAIL_TO` — notification recipient email address
- `NOTIFICATIONS_EMAIL_FROM` — notification sender email address
- `DB_ENC_PASSPHRASE` — encryption passphrase for backup files

## Database Backup

The `home-assistant-db-backup` sidecar (tiredofit/db-backup with s6-overlay) runs a one-shot `sqlite3 .dump` of the Home Assistant recorder database (`home-assistant_v2.db`), producing a consistent SQL snapshot even while HA is running in WAL mode. The backup is compressed with ZSTD and encrypted with `${DB_ENC_PASSPHRASE}`.

- **Mode**: `MANUAL` with `MANUAL_RUN_FOREVER=FALSE` — runs one backup and exits. The nightly CD script (`dccd.sh`) restarts the container fresh each run.
- **Notifications**: Sends email notifications on backup success/failure via SMTP.
- **Storage**: Backups are written to `./backups/db-backup/` (gitignored). Old backups are cleaned up after 48 hours (`DEFAULT_CLEANUP_TIME=2880`).
- **Network**: `network_mode: none` — the backup container has no network access.

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/home-assistant` in TrueNAS
2. Add the five macvlan variables (`HA_LAN_IP`, `HA_LAN_MAC`, `HA_LAN_PARENT`, `HA_LAN_SUBNET`, `HA_LAN_GATEWAY`) to `secret.sops.env`. Reserve `HA_LAN_IP` in your DHCP server (or set a static IP outside the DHCP pool) and verify the macvlan parent interface with `ip link show` on the TrueNAS host.
3. Deploy the stack — no TrueNAS service account needed (s6-overlay manages permissions internally)
4. Complete the HA onboarding wizard in the web UI
5. Configure integrations for your smart home devices

## Upgrade Notes

Home Assistant uses the `beta` tag. Review the [release notes](https://www.home-assistant.io/blog/) before deploying major version changes — breaking changes to integrations are common. The init container uses `cp -n`, so config updates from the repo are only applied on first deploy — subsequent config changes should be made through the HA UI or by manually updating `./data/config/`.
