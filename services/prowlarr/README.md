# Prowlarr

Prowlarr is an indexer manager that integrates with the arr stack (Sonarr, Radarr, Lidarr) to centrally manage and sync indexer/tracker configurations.

## Why

Without Prowlarr, you'd need to configure indexers separately in every arr app — and keep them in sync when credentials change or indexers go down. Prowlarr manages all indexers in one place and pushes configurations to Sonarr, Radarr, and Lidarr automatically via their APIs.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/prowlarr/compose.yaml)

## Access

| URL                              | Description                   |
| -------------------------------- | ----------------------------- |
| `https://prowlarr.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [linuxserver/prowlarr](https://github.com/linuxserver/docker-prowlarr) (s6-overlay)
- **User/Group**: `PUID=3113` / `PGID=3113` (`svc-app-prowlarr`) — own group, no media file access needed
- **Networks**: `arr-egress` (macvlan, default route), `prowlarr-frontend` (bridge, Traefik-facing, `internal: true`), `arr-stack-backend` (internal bridge for arr inter-communication)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware

### s6-overlay Exceptions

See [Architecture](../ARCHITECTURE.md) for the full rationale. `read_only` and `user:` are omitted; `cap_add` includes `CHOWN`, `SETUID`, `SETGID`, `SETPCAP`.

### Networking

Uses the arr-stack egress pattern — `arr-egress` is listed first for default route, `prowlarr-frontend` is `internal: true`.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing
- `EGRESS_IP` / `EGRESS_MAC` — static IP and MAC for the arr-egress macvlan network

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/prowlarr` in TrueNAS
2. Create a `svc-app-prowlarr` group (GID 3113) and user (UID 3113) on the TrueNAS host
3. Deploy and add indexers in the web UI
4. Connect Prowlarr to Sonarr, Radarr, and Lidarr via their API keys (Settings → Apps)

## Upgrade Notes

No special upgrade procedures. s6-overlay and Prowlarr handle migrations automatically. Image updates are managed by Renovate.
