# TubeSync

TubeSync is a YouTube channel and playlist synchronization tool that automatically downloads new videos from subscribed channels.

## Why

If you follow specific YouTube channels and want their content available in your Plex library for offline viewing on any device, TubeSync automates the entire workflow. Subscribe to channels, and new videos are downloaded automatically and organized in a Plex-compatible folder structure. Unlike MeTube (which handles individual on-demand downloads), TubeSync runs continuously and keeps your library in sync with YouTube.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/tubesync/compose.yaml)

## Access

| URL                              | Description                   |
| -------------------------------- | ----------------------------- |
| `https://tubesync.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [meeb/tubesync](https://github.com/meeb/tubesync) (custom init script + supervisord)
- **User/Group**: `PUID=3118` / `PGID=3200` (`svc-app-tubesync:media`)
- **Networks**: `tubesync-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **Downloads**: `/mnt/archive-pool/content/media/youtube/tubesync`

### Root-Start Exceptions

TubeSync uses its own `start.sh` init script (similar to s6-overlay) that creates the PUID:PGID user, chowns `/config`, and launches supervisord. See [Architecture](../ARCHITECTURE.md) for the full rationale:

- **`read_only` is omitted**: init script writes to the root filesystem during startup
- **`user:` is omitted**: init script requires root for privilege management
- **`cap_add`**: `CHOWN`, `SETUID`, `SETGID`, `SETPCAP`

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/tubesync` in TrueNAS
2. Create a `svc-app-tubesync` group (GID 3118) and user (UID 3118, primary group `media` GID 3200) on the TrueNAS host
3. Deploy and add YouTube channels/playlists in the web UI

## Upgrade Notes

No special upgrade procedures. Image updates are managed by Renovate.
