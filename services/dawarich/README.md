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

| Route                                                       | Authentication                                | Description                                    |
| ----------------------------------------------------------- | --------------------------------------------- | ---------------------------------------------- |
| `https://dawarich.${DOMAINNAME}` and all unspecified routes | Traefik Forward Auth, then Dawarich account   | Web UI and default route                       |
| Allowlisted official mobile API routes                      | `X-Dawarich-Proxy-Token` and Dawarich API key | Official iOS app                               |
| `POST /api/v1/overland/batches`                             | Dawarich API key                              | Overland ingestion                             |
| `POST /api/v1/owntracks/points`                             | Dawarich API key                              | OwnTracks, GPSLogger, and PhoneTrack ingestion |
| `POST /api/v1/traccar/points`                               | Dawarich API key                              | Traccar ingestion                              |

The main router uses `chain-auth-dawarich@file` as defense in depth because
upstream seeds a demo administrator. The chain combines rate limiting, Forward
Auth, and `middlewares-dawarich-secure-headers`. Its restrictive CSP permits
`connect-src 'self' https:` because upstream supports user-configurable vector,
raster, and style basemap URLs. Custom basemap endpoints must use HTTPS; HTTP
custom origins remain intentionally blocked. `worker-src` remains limited to
`'self' blob:` for MapLibre.

With `SELF_HOSTED=true` on Dawarich 1.14.2, `/sidekiq` requires a signed-in
Dawarich administrator account. No separate Sidekiq dashboard credentials are
configured.

Two higher-priority routers provide narrowly scoped Forward Auth bypasses:

- The official mobile router requires both the user's Dawarich API key and an
  `X-Dawarich-Proxy-Token` header matching
  `DAWARICH_MOBILE_PROXY_TOKEN`. It accepts only the following `/api/v1`
  resources: `health`, `users/me`, `plan`, `settings/mobile`, `points`,
  `timeline`, `tracks`, `visits`, `stats`, `insights`, `digests`, `demo_data`,
  `families`, `photos`, `countries`, `maps`, `tiles`, and `places`.
- The third-party ingestion router accepts only `POST` requests to the three
  exact endpoints listed in the table. These endpoints still require a
  Dawarich API key.

Authentication login and registration routes, `/api-docs`, requests with a
missing or incorrect mobile proxy token, and every other route remain behind
`chain-auth-dawarich@file`.

### Official iOS App

Dawarich iOS 2.5 and later supports custom reverse-proxy headers. Configure:

| Setting             | Value                                                |
| ------------------- | ---------------------------------------------------- |
| Server URL          | `https://dawarich.${DOMAINNAME}`                     |
| API key             | The user's API key from **Account** in Dawarich      |
| Custom header name  | `X-Dawarich-Proxy-Token`                             |
| Custom header value | The decrypted value of `DAWARICH_MOBILE_PROXY_TOKEN` |

The API key identifies and authorizes the Dawarich user. The separate proxy
token permits the request to use only the mobile router's allowlisted API
surface without interactive Entra Forward Auth.

### Third-Party GPS Clients

Configure OwnTracks-compatible clients, including GPSLogger and PhoneTrack, to
send `POST` requests to `/api/v1/owntracks/points`. Overland and Traccar use
their corresponding exact endpoints in the access table. Supply a Dawarich API
key as required by the client and Dawarich; the proxy bypass does not replace
API-key authentication.

<!-- dprint-ignore -->
!!! warning "Protect query-string API keys"
    Third-party clients may place their Dawarich API key in the request query
    string. Query strings can appear in Traefik or other intermediary access
    logs. Restrict access to those logs, avoid sharing raw request URLs, and
    rotate an API key if it may have been exposed.

## Architecture

- **Images**: Dawarich `1.14.2`, PostGIS `17-3.5-alpine`, Redis
  `7.4-alpine`, nfrastack/db-backup `4.9.2`, and postgres_exporter `v0.20.1`;
  Compose pins each image by digest
- **Application user/group**: `3128:3128` (`svc-app-dawarich`)
- **Reverse proxy**: Traefik with `chain-auth-dawarich@file` by default, plus
  separate higher-priority mobile and third-party ingestion routers using
  `chain-no-auth@file`
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
| `dawarich-db-backup`   | One-shot GPG-encrypted PostgreSQL backup after healthy Rails startup                       |
| `dawarich-db-exporter` | Exposes PostgreSQL metrics on the backend network                                          |

The application health check sends `X-Forwarded-Proto: https` with its internal
HTTP request. Because `APPLICATION_PROTOCOL=https` enables Rails `force_ssl`,
omitting the header redirects the probe instead of returning the expected
health response.

The Sidekiq health check uses the image's Ruby interpreter to inspect
`/proc/1/cmdline` and confirm that PID 1 contains `sidekiq`. It does not use
`pgrep` because the image does not include `pgrep`/procps.

### Networks

| Network             | Members and purpose                                                                                  |
| ------------------- | ---------------------------------------------------------------------------------------------------- |
| `dawarich-frontend` | Traefik reaches the web application; the app and worker also use it for outbound requests            |
| `dawarich-backend`  | External internal network for the app, worker, PostGIS, Redis, DB backup, exporter, and Alloy scrape |

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
| `./backups/db-backup` | `/backup`                      | Backup sidecar | GPG-encrypted database backups     |

## Secrets

Secrets are managed in `secret.sops.env`, committed SOPS-encrypted, and
decrypted to `.env` during deployment.

| Variable                           | Purpose                                              |
| ---------------------------------- | ---------------------------------------------------- |
| `DOMAINNAME`                       | Base domain for Traefik routing                      |
| `DAWARICH_SECRET_KEY_BASE`         | Rails secret key base                                |
| `DAWARICH_DB_PASSWORD`             | PostGIS password for the Dawarich database user      |
| `DAWARICH_REDIS_PASSWORD`          | Redis authentication password                        |
| `DAWARICH_OTP_PRIMARY_KEY`         | Primary key for encrypted OTP attributes             |
| `DAWARICH_OTP_DETERMINISTIC_KEY`   | Deterministic key for encrypted OTP attributes       |
| `DAWARICH_OTP_KEY_DERIVATION_SALT` | Key-derivation salt for encrypted OTP attributes     |
| `DAWARICH_ARCHIVE_ENCRYPTION_KEY`  | Dawarich archive encryption key                      |
| `DAWARICH_MOBILE_PROXY_TOKEN`      | Second secret required by the official mobile router |
| `NOTIFICATIONS_EMAIL_FROM`         | Sender address for Dawarich application email        |
| `NOTIFICATIONS_EMAIL_HOST`         | SMTP server for Dawarich application email           |
| `NOTIFICATIONS_EMAIL_DOMAIN`       | SMTP HELO domain for Dawarich application email      |
| `NOTIFICATIONS_EMAIL_USERNAME`     | SMTP username for Dawarich application email         |
| `NOTIFICATIONS_EMAIL_PASSWORD`     | SMTP password for Dawarich application email         |
| `NOTIFICATIONS_EMAIL_PORT`         | SMTP port for Dawarich application email             |
| `DB_ENC_PASSPHRASE`                | GPG passphrase for database backup files             |

`dawarich-init` checks every required decrypted value before changing runtime
permissions. It exits unsuccessfully if any value is empty or equals
`CHANGE_ME`, which blocks deployment with placeholder domain, SMTP, database,
Redis, mobile proxy, application, or backup settings. PostGIS and Redis require
successful init completion before startup, so a placeholder database password
cannot initialize PostGIS; the application and worker start only after those
backends are healthy.

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
4. Add a unique, high-entropy `DAWARICH_MOBILE_PROXY_TOKEN`, replace every
   shared `CHANGE_ME` value in `secret.sops.env`, then re-encrypt the file with
   SOPS. Do not reuse a Dawarich API key as the proxy token.
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
9. Create a separate Dawarich API key for each GPS client.
10. For the official iOS app 2.5 or later, configure the server URL, API key,
    and custom proxy header described under [Official iOS App](#official-ios-app).
11. Configure third-party clients to use only the applicable exact ingestion
    endpoint. GPSLogger and PhoneTrack use `/api/v1/owntracks/points`. These
    endpoints bypass Forward Auth only for `POST` and still require Dawarich
    API-key authentication.

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
  backend network. The backup job sets `ENABLE_NOTIFICATIONS=FALSE` and does not
  join the frontend network. Only the web application is routed through
  Traefik.
- The web UI and unspecified routes use `chain-auth-dawarich@file`, combining
  rate limiting, Forward Auth, and Dawarich-specific secure headers. Its CSP
  permits `connect-src 'self' https:` for upstream's user-configurable vector,
  raster, and style basemap URLs. Custom endpoints must use HTTPS because HTTP
  custom origins remain blocked. `worker-src 'self' blob:` stays unchanged, and
  the other directives remain restrictive.
- With `SELF_HOSTED=true` on Dawarich 1.14.2, `/sidekiq` requires a signed-in
  Dawarich administrator account rather than separate dashboard credentials.
- The official mobile router uses `chain-no-auth@file` only when the request
  has the configured `X-Dawarich-Proxy-Token` and targets an allowlisted mobile
  API resource. The request must also carry the user's Dawarich API key.
- The third-party ingestion router uses `chain-no-auth@file` only for `POST` to
  `/api/v1/owntracks/points`, `/api/v1/overland/batches`, or
  `/api/v1/traccar/points`; Dawarich API-key authentication still applies.
  Login, registration, `/api-docs`, all other methods and endpoints, and mobile
  requests without the proxy token stay behind Forward Auth.
- Forward Auth reduces exposure of the seeded demo administrator but does not
  replace rotating `demo@dawarich.app` / `safepassword` immediately.
- SOPS encrypts credentials at rest in Git. Decrypted `.env` files and all
  runtime/backup directories are gitignored.

## Backup and Restore

`dawarich-db-backup` is a one-shot job started by each full `dccd.sh`
deployment. It runs `backup-now` with `MODE=MANUAL` and has no intrinsic
scheduler, so its cadence follows `dccd`. The documented TrueNAS cron runs every
15 minutes with `-f`, which means the one-shot backup may run on every forced
full deployment. It writes ZSTD-compressed PostgreSQL dumps, GPG-encrypts them
with `DEFAULT_ENCRYPT=TRUE` and
`DEFAULT_ENCRYPT_PASSPHRASE=${DB_ENC_PASSPHRASE}`, and writes a SHA1 sidecar.
`DEFAULT_CLEANUP_TIME=2880` retains backup artifacts for 2880 minutes (48
hours). The image maps its internal backup account to the Dawarich service
identity with `USER_DBBACKUP=3128` and `GROUP_DBBACKUP=3128`.

The backup job depends on the healthy `dawarich` Rails service rather than only
PostgreSQL. This ordering lets startup migrations, data migrations, and seeding
finish before the dump can run.

The stack intentionally uses the maintained
`docker.io/nfrastack/db-backup:4.9.2` compatibility release. Runtime restore
validation of v5.0.0 failed with an invalid bigint conversion. Version 4.9.2
keeps the proven v4 backup and restore workflow while using the maintained
nfrastack image and repository. `ENABLE_NOTIFICATIONS=FALSE` keeps the one-shot
job backend-only; all `NOTIFICATIONS_EMAIL_*` values belong only to the Dawarich
application.

Runtime testing successfully decrypted the resulting GPG-encrypted,
ZSTD-compressed dump and restored it into a fresh PostgreSQL database.

ZFS snapshots and replication protect the complete Dawarich dataset, including
PostGIS, Redis, storage, public assets, watched imports, temporary paths, and
encrypted database backups. See [Backup Strategy](../BACKUP.md).

For a restore:

1. Preserve the SOPS secrets used by the backup, especially
   `DB_ENC_PASSPHRASE` and the Dawarich encryption keys.
2. Stop the Rails application and Sidekiq worker.
3. Restore file-backed paths from the same ZFS snapshot when a coordinated
   dataset rollback is required.
4. Verify the SHA1 sidecar, then use `DB_ENC_PASSPHRASE` to GPG-decrypt and
   ZSTD-decompress the dump.
5. Restore the resulting PostgreSQL dump into PostGIS.
6. Start the stack and verify the health endpoint, login, imports, and
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
