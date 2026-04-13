# MeTube

MeTube is a web-based YouTube downloader powered by yt-dlp, with a clean UI for downloading individual videos and audio.

## Why

Sometimes you need to save a specific video or podcast episode for offline viewing or archival. MeTube provides a simple paste-and-download interface without needing CLI tools on your workstation. Downloads land directly on the NAS media library where Plex can pick them up.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/metube/compose.yaml)

## Access

| URL                            | Description                   |
| ------------------------------ | ----------------------------- |
| `https://metube.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [alexta69/metube](https://github.com/alexta69/metube) (Python/aiohttp)
- **User/Group**: `3107:3200` (`svc-app-metube:media`) — runs directly as non-root, no s6-overlay
- **Networks**: `metube-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **Downloads**: Video to `/mnt/archive-pool/content/media/youtube/metube`, temp files to a size-capped tmpfs (`4G`)

### Services

| Container     | Role                                                |
| ------------- | --------------------------------------------------- |
| `metube-init` | One-shot init: chowns `./data/state` to `3107:3200` |
| `metube`      | Web UI and yt-dlp download engine                   |

### File Permissions

`UMASK=002` produces group-writable files (`664`/`775`) so all `media` group (GID 3200) members — including Plex, TubeSync, and the arr apps — can read downloaded content.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/metube` in TrueNAS
2. Create a `svc-app-metube` group (GID 3107) and user (UID 3107, primary group `media` GID 3200) on the TrueNAS host
3. Deploy — MeTube is ready to use immediately

## Upgrade Notes

No special upgrade procedures. Image updates are managed by Renovate.
