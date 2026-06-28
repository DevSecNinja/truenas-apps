# AirTrail

AirTrail is a modern, open-source self-hosted personal flight tracking system. Log the flights you have taken, visualise routes on a map, and keep statistics on your travel history — all under your own control.

## Why

Commercial flight-logging apps lock your travel history behind an account and sync it to someone else's cloud. AirTrail keeps your flight data private on your own infrastructure, with a clean SvelteKit web UI, route maps, and per-user statistics. Authentication is fronted by Microsoft Entra ID SSO (via Traefik forward-auth) while AirTrail also manages its own built-in user accounts.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/airtrail/compose.yaml)

## Access

| URL                              | Description                                                      |
| -------------------------------- | ---------------------------------------------------------------- |
| `https://airtrail.${DOMAINNAME}` | Web UI (Traefik forward-auth + AirTrail's own built-in accounts) |

## Architecture

- **Images**: [johly/airtrail](https://github.com/johanohly/AirTrail), [postgres](https://hub.docker.com/_/postgres), [pgautoupgrade](https://github.com/pgautoupgrade/docker-pgautoupgrade), [tiredofit/db-backup](https://github.com/tiredofit/docker-db-backup), [postgres_exporter](https://github.com/prometheus-community/postgres_exporter)
- **User/Group**: `1000:1000` (image-internal `node` user — AirTrail does not support PUID/PGID)
- **Networks**: `airtrail-frontend` (Traefik-facing bridge), `airtrail-backend` (internal bridge — Postgres, backup, exporter)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware; the app listens on port `3000`
- **Volumes**: `./data/uploads` (app uploads), `./data/db` (Postgres data), `./backups/db-backup` (encrypted backups)

### User/Group Exception

The `johly/airtrail` image does not support custom PUID/PGID — it runs as the image-internal `node` user (UID/GID 1000). UID 3128 (`svc-app-airtrail`) is used only for the db-backup sidecar. The `airtrail-init` container pre-chowns `./data/uploads` to UID 1000 so the node process can write uploaded files (airline icons, etc.) to the bind-mount.

### Services

| Container              | Role                                                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `airtrail-init`        | One-shot init: chowns `./data/uploads` to `1000:1000` (node user)                                                                     |
| `airtrail`             | SvelteKit/Node.js flight tracking application                                                                                         |
| `airtrail-db-upgrade`  | One-shot: pgautoupgrade for automatic Postgres major version upgrades                                                                 |
| `airtrail-db`          | PostgreSQL 18.4 database                                                                                                              |
| `airtrail-db-backup`   | One-shot nightly backup sidecar (restarted by `dccd.sh`) — runs as UID/GID 3128 (`svc-app-airtrail`)                                  |
| `airtrail-db-exporter` | `postgres_exporter` sidecar — exposes Postgres metrics on `airtrail-backend:9187` for Alloy to scrape (reuses `AIRTRAIL_DB_PASSWORD`) |

### Database Backup

`airtrail-db-backup` uses `tiredofit/db-backup` in `MODE=MANUAL` with `MANUAL_RUN_FOREVER=FALSE`. Backups are ZSTD-compressed, SHA1-checksummed, AES-encrypted with `DB_ENC_PASSPHRASE`, and retained for 48 hours. Email notifications are sent via the `NOTIFICATIONS_EMAIL_*` SMTP settings.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

| Variable                       | Description                                |
| ------------------------------ | ------------------------------------------ |
| `DOMAINNAME`                   | Base domain for Traefik routing            |
| `AIRTRAIL_DB_PASSWORD`         | PostgreSQL password                        |
| `DB_ENC_PASSPHRASE`            | Encryption passphrase for database backups |
| `NOTIFICATIONS_EMAIL_FROM`     | Backup notification sender address         |
| `NOTIFICATIONS_EMAIL_TO`       | Backup notification recipient address      |
| `NOTIFICATIONS_EMAIL_HOST`     | SMTP server hostname                       |
| `NOTIFICATIONS_EMAIL_DOMAIN`   | SMTP HELO/EHLO domain                      |
| `NOTIFICATIONS_EMAIL_USERNAME` | SMTP authentication username               |
| `NOTIFICATIONS_EMAIL_PASSWORD` | SMTP authentication password               |
| `NOTIFICATIONS_EMAIL_PORT`     | SMTP server port                           |

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/airtrail` in TrueNAS
2. Create a `svc-app-airtrail` group (GID 3128) and user (UID 3128) on the TrueNAS host (used by db-backup only)
3. Populate `secret.sops.env` with the database password, backup passphrase, and SMTP settings
4. Deploy — database migrations run automatically on container start via the image entrypoint
5. Visit `https://airtrail.${DOMAINNAME}` — the first user created becomes the admin account

## Upgrade Notes

PostgreSQL major version upgrades are handled automatically by `airtrail-db-upgrade` (pgautoupgrade). AirTrail application migrations run automatically on startup — check the [AirTrail releases](https://github.com/johanohly/AirTrail/releases) before deploying major version bumps. Nightly encrypted backups provide a recovery point before each upgrade.
