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

- **Image**: [meeb/tubesync](https://github.com/meeb/tubesync) (s6-overlay init system)
- **User/Group**: `PUID=3118` / `PGID=3200` (`svc-app-tubesync:media`)
- **Networks**: `tubesync-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **Downloads**: `/mnt/archive-pool/content/media/youtube/tubesync`

### Root-Start Exceptions

TubeSync's s6-overlay `tubesync-config-init` service runs as root at startup: it sets the `app` user's UID/GID from `PUID`/`PGID`, then `chown`s and `chmod`s `/run/app` (mode 0700) and `/config` directories (mode 0755). Service startup scripts finish root-level setup before dropping privileges to `app`. See [Architecture](../ARCHITECTURE.md) for the full rationale:

- **`read_only` is omitted**: the init service writes to the root filesystem during startup
- **`user:` is omitted**: the init service requires root for privilege management and to re-permission `/config`
- **`cap_add`**: `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `SETPCAP` — `FOWNER` allows init to `chmod` app-owned files; `DAC_OVERRIDE` lets root startup services create `/config/state/hat` under app-owned mode 0755 directories and access `/run/app` (mode 0700). `CHOWN` and `FOWNER` alone do not bypass those access permissions

`cap_drop: ALL` and `no-new-privileges` remain enabled. These startup capabilities do not replace running the application as `PUID`/`PGID`.

### Restart Permission Errors

`Permission denied` errors for `/config/state/hat` or `/run/app` can occur when the deployed container lacks `DAC_OVERRIDE`, even though startup runs as root. Redeploy the changed Compose configuration through `dccd` to recreate the container with the added capability; `docker restart` alone cannot apply capability changes. This fix does not require a recursive permission reset or deleting data.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/tubesync` in TrueNAS
2. Create a `svc-app-tubesync` group (GID 3118) and user (UID 3118, primary group `media` GID 3200) on the TrueNAS host
3. Deploy and add YouTube channels/playlists in the web UI

## Upgrade Notes

No special upgrade procedures. Image updates are managed by Renovate.
