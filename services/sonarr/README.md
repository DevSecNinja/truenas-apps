# Sonarr

Sonarr is a TV series collection manager that automates searching, downloading, and organizing your TV library.

## Why

Keeping up with TV series releases — checking for new episodes, finding quality downloads, renaming and organizing files — is tedious manual work. Sonarr automates the entire pipeline: it monitors your series list, searches indexers when new episodes air, sends downloads to your client, imports with proper naming, and triggers Plex library updates. Combined with Prowlarr and hardlinks, it's a fully hands-off TV management system.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/sonarr/compose.yaml)

## Access

| URL                            | Description                   |
| ------------------------------ | ----------------------------- |
| `https://sonarr.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [linuxserver/sonarr](https://github.com/linuxserver/docker-sonarr) (s6-overlay)
- **User/Group**: `PUID=3116` / `PGID=3200` (`svc-app-sonarr:media`)
- **Networks**: `arr-egress` (macvlan, default route), `sonarr-frontend` (bridge, Traefik-facing, `internal: true`), `arr-stack-backend` (internal bridge for arr inter-communication)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **Media mount**: `/mnt/archive-pool/content` → `/data` — same filesystem for hardlink support

### s6-overlay Exceptions

See [Architecture](../ARCHITECTURE.md) for the full rationale. `read_only` and `user:` are omitted; `cap_add` includes `CHOWN`, `SETUID`, `SETGID`, `SETPCAP`.

### Networking

Uses the arr-stack egress pattern — `arr-egress` is listed first for default route, `sonarr-frontend` is `internal: true`.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing
- `EGRESS_IP` / `EGRESS_MAC` — static IP and MAC for the arr-egress macvlan network

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/sonarr` in TrueNAS
2. Create a `svc-app-sonarr` group (GID 3116) and user (UID 3116, primary group `media` GID 3200) on the TrueNAS host
3. Deploy and configure root folders, download clients, and quality profiles in the web UI

## Upgrade Notes

No special upgrade procedures. s6-overlay and Sonarr handle migrations automatically. Image updates are managed by Renovate.
