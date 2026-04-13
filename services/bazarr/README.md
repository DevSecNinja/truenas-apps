# Bazarr

Bazarr is a companion application to Sonarr and Radarr that automatically downloads subtitles for your media library.

## Why

Finding quality subtitles for every movie and TV episode is tedious manual work. Bazarr automates subtitle management — it monitors your Sonarr and Radarr libraries, searches multiple subtitle providers, and downloads the best match automatically. This keeps your media library accessible for non-native speakers or hearing-impaired viewers without any ongoing effort.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/bazarr/compose.yaml)

## Access

| URL                            | Description                   |
| ------------------------------ | ----------------------------- |
| `https://bazarr.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [linuxserver/bazarr](https://github.com/linuxserver/docker-bazarr) (s6-overlay)
- **User/Group**: `PUID=3111` / `PGID=3200` (`svc-app-bazarr:media`) — s6-overlay handles privilege drop internally
- **Networks**: `arr-egress` (macvlan, default route for internet traffic), `bazarr-frontend` (bridge, Traefik-facing, `internal: true`), `arr-stack-backend` (internal bridge for arr app inter-communication)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **Media mount**: `/mnt/archive-pool/content` → `/data` — downloads and media on the same filesystem for hardlink support

### s6-overlay Exceptions

This container uses LinuxServer's s6-overlay init system. See [Architecture](../ARCHITECTURE.md) for the full rationale:

- **`read_only` is omitted**: s6-overlay writes to the root filesystem at startup
- **`user:` is omitted**: s6-overlay starts as root and drops to PUID:PGID internally
- **`cap_add`**: `CHOWN`, `SETUID`, `SETGID`, `SETPCAP` for s6-overlay privilege management

### Networking

Bazarr uses the arr-stack egress network pattern. `arr-egress` (macvlan) is listed first so Docker assigns it as the default route — all internet traffic exits through the egress network. The `bazarr-frontend` bridge is `internal: true`, preventing internet egress via the Traefik bridge.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing
- `EGRESS_IP` / `EGRESS_MAC` — static IP and MAC for the arr-egress macvlan network

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/bazarr` in TrueNAS
2. Create a `svc-app-bazarr` group (GID 3111) and user (UID 3111, primary group `media` GID 3200) on the TrueNAS host
3. Deploy the stack and configure subtitle providers in the web UI
4. Connect Bazarr to Sonarr and Radarr via their API keys (Settings → Sonarr / Radarr)

## Upgrade Notes

No special upgrade procedures. s6-overlay and Bazarr handle migrations automatically. Image updates are managed by Renovate.
