# Memos

[Memos](https://www.usememos.com/) is a lightweight, self-hosted note-taking
service — a privacy-first, open-source hub for capturing memos, thoughts, and
ideas in Markdown.

## Why

Memos provides a fast, minimal alternative to heavier knowledge bases for
quick-capture notes. It runs as a single self-contained Go binary backed by an
embedded SQLite database, making it one of the simplest stateful services to
operate — no external database or cache required.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/memos/compose.yaml)

## Access

| URL                           | Description                   |
| ----------------------------- | ----------------------------- |
| `https://memos.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [usememos/memos](https://github.com/usememos/memos) (Go binary)
- **User/Group**: `3128:3128` (`svc-app-memos`)
- **Networks**: `memos-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **Database**: Embedded SQLite (`MEMOS_DRIVER=sqlite`), stored under `./data`
- **Init container**: `memos-init` chowns `./data` to `3128:3128` so the
  non-root process can write its database and uploaded attachments
- **Health check**: `GET /healthz` (returns `Service ready.`)

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/memos` in TrueNAS
2. Create a `svc-app-memos` group (GID 3128) and user (UID 3128) on the TrueNAS host
3. Deploy — the init container prepares `./data` and Memos initialises its SQLite
   database automatically
4. Open `https://memos.${DOMAINNAME}` and complete the first-run admin sign-up

## Upgrade Notes

Memos applies database schema migrations automatically on startup. Redeploys
replace the container cleanly; the SQLite database persists in `./data`. Image
updates are managed by Renovate.
