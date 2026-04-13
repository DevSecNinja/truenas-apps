# qBittorrent

qBittorrent is a feature-rich BitTorrent client with a web interface for remote management.

## Why

A headless torrent client running on the NAS means downloads happen 24/7 without tying up a workstation. qBittorrent's web UI provides full control over torrents remotely, and the arr stack (Sonarr, Radarr) integrates with it directly for automated media downloading. The egress network ensures all torrent traffic exits through a dedicated network interface.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/qbittorrent/compose.yaml)

## Access

| URL                                 | Description                                                    |
| ----------------------------------- | -------------------------------------------------------------- |
| `https://qbittorrent.${DOMAINNAME}` | Web UI (Traefik with `chain-auth-qbittorrent@file` middleware) |

## Architecture

- **Image**: [linuxserver/qbittorrent](https://github.com/linuxserver/docker-qbittorrent) (s6-overlay)
- **User/Group**: `PUID=3114` / `PGID=3200` (`svc-app-qbittorrent:media`)
- **Networks**: `arr-egress` (macvlan, default route), `qbittorrent-frontend` (bridge, Traefik-facing, `internal: true`), `arr-stack-backend` (internal bridge for arr inter-communication)
- **Reverse proxy**: Traefik with `chain-auth-qbittorrent@file` middleware (dedicated middleware for qBittorrent's UI quirks)
- **Media mount**: `/mnt/archive-pool/content` → `/data` — same filesystem for hardlink support

### s6-overlay Exceptions

See [Architecture](../ARCHITECTURE.md) for the full rationale. `read_only` and `user:` are omitted; `cap_add` includes `CHOWN`, `SETUID`, `SETGID`, `SETPCAP`.

### Networking

Uses the arr-stack egress pattern — `arr-egress` is listed first for default route, `qbittorrent-frontend` is `internal: true`. Torrent traffic (port 6881) exits via the egress network.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing
- `EGRESS_IP` / `EGRESS_MAC` — static IP and MAC for the arr-egress macvlan network

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/qbittorrent` in TrueNAS
2. Create a `svc-app-qbittorrent` group (GID 3114) and user (UID 3114, primary group `media` GID 3200) on the TrueNAS host
3. Deploy and configure download paths and connection settings in the web UI

## Upgrade Notes

No special upgrade procedures. s6-overlay and qBittorrent handle migrations automatically. Image updates are managed by Renovate.
