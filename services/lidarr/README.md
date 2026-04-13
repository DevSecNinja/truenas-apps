# Lidarr

Lidarr is a music collection manager that automates searching, downloading, and organizing your music library.

## Why

Manually tracking music releases across artists and managing downloads is time-consuming. Lidarr monitors your wanted list, searches indexers automatically, sends downloads to your client (SABnzbd/qBittorrent), and imports completed files into your library with proper naming. Combined with Plex, it provides a fully automated music pipeline from release to playback.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/lidarr/compose.yaml)

## Access

| URL                            | Description                   |
| ------------------------------ | ----------------------------- |
| `https://lidarr.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [linuxserver/lidarr](https://github.com/linuxserver/docker-lidarr) (s6-overlay)
- **User/Group**: `PUID=3112` / `PGID=3200` (`svc-app-lidarr:media`)
- **Networks**: `arr-egress` (macvlan, default route), `lidarr-frontend` (bridge, Traefik-facing, `internal: true`), `arr-stack-backend` (internal bridge for arr inter-communication)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **Media mount**: `/mnt/archive-pool/content` → `/data` — same filesystem for hardlink support

### s6-overlay Exceptions

See [Architecture](../ARCHITECTURE.md) for the full rationale. `read_only` and `user:` are omitted; `cap_add` includes `CHOWN`, `SETUID`, `SETGID`, `SETPCAP`.

### Networking

Uses the arr-stack egress pattern — `arr-egress` is listed first for default route, `lidarr-frontend` is `internal: true`.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing
- `EGRESS_IP` / `EGRESS_MAC` — static IP and MAC for the arr-egress macvlan network

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/lidarr` in TrueNAS
2. Create a `svc-app-lidarr` group (GID 3112) and user (UID 3112, primary group `media` GID 3200) on the TrueNAS host
3. Deploy and configure root folders, download clients, and indexers in the web UI

## Upgrade Notes

No special upgrade procedures. s6-overlay and Lidarr handle migrations automatically. Image updates are managed by Renovate.
