# Bitwarden Lite

[Bitwarden Lite](https://bitwarden.com/help/install-and-deploy-lite/) is the official single-container self-hosted Bitwarden server, designed for personal use and home labs. It bundles nginx and all Bitwarden backend services (api, identity, admin, icons, notifications, sso, scim, events) into one image orchestrated by `supervisord`.

> Bitwarden Lite was renamed from "Bitwarden Unified" in December 2025 when it exited beta.

## Why

The standard Bitwarden self-hosted deployment runs ~10 containers and requires MSSQL, with substantial memory overhead. Bitwarden Lite trades that footprint for simplicity:

- Single container, multi-arch (amd64, arm64, arm/v7)
- ~200 MB minimum RAM
- Choice of database backend — SQLite, PostgreSQL, MySQL/MariaDB, or MSSQL
- Official Bitwarden image — full client compatibility (web vault, browser extensions, mobile, desktop)

This deployment uses **SQLite** for zero database management. The `vault.db` file lives in `./data/` alongside attachments and the IdentityServer certificate.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/bitwarden/compose.yaml)

## Access

| URL                                 | Auth                                   | Description                                     |
| ----------------------------------- | -------------------------------------- | ----------------------------------------------- |
| `https://vault.${DOMAINNAME}`       | Bitwarden built-in (account password)  | Web vault, mobile/desktop/browser-extension API |
| `https://vault.${DOMAINNAME}/admin` | Traefik Forward Auth + Bitwarden admin | System administrator portal (defence in depth)  |

The `/admin` panel sits behind both Traefik Forward Auth (Microsoft Entra ID SSO) and Bitwarden's built-in admin token authentication. The rest of the host is exposed via `chain-no-auth@file` so the Bitwarden API and Identity service can authenticate clients themselves — placing forward-auth in front of those endpoints would break every Bitwarden client.

## Architecture

- **Image**: [`ghcr.io/bitwarden/lite`](https://github.com/bitwarden/self-host/tree/main/bitwarden-lite)
- **Runtime user**: UID/GID `3126` (`svc-app-bitwarden`) — set via `PUID`/`PGID`. The entrypoint runs as root to generate the IdentityServer PFX certificate and chown internal paths, then `exec su-exec`s into `supervisord` as the runtime user.
- **Database**: SQLite at `/etc/bitwarden/vault.db` (auto-created on first start)
- **Networks**: `bitwarden-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with split routing — `chain-no-auth@file` for the public Bitwarden services, `chain-auth@file` for `/admin`
- **No init container** — the upstream entrypoint chowns its own paths via `su-exec`, matching the LinuxServer/s6-overlay exception in [Architecture](../ARCHITECTURE.md)

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

| Variable                       | Description                                                                            |
| ------------------------------ | -------------------------------------------------------------------------------------- |
| `DOMAINNAME`                   | Base domain for Traefik routing                                                        |
| `BW_INSTALLATION_ID`           | Installation ID from <https://bitwarden.com/host/>                                     |
| `BW_INSTALLATION_KEY`          | Installation key from <https://bitwarden.com/host/>                                    |
| `BW_ADMIN_EMAILS`              | Comma-separated admin emails for `/admin` panel access                                 |
| `BW_DISABLE_USER_REGISTRATION` | `false` until your account is created, then flip to `true` to lock down the deployment |
| `NOTIFICATIONS_EMAIL_*`        | SMTP settings (host/port/username/password/from) — required for verification emails    |

## First-Run Setup

1. Generate an installation ID and key at <https://bitwarden.com/host/> and save them.
2. Create the dataset `vm-pool/apps/services/bitwarden` in TrueNAS.
3. Create the `svc-app-bitwarden` group (GID 3126), then user (UID 3126) on the TrueNAS host. See [Infrastructure § TrueNAS Host Setup](../INFRASTRUCTURE.md#truenas-host-setup) for the standard creation order.
4. Populate `secret.sops.env` with the installation ID/key, admin emails, and SMTP settings, then encrypt it:

   ```sh
   sops -e -i services/bitwarden/secret.sops.env
   ```

5. Deploy. Visit `https://vault.${DOMAINNAME}` and register your account.
6. Once your account exists, set `BW_DISABLE_USER_REGISTRATION=true` in `secret.sops.env` and redeploy to disable further signups.

## Upgrade Notes

- **Image updates** are managed by Renovate. The initial commit pins the tag only; Renovate will add the `@sha256:...` digest pin in its next run (see the Docker Hardened Image guidance in [Architecture](../ARCHITECTURE.md)).
- **Database backups**: SQLite stores everything in `./data/vault.db`. Snapshot the `vm-pool/apps/services/bitwarden` dataset on a regular cadence, or export an encrypted backup from the Bitwarden web vault (`Settings → Export vault`).
- **Schema migrations** run automatically at container start. The entrypoint applies pending migrations against the SQLite file before launching `supervisord`.
- **Memory tuning**: the default `mem_limit: 1024m` is comfortable. Reduce via `MEM_LIMIT` if needed — Bitwarden Lite requires at least 200 MB.
