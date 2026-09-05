# Dawarich

[Dawarich](https://dawarich.app/) is a self-hosted location history service
for importing, visualising, and searching GPS data.

## Why

Dawarich keeps location history under local control while supporting imports
and API-key-authenticated GPS clients. This stack separates the web application,
background processing, PostGIS, Redis, database backups, and metrics exporter
so each component can be isolated and operated independently.

## Compose Files

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/dawarich/compose.yaml)
- [secret.sops.env](https://github.com/DevSecNinja/truenas-apps/blob/main/services/dawarich/secret.sops.env)

## Access

| URL                                                      | Authentication                              | Description              |
| -------------------------------------------------------- | ------------------------------------------- | ------------------------ |
| `https://dawarich.${DOMAINNAME}`                         | Traefik Forward Auth, then Dawarich account | Web UI                   |
| `https://dawarich.${DOMAINNAME}/api/v1/overland/batches` | Dawarich API key                            | Overland batch ingestion |
| `https://dawarich.${DOMAINNAME}/api/v1/owntracks/points` | Dawarich API key                            | OwnTracks ingestion      |

The main router uses `chain-auth-dawarich@file` as defense in depth because
upstream seeds a demo administrator. The chain combines rate limiting, Forward
Auth, and `middlewares-dawarich-secure-headers`. Its CSP adds only
`https://tyles.dwri.xyz`, required by the default Protomaps vector tiles, and
permits same-origin and `blob:` web workers for MapLibre. A higher-priority
router uses `chain-no-auth@file` only for the exact
`/api/v1/owntracks/points` and
`/api/v1/overland/batches` paths, allowing GPS clients to present Dawarich API
keys without being redirected to interactive SSO. API login, registration,
`/api-docs`, and every other endpoint remain behind
`chain-auth-dawarich@file`. This prevents the known seeded administrator
credentials from being exchanged for an API key without first passing SSO.

## Architecture

- **Images**: Dawarich `1.14.2`, PostGIS `17-3.5-alpine`, Redis
  `7.4-alpine`, tiredofit/db-backup `4.1.100`, and postgres_exporter
  `v0.20.1`; Compose pins each image by digest
- **Application user/group**: `3128:3128` (`svc-app-dawarich`)
- **Reverse proxy**: Traefik with `chain-auth-dawarich@file` for the web UI and
  a higher-priority `chain-no-auth@file` router only for
  `/api/v1/owntracks/points` and `/api/v1/overland/batches`
- **Networks**: `dawarich-frontend` and the external, internal
  `dawarich-backend`

### Services

| Container              | Role                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------ |
| `dawarich-init`        | Validates required decrypted values, creates temporary paths, and assigns ownership        |
| `dawarich`             | Runs `web-entrypoint.sh` with `bin/rails server -p 3000 -b ::`; Rails metrics are disabled |
| `dawarich-sidekiq`     | Runs `sidekiq-entrypoint.sh` for background GPS import and processing                      |
| `dawarich-redis`       | Password-protected job queue and cache with persistent snapshots                           |
| `dawarich-db`          | PostGIS database                                                                           |
| `dawarich-db-backup`   | One-shot encrypted PostgreSQL backup                                                       |
| `dawarich-db-exporter` | Exposes PostgreSQL metrics on the backend network                                          |

The application health check sends `X-Forwarded-Proto: https` with its internal
HTTP request. Because `APPLICATION_PROTOCOL=https` enables Rails `force_ssl`,
omitting the header redirects the probe instead of returning the expected
health response.

The Sidekiq health check uses the image's Ruby interpreter to inspect
`/proc/1/cmdline` and confirm that PID 1 contains `sidekiq`. It does not use
`pgrep` because the image does not include `pgrep`/procps.

### Networks

| Network             | Members and purpose                                                                                                    |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `dawarich-frontend` | Traefik reaches the web application; the app and worker use it for outbound requests, and backup uses it only for SMTP |
| `dawarich-backend`  | External internal network for the app, worker, PostGIS, Redis, DB backup, exporter, and Alloy scrape                   |

`_bootstrap` creates `dawarich-backend` before Alloy and Dawarich deploy. This
ordering lets both stacks reference the external network on a fresh deployment
without either stack owning or recreating it.

Alloy joins `dawarich-backend` as an external network and actively scrapes
`dawarich-db-exporter:9187` through Alloy's
`prometheus.scrape "postgres_dawarich"` target. The exporter endpoint is not
published on the host. The Rails Prometheus exporter is disabled, so Alloy
does not scrape the Dawarich application container.

## Storage

All persistent paths remain inside the
`vm-pool/apps/services/dawarich` dataset.

| Host path             | Container path                 | Used by        | Purpose                            |
| --------------------- | ------------------------------ | -------------- | ---------------------------------- |
| `./data/public`       | `/var/app/public`              | App, worker    | Generated public assets            |
| `./data/storage`      | `/var/app/storage`             | App, worker    | Application storage                |
| `./data/watched`      | `/var/app/tmp/imports/watched` | App, worker    | Watched GPS imports                |
| `./data/app-tmp`      | `/var/app/tmp`                 | App            | PID, cache, socket, and home paths |
| `./data/sidekiq-tmp`  | `/var/app/tmp`                 | Worker         | Worker cache and home paths        |
| `./data/redis`        | `/data`                        | Redis          | Persistent Redis snapshots         |
| `./data/db`           | `/var/lib/postgresql/data`     | PostGIS        | Database cluster                   |
| `./backups/db-backup` | `/backup`                      | Backup sidecar | Encrypted database backups         |

## Secrets

Secrets are managed in `secret.sops.env`, committed SOPS-encrypted, and
decrypted to `.env` during deployment.

| Variable                           | Purpose                                          |
| ---------------------------------- | ------------------------------------------------ |
| `DOMAINNAME`                       | Base domain for Traefik routing                  |
| `DAWARICH_SECRET_KEY_BASE`         | Rails secret key base                            |
| `DAWARICH_DB_PASSWORD`             | PostGIS password for the Dawarich database user  |
| `DAWARICH_REDIS_PASSWORD`          | Redis authentication password                    |
| `DAWARICH_OTP_PRIMARY_KEY`         | Primary key for encrypted OTP attributes         |
| `DAWARICH_OTP_DETERMINISTIC_KEY`   | Deterministic key for encrypted OTP attributes   |
| `DAWARICH_OTP_KEY_DERIVATION_SALT` | Key-derivation salt for encrypted OTP attributes |
| `DAWARICH_ARCHIVE_ENCRYPTION_KEY`  | Dawarich archive encryption key                  |
| `DAWARICH_SIDEKIQ_USERNAME`        | Sidekiq dashboard username                       |
| `DAWARICH_SIDEKIQ_PASSWORD`        | Sidekiq dashboard password                       |
| `NOTIFICATIONS_EMAIL_FROM`         | Sender address for application and backup email  |
| `NOTIFICATIONS_EMAIL_TO`           | Recipient for backup notifications               |
| `NOTIFICATIONS_EMAIL_HOST`         | SMTP server                                      |
| `NOTIFICATIONS_EMAIL_DOMAIN`       | SMTP HELO domain                                 |
| `NOTIFICATIONS_EMAIL_USERNAME`     | SMTP username                                    |
| `NOTIFICATIONS_EMAIL_PASSWORD`     | SMTP password                                    |
| `NOTIFICATIONS_EMAIL_PORT`         | SMTP port                                        |
| `DB_ENC_PASSPHRASE`                | Encryption passphrase for database backup files  |

`dawarich-init` checks every required decrypted value before changing runtime
permissions. It exits unsuccessfully if any value is empty or equals
`CHANGE_ME`, which blocks deployment with placeholder domain, SMTP, database,
Redis, application, or backup settings. PostGIS and Redis require successful
init completion before startup, so a placeholder database password cannot
initialize PostGIS; the application and worker start only after those backends
are healthy.

<!-- dprint-ignore -->
!!! danger "Encryption keys are data dependencies"
    Never rotate `DAWARICH_SECRET_KEY_BASE`, any `DAWARICH_OTP_*` key,
    `DAWARICH_ARCHIVE_ENCRYPTION_KEY`, or `DB_ENC_PASSPHRASE` without a tested
    migration or restore plan. Losing or changing them can make application
    data, archived data, OTP attributes, or database backups unreadable.

## First-Run Setup

1. Create the `svc-app-dawarich` group with GID 3128 and add
   `truenas_admin` as an auxiliary member.
2. Create the `svc-app-dawarich` user with UID 3128 and primary group
   `svc-app-dawarich`.
3. Create the `vm-pool/apps/services/dawarich` dataset.
4. Replace every shared `CHANGE_ME` value in `secret.sops.env`, then
   re-encrypt the file with SOPS.
5. Run a full `dccd.sh` deployment so `_bootstrap` creates
   `dawarich-backend` before Alloy and Dawarich.
6. Confirm `dawarich-init` validates the decrypted values and completes before
   PostGIS or Redis starts; the application and worker then wait for the
   backends to become healthy.
7. Open `https://dawarich.${DOMAINNAME}` through Traefik Forward Auth and sign
   in with the upstream seeded
   account.
8. **Immediately change the seeded `demo@dawarich.app` / `safepassword`
   credentials before importing data or configuring a GPS client.**
9. Create API keys in Dawarich for GPS clients. Configure clients to use only
   `/api/v1/owntracks/points` or `/api/v1/overland/batches`; these exact paths
   bypass Forward Auth but still require Dawarich API-key authentication.

## Security Model

- The Rails application and Sidekiq worker run the upstream role-specific
  `web-entrypoint.sh` and `sidekiq-entrypoint.sh` scripts directly as
  `svc-app-dawarich` (`3128:3128`). The web command is explicitly
  `bin/rails server -p 3000 -b ::`.
- `dawarich-init` is the only application-specific root process. It retains
  only `CHOWN`, `FOWNER`, and `DAC_OVERRIDE`; the latter is required to traverse
  mode `770` runtime paths on repeat deployments. It rejects empty or
  `CHANGE_ME` required values, prepares the writable paths, and exits before
  PostGIS, Redis, or the application starts.
- The app, worker, Redis, and exporter use read-only root filesystems,
  `no-new-privileges`, and dropped Linux capabilities.
- The official PostGIS image retains its root-start entrypoint so it can
  initialise ownership and then drop to its internal PostgreSQL user.
- PostGIS, Redis, database backup access, and metrics stay on the internal
  backend network. Redis is backend-only; of the backend services, only the
  backup container also joins the frontend, solely for outbound SMTP. Only the
  web application is routed through Traefik.
- The web UI uses `chain-auth-dawarich@file`, combining rate limiting, Forward
  Auth, and Dawarich-specific secure headers. Its CSP adds only
  `https://tyles.dwri.xyz` for the default Protomaps vector tiles and allows
  same-origin and `blob:` workers for MapLibre. Only
  `/api/v1/owntracks/points` and `/api/v1/overland/batches` use
  `chain-no-auth@file`; both still require Dawarich API-key authentication. API
  login, registration, `/api-docs`, and every other endpoint remain behind
  `chain-auth-dawarich@file`, so the seeded administrator credentials cannot be
  exchanged for an API key without SSO.
- Forward Auth reduces exposure of the seeded demo administrator but does not
  replace rotating `demo@dawarich.app` / `safepassword` immediately.
- SOPS encrypts credentials at rest in Git. Decrypted `.env` files and all
  runtime/backup directories are gitignored.

## Backup and Restore

`dawarich-db-backup` is a one-shot job started by each full `dccd.sh`
deployment. It has no intrinsic scheduler, so its cadence follows `dccd`. The
documented TrueNAS cron runs every 15 minutes with `-f`, which means the
one-shot backup may run on every forced full deployment. It writes
ZSTD-compressed, SHA1-checksummed, encrypted PostgreSQL backups to
`./backups/db-backup`; 48-hour retention bounds the number of stored files.

ZFS snapshots and replication protect the complete Dawarich dataset, including
PostGIS, Redis, storage, public assets, watched imports, temporary paths, and
encrypted database backups. See [Backup Strategy](../BACKUP.md).

For a restore:

1. Preserve the SOPS secrets used by the backup, especially
   `DB_ENC_PASSPHRASE` and the Dawarich encryption keys.
2. Stop the Rails application and Sidekiq worker.
3. Restore file-backed paths from the same ZFS snapshot when a coordinated
   dataset rollback is required.
4. Decrypt and restore the selected PostgreSQL backup into PostGIS using the
   tiredofit/db-backup restore workflow.
5. Start the stack and verify the health endpoint, login, imports, and
   background jobs.

Prefer the application-level PostgreSQL dump for database recovery; use a
whole-dataset rollback only when all runtime paths must return to the same
point in time.

## Upgrade Notes

- Renovate manages image updates. Review Dawarich release notes for migrations
  and breaking configuration changes before deployment.
- Take a current database backup and ZFS snapshot before major Dawarich or
  PostGIS changes.
- The application uses stop-first replacement so migrations complete before a
  replacement instance serves traffic.
- Treat a PostGIS major-version change as a database migration. Follow
  [Database Upgrades](../DATABASE-UPGRADES.md) rather than replacing the image
  in place.
- Do not rotate persistent encryption keys as part of a routine upgrade.
