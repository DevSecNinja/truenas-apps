# Excalidraw

Excalidraw is a browser-based virtual whiteboard for sketching hand-drawn-style diagrams collaboratively.

## Why

Self-hosting Excalidraw keeps your sketches and brainstorming sessions private — nothing is sent to external servers. It's completely stateless (drawings are stored in the browser or exported manually), making it trivial to deploy and maintain.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/excalidraw/compose.yaml)

## Access

| URL                                | Description                   |
| ---------------------------------- | ----------------------------- |
| `https://excalidraw.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [excalidraw/excalidraw](https://github.com/excalidraw/excalidraw) (nginx:alpine serving static files)
- **Networks**: `excalidraw-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **Stateless**: No persistent volumes, no init container

### nginx Exceptions

The nginx image starts as root to bind port 80, then drops to the internal `nginx` user for worker processes:

- **`user:` is omitted**: nginx master requires root for privileged port binding and privilege dropping
- **`cap_add`**: `CHOWN`, `SETUID`, `SETGID`, `SETPCAP` (privilege management) + `NET_BIND_SERVICE` (port 80 binding)
- **`read_only: true`** is supported via tmpfs mounts for `/var/cache/nginx`, `/var/run`, and `/tmp`

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing

## First-Run Setup

1. Deploy — no dataset, service account, or configuration needed. Excalidraw is fully stateless.

## Upgrade Notes

No special upgrade procedures. Stateless container. Image updates are managed by Renovate.
