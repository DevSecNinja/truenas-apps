# Gatus

Gatus is an automated uptime monitoring tool with alerting and a public-facing status page.

## Why

You need to know when services go down — ideally before users notice. Gatus monitors every service in this stack via HTTP health checks through Traefik's internal monitoring entrypoint, sends email alerts on failure, and serves a clean status page. Unlike SaaS monitoring tools, it runs entirely within your network and can check internal services that aren't exposed to the internet.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/gatus/compose.yaml)

## Access

| URL                            | Description                           |
| ------------------------------ | ------------------------------------- |
| `https://status.${DOMAINNAME}` | Status page (no auth — public-facing) |

## Architecture

- **Images**: [twinproduction/gatus](https://github.com/TwiN/gatus), [postgres](https://hub.docker.com/_/postgres), [pgautoupgrade](https://github.com/pgautoupgrade/docker-pgautoupgrade), [tiredofit/db-backup](https://github.com/tiredofit/docker-db-backup), [gatus-sidecar](https://github.com/DevSecNinja/gatus-sidecar) (first-party), [linuxserver/socket-proxy](https://github.com/linuxserver/docker-socket-proxy)
- **User/Group**: `3103:3103` (`svc-app-gatus`)
- **Networks**: `gatus-frontend` (Traefik-facing, fixed IPAM subnet `172.30.100.0/29`), `gatus-backend` (internal — Postgres, Redis, socket proxy, sidecar)
- **Reverse proxy**: Traefik with `chain-no-auth@file` middleware — the status page is intentionally public

### How Monitoring Works

Gatus checks services through Traefik's dedicated monitoring entrypoint (port 8444), which uses `chain-no-auth@file` to bypass forward-auth. An IP allowlist restricts this entrypoint to the `gatus-frontend` subnet only. See [Architecture](../ARCHITECTURE.md#gatus-internal-monitoring-entrypoint) for the full security model.

The `gatus-sidecar` reads Docker labels (`gatus.*`) from running containers via the socket proxy and auto-generates monitoring endpoints in `data/sidecar-config/gatus-sidecar.yaml`. This means adding monitoring to a new service only requires Traefik labels — no manual Gatus config changes.

### Services

| Container            | Role                                                                                       |
| -------------------- | ------------------------------------------------------------------------------------------ |
| `gatus-init`         | One-shot init: copies `config/config.yaml` → `data/sidecar-config/` (config mounted `:ro`) |
| `gatus`              | Uptime monitor and status page                                                             |
| `gatus-db-upgrade`   | One-shot: pgautoupgrade for automatic Postgres major version upgrades                      |
| `gatus-db`           | PostgreSQL database for historical uptime data                                             |
| `gatus-db-backup`    | One-shot nightly backup sidecar (restarted by `dccd.sh`)                                   |
| `gatus-sidecar`      | Auto-generates monitoring config from Docker labels via socket proxy                       |
| `gatus-docker-proxy` | LinuxServer socket-proxy — read-only Docker API access                                     |

### Config Management

The main `config/config.yaml` is git-tracked and copied into `data/sidecar-config/` by `gatus-init` (the config directory is mounted `:ro`). The sidecar writes its auto-generated config alongside it. Gatus reads both files from the same directory.

### Database Backup

`gatus-db-backup` uses `tiredofit/db-backup` in `MODE=MANUAL` with `MANUAL_RUN_FOREVER=FALSE` — it runs one backup and exits. Backups are ZSTD-compressed, SHA1-checksummed, AES-encrypted with `DB_ENC_PASSPHRASE`, and retained for 48 hours.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing
- `GATUS_DB_PASSWORD` — PostgreSQL password
- `DB_ENC_PASSPHRASE` — encryption passphrase for database backups
- `NOTIFICATIONS_EMAIL_*` — SMTP settings for alert emails

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/gatus` in TrueNAS
2. Create a `svc-app-gatus` group (GID 3103) and user (UID 3103) on the TrueNAS host
3. Add secrets to `secret.sops.env` (at minimum `GATUS_DB_PASSWORD` and email notification settings)
4. Deploy — Gatus auto-discovers monitored services from Docker labels

## Upgrade Notes

PostgreSQL major version upgrades are handled automatically by the `gatus-db-upgrade` (pgautoupgrade) container that runs before the database starts. See [Database Upgrades](../DATABASE-UPGRADES.md) for general guidance.
