# SABnzbd

SABnzbd is a Usenet download client with a web interface, automated post-processing, and NZB file management.

## Why

Usenet downloading requires a specialized client that handles NZB parsing, server connections, download verification, and automatic extraction. SABnzbd does all of this with a polished web UI, and integrates directly with the arr stack (Sonarr, Radarr) for fully automated media acquisition.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/sabnzbd/compose.yaml)

## Access

| URL                             | Description                   |
| ------------------------------- | ----------------------------- |
| `https://sabnzbd.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [linuxserver/sabnzbd](https://github.com/linuxserver/docker-sabnzbd) (s6-overlay)
- **User/Group**: `PUID=3115` / `PGID=3200` (`svc-app-sabnzbd:media`)
- **Networks**: `arr-egress` (macvlan, default route), `sabnzbd-frontend` (bridge, Traefik-facing, `internal: true`), `arr-stack-backend` (internal bridge for arr inter-communication)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **Media mount**: `/mnt/archive-pool/content` → `/data` — same filesystem for hardlink support

### s6-overlay Exceptions

See [Architecture](../ARCHITECTURE.md) for the full rationale. `read_only` and `user:` are omitted; `cap_add` includes `CHOWN`, `SETUID`, `SETGID`, `SETPCAP`.

### Networking

Uses the arr-stack egress pattern — `arr-egress` is listed first for default route, `sabnzbd-frontend` is `internal: true`.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing
- `EGRESS_IP` / `EGRESS_MAC` — static IP and MAC for the arr-egress macvlan network

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/sabnzbd` in TrueNAS
2. Create a `svc-app-sabnzbd` group (GID 3115) and user (UID 3115, primary group `media` GID 3200) on the TrueNAS host
3. Deploy and configure Usenet server credentials and download paths in the web UI

## Upgrade Notes

No special upgrade procedures. s6-overlay and SABnzbd handle migrations automatically. Image updates are managed by Renovate.
