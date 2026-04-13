# Outline

Outline is a modern knowledge base and wiki with real-time collaboration, Markdown support, and Azure AD (Microsoft Entra ID) authentication.

## Why

Team knowledge scattered across documents, chat messages, and emails is hard to find and maintain. Outline provides a clean, searchable wiki with structured collections, real-time collaborative editing, and full-text search. Self-hosting means your documentation stays private and under your control, with authentication handled by your existing Microsoft Entra ID tenant.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/outline/compose.yaml)

## Access

| URL                          | Description                                                 |
| ---------------------------- | ----------------------------------------------------------- |
| `https://docs.${DOMAINNAME}` | Web UI (Traefik forward-auth + Outline's own Azure AD auth) |

## Architecture

- **Images**: [outlinewiki/outline](https://github.com/outline/outline), [postgres](https://hub.docker.com/_/postgres), [pgautoupgrade](https://github.com/pgautoupgrade/docker-pgautoupgrade), [redis](https://hub.docker.com/_/redis), [tiredofit/db-backup](https://github.com/tiredofit/docker-db-backup)
- **User/Group**: `1000:1000` (image-internal `node` user — Outline does not support PUID/PGID)
- **Networks**: `outline-frontend` (Traefik-facing), `outline-backend` (internal — Postgres, Redis)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware

### User/Group Exception

The `outlinewiki/outline` image does not support custom PUID/PGID — it runs as the image-internal `node` user (UID/GID 1000). UID 3120 (`svc-app-outline`) is used only for the db-backup sidecar. The `outline-init` container pre-chowns `./data/data` to UID 1000 so the node process can write to the bind-mount. See the [upstream discussion](https://github.com/outline/outline/discussions/9452).

### Services

| Container            | Role                                                                      |
| -------------------- | ------------------------------------------------------------------------- |
| `outline-init`       | One-shot init: chowns `./data/data` to `1000:1000` (node user)            |
| `outline`            | Wiki application (Node.js)                                                |
| `outline-db-upgrade` | One-shot: pgautoupgrade for automatic Postgres major version upgrades     |
| `outline-db`         | PostgreSQL database                                                       |
| `outline-db-backup`  | One-shot nightly backup sidecar (restarted by `dccd.sh`)                  |
| `outline-redis`      | Redis — session/cache store (ephemeral, `--save ""` disables persistence) |

### Database Backup

`outline-db-backup` uses `tiredofit/db-backup` in `MODE=MANUAL` with `MANUAL_RUN_FOREVER=FALSE`. Backups are ZSTD-compressed, SHA1-checksummed, AES-encrypted with `DB_ENC_PASSPHRASE`, and retained for 48 hours.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing
- `OUTLINE_SECRET_KEY` / `OUTLINE_UTILS_SECRET` — application secrets
- `OUTLINE_DB_PASSWORD` — PostgreSQL password
- `OUTLINE_REDIS_PASSWORD` — Redis password
- `OUTLINE_AZURE_CLIENT_ID` / `OUTLINE_AZURE_CLIENT_SECRET` / `OUTLINE_AZURE_RESOURCE_APP_ID` / `OUTLINE_AZURE_TENANT_ID` — Microsoft Entra ID OIDC credentials
- `DB_ENC_PASSPHRASE` — encryption passphrase for database backups
- `NOTIFICATIONS_EMAIL_*` — SMTP settings for mention notifications and invitations

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/outline` in TrueNAS
2. Create a `svc-app-outline` group (GID 3120) and user (UID 3120) on the TrueNAS host (used by db-backup only)
3. Register an Azure AD application for OIDC authentication and populate the `OUTLINE_AZURE_*` secrets
4. Generate `OUTLINE_SECRET_KEY` and `OUTLINE_UTILS_SECRET` (e.g. `openssl rand -hex 32`)
5. Deploy — Outline runs database migrations automatically on first start

## Upgrade Notes

PostgreSQL major version upgrades are handled automatically by `outline-db-upgrade` (pgautoupgrade). Outline application migrations run automatically on startup — check the [Outline changelog](https://github.com/outline/outline/releases) before deploying major version bumps.
