# hadiscover API

hadiscover is a public-facing API backend for the [Home Assistant Discover](https://github.com/DevSecNinja/hadiscover) project, providing device discovery data for the Home Assistant ecosystem.

## Why

This is a first-party project — the API backend serves device metadata used by the hadiscover frontend. Self-hosting ensures full control over the data pipeline and avoids reliance on third-party hosting.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/hadiscover/compose.yaml)

## Access

| URL                          | Description                                |
| ---------------------------- | ------------------------------------------ |
| `https://api.hadiscover.com` | Public API endpoint (no auth — public API) |

## Architecture

- **Image**: [devsecninja/hadiscover/backend](https://github.com/DevSecNinja/hadiscover) (Python)
- **User/Group**: `3121:3121` (`svc-app-hadiscover`)
- **Networks**: `hadiscover-frontend` (shared with cloudflared)
- **Reverse proxy**: Cloudflare Tunnel via cloudflared — public API, no authentication. Traffic flows: internet → Cloudflare edge → cloudflared → hadiscover-api:8000
- **TLS**: Terminated at Cloudflare's edge (not by Traefik)

### Services

| Container         | Role                                             |
| ----------------- | ------------------------------------------------ |
| `hadiscover-init` | One-shot init: chowns `./data` to `3121:3121`    |
| `hadiscover-api`  | Python API backend serving device discovery data |

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `HADISCOVER_GITHUB_TOKEN` — GitHub API token for fetching device data

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/hadiscover` in TrueNAS
2. Create a `svc-app-hadiscover` group (GID 3121) and user (UID 3121) on the TrueNAS host
3. Set `HADISCOVER_GITHUB_TOKEN` in `secret.sops.env`
4. Deploy — the API starts serving on port 8000, accessible via Cloudflare Tunnel

## Upgrade Notes

No special upgrade procedures. Image updates are managed by Renovate.
