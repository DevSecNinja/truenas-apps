# Draw.io

Draw.io is a browser-based flowchart and diagram editor with export to PNG, SVG, PDF, and more.

## Why

Having a self-hosted diagramming tool means your diagrams never leave your network, and there's no dependency on draw.io's public servers being available. It's fully stateless — no database, no persistent storage — making it one of the simplest services to run.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/drawio/compose.yaml)

## Access

| URL                          | Description                   |
| ---------------------------- | ----------------------------- |
| `https://draw.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [jgraph/drawio](https://github.com/jgraph/drawio) (Jetty-based)
- **User/Group**: `3119:3119` (`svc-app-drawio`)
- **Networks**: `drawio-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **Stateless**: No persistent volumes, no init container — all writable paths covered by tmpfs

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/drawio` in TrueNAS
2. Create a `svc-app-drawio` group (GID 3119) and user (UID 3119) on the TrueNAS host
3. Deploy — no additional configuration needed

## Upgrade Notes

No special upgrade procedures. Stateless container — redeploy replaces it cleanly. Image updates are managed by Renovate.
