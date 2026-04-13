# Dozzle

Dozzle is a lightweight, real-time container log viewer with a web-based interface.

## Why

When debugging container issues, tailing logs via `docker logs` on the CLI is slow and cumbersome — especially when you need to compare logs across multiple containers. Dozzle provides an instant, searchable web UI for all container logs without storing anything on disk. It's read-only by design, so there's no risk of it modifying your environment.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/dozzle/compose.yaml)

## Access

| URL                          | Description                   |
| ---------------------------- | ----------------------------- |
| `https://logs.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [amir20/dozzle](https://github.com/amir20/dozzle) (scratch-based Go binary)
- **User/Group**: `3109:3109` (`svc-app-dozzle`)
- **Networks**: `dozzle-frontend` (Traefik-facing), `dozzle-backend` (internal — Docker socket proxy)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware

### Services

| Container             | Role                                                                                                    |
| --------------------- | ------------------------------------------------------------------------------------------------------- |
| `dozzle-init`         | One-shot init: chowns `./data` to `3109:3109`                                                           |
| `dozzle`              | Log viewer web UI — connects to Docker via socket proxy                                                 |
| `dozzle-docker-proxy` | LinuxServer socket-proxy — read-only Docker API access (`CONTAINERS=1`, `EVENTS=1`, `INFO=1`, `POST=0`) |

### Docker Socket Proxy

Dozzle never mounts the Docker socket directly. A dedicated [LinuxServer socket-proxy](https://github.com/linuxserver/docker-socket-proxy) instance provides read-only API access on the internal backend network. This limits the blast radius if Dozzle were compromised.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/dozzle` in TrueNAS
2. Create a `svc-app-dozzle` group (GID 3109) and user (UID 3109) on the TrueNAS host
3. Deploy — Dozzle auto-discovers all running containers via the socket proxy

## Upgrade Notes

No special upgrade procedures. Image updates are managed by Renovate.
