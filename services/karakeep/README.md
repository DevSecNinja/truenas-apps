# Karakeep

[Karakeep](https://karakeep.app/) is a self-hosted bookmark manager for links,
notes, and images, with full-text search and optional AI tagging.

## Why

Karakeep keeps saved content and its search index on locally managed storage.
The split web, worker, and search services isolate background crawling and
indexing from the user-facing application. The enabled Chrome service renders
JavaScript-driven pages and supports screenshots without exposing its DevTools
endpoint through the host or Traefik.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/karakeep/compose.yaml)

## Access and Authentication

| Access path                      | Traefik authentication                                       | Karakeep authentication                               |
| -------------------------------- | ------------------------------------------------------------ | ----------------------------------------------------- |
| Web UI and all unspecified APIs  | `chain-auth@file`                                            | Local user session                                    |
| Allowlisted official mobile APIs | Proxy token header, then `chain-no-auth@file` after matching | Public discovery/exchange or API key/session for data |

The standard `karakeep-rtr` router remains behind `chain-auth@file`. The
higher-priority `karakeep-mobile-rtr` matches only the exact mobile route
envelope below when the request includes
`X-Karakeep-Proxy-Token: ${KARAKEEP_MOBILE_PROXY_TOKEN}`. It applies
`chain-no-auth@file`, strips the proxy token header, and then forwards the
request to Karakeep. A missing or incorrect token, a different method, or any
other path falls through to the standard SSO-protected router.

<!-- dprint-ignore -->
!!! warning "The proxy token is not Karakeep user authentication"
    The header only permits an allowlisted request to bypass interactive
    Forward Auth. Karakeep still authenticates user-data operations with the
    user's API key or session and applies its normal scope checks. Treat the
    proxy token as a secret because discovery and API-key exchange routes are
    public upstream.

### Mobile Route Envelope

The bypass, audited against official mobile app 1.11.1 at the pinned upstream
commit below, accepts only:

| Method | Path                                                 |
| ------ | ---------------------------------------------------- |
| `GET`  | `/api/health`                                        |
| `GET`  | `/api/version`                                       |
| `GET`  | `/api/assets/{single-path-segment}`                  |
| `POST` | `/api/assets`                                        |
| `GET`  | `/api/trpc/{allowlisted-query-or-query-batch}`       |
| `POST` | `/api/trpc/{allowlisted-mutation-or-mutation-batch}` |

The tRPC path must contain one of the following procedures or a
comma-separated batch made entirely from the corresponding method's list:

- **GET:** `config.clientConfig`; `bookmarks.getBookmarks`,
  `bookmarks.getBookmark`, `bookmarks.searchBookmarks`,
  `bookmarks.getReadingProgress`; `lists.list`, `lists.stats`, `lists.get`,
  `lists.getListsOfBookmark`; `tags.list`, `tags.get`; `highlights.getAll`,
  `highlights.getForBookmark`; `users.whoami`, `users.settings`, `users.stats`
- **POST:** `apiKeys.exchange`, `apiKeys.validate`, `apiKeys.revoke`;
  `bookmarks.createBookmark`, `bookmarks.updateBookmark`,
  `bookmarks.deleteBookmark`, `bookmarks.updateTags`,
  `bookmarks.summarizeBookmark`, `bookmarks.updateReadingProgress`;
  `lists.create`, `lists.edit`, `lists.delete`, `lists.addToList`,
  `lists.removeFromList`, `lists.leaveList`; `tags.create`, `tags.update`,
  `tags.delete`; `highlights.create`, `highlights.update`,
  `highlights.delete`; `users.updateSettings`, `users.deleteAccount`

`/api/health`, `/api/version`, `config.clientConfig`, `apiKeys.exchange`, and
`apiKeys.validate` are public in Karakeep itself, so the Traefik proxy token is
their authentication boundary in this deployment. Asset and other user-data
routes continue to require Karakeep API-key/session authentication and scope
checks. There are no separate mobile sync or push endpoints.

`/signup` is deliberately excluded. The native app opens that route in a
browser without custom headers, so registration remains behind SSO.

### Configure the Official Mobile App

In the mobile app's **Server Address** form, configure:

| Field               | Value                                   |
| ------------------- | --------------------------------------- |
| Server URL          | `https://karakeep.${DOMAINNAME}`        |
| Custom header name  | `X-Karakeep-Proxy-Token`                |
| Custom header value | Decrypted `KARAKEEP_MOBILE_PROXY_TOKEN` |

The app accepts arbitrary custom header name/value pairs and applies them to
tRPC requests, health and version checks, uploads, and Karakeep-local asset
requests. It stores the settings in Expo SecureStore, but the values remain
visible in the configuration UI to anyone with access to the unlocked device.

Complete account creation through the SSO-protected web flow before signing in
from the native app. Do not enable the optional Chrome service for mobile
access; it is unrelated to the authentication route.

### Rotate the Mobile Proxy Token

1. Replace `KARAKEEP_MOBILE_PROXY_TOKEN` in `secret.sops.env` through the
   approved
   [SOPS editing workflow](../CONTRIBUTING.md#generating-random-sops-secrets).
2. Deploy the updated encrypted configuration.
3. Replace the custom header value on every configured mobile device.

The old token stops working immediately when the deployment takes effect.
Plan for mobile access to remain unavailable on each device until its stored
value is replaced.

### Upstream Mobile Authentication Evidence

These links are pinned to upstream commit
`a1a887d5a0c311aacfbe13fcc080b1ddef5b8175`:

- [Server Address custom-header configuration](https://github.com/karakeep-app/karakeep/blob/a1a887d5a0c311aacfbe13fcc080b1ddef5b8175/apps/mobile/app/server-address.tsx#L113-L218)
- [tRPC custom-header injection](https://github.com/karakeep-app/karakeep/blob/a1a887d5a0c311aacfbe13fcc080b1ddef5b8175/packages/shared-react/providers/trpc-provider.tsx#L42-L93)
- [Health, version, and local-asset requests](https://github.com/karakeep-app/karakeep/blob/a1a887d5a0c311aacfbe13fcc080b1ddef5b8175/apps/mobile/lib/utils.ts#L46-L58)
- [Upload custom headers](https://github.com/karakeep-app/karakeep/blob/a1a887d5a0c311aacfbe13fcc080b1ddef5b8175/apps/mobile/lib/upload.ts#L40-L71)
- [Asset authentication and scope checks](https://github.com/karakeep-app/karakeep/blob/a1a887d5a0c311aacfbe13fcc080b1ddef5b8175/packages/api/routes/assets.ts#L15-L71)
- [tRPC authentication and public procedures](https://github.com/karakeep-app/karakeep/blob/a1a887d5a0c311aacfbe13fcc080b1ddef5b8175/packages/trpc/index.ts#L136-L199)
- [API-key exchange and validation](https://github.com/karakeep-app/karakeep/blob/a1a887d5a0c311aacfbe13fcc080b1ddef5b8175/packages/trpc/routers/apiKeys.ts#L132-L214)
- [Native sign-in flow](https://github.com/karakeep-app/karakeep/blob/a1a887d5a0c311aacfbe13fcc080b1ddef5b8175/apps/mobile/app/signin.tsx#L67-L147)
- [Browser signup behavior](https://github.com/karakeep-app/karakeep/blob/a1a887d5a0c311aacfbe13fcc080b1ddef5b8175/apps/mobile/app/signin.tsx#L255-L279)

## Architecture

- **Active images**: `ghcr.io/karakeep-app/karakeep:0.33.2`,
  `ghcr.io/karakeep-app/karakeep-chrome:151.0.7922.47-r1`,
  `docker.io/getmeili/meilisearch:v1.41.0`, and
  `docker.io/tiredofit/db-backup:4.1.100`
- **Application user/group**: `3130:3130` (`svc-app-karakeep`) for the web,
  worker, Meilisearch, and database backup processes
- **Reverse proxy**: Traefik with `chain-auth@file` by default and a
  token-gated mobile route allowlist
- **Process model**: split web and worker processes with
  `USING_LEGACY_SEPARATE_CONTAINERS=true`

The upstream all-in-one image normally starts the web and workers under
s6-overlay as root. This stack launches each process directly under the
dedicated service account. The web process runs database migrations before
starting the server.

### Services

| Container              | Role                                                                  |
| ---------------------- | --------------------------------------------------------------------- |
| `karakeep-chrome`      | Headless Chromium for browser-rendered crawling and screenshots       |
| `karakeep-init`        | Validates required settings and assigns runtime directory ownership   |
| `karakeep`             | Web UI and API on the internal container port `3000`                  |
| `karakeep-db-backup`   | One-shot encrypted SQLite backup sidecar                              |
| `karakeep-workers`     | Background crawling, asset processing, indexing, and optional AI work |
| `karakeep-meilisearch` | Full-text search engine on the internal port `7700`                   |

### Browser Rendering and Screenshots

Browser crawling is enabled through `CRAWLER_HEADLESS_BROWSER=true` and
`BROWSER_WEB_URL=http://karakeep-chrome:9222` in the shared Karakeep
environment. The web service waits for a healthy Chrome service before
starting, and both the web and worker services can reach Chrome over the
internal `karakeep-browser` network. This enables JavaScript-rendered page
capture, browser-derived content, and screenshots in addition to Karakeep's
plain HTTP crawling path. See the upstream
[Docker guide](https://docs.karakeep.app/installation/docker/) and
[Chrome image migration guide](https://docs.karakeep.app/administration/chrome-image-migration/)
for the corresponding Karakeep settings and image model.

| Property         | Active configuration                                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Image            | `ghcr.io/karakeep-app/karakeep-chrome:151.0.7922.47-r1@sha256:5b19bbb160e9ff60681a3abd97e1c4ec9f64212301410de658c3900ab7ef31e7` |
| Architectures    | `linux/amd64`, `linux/arm64`                                                                                                    |
| Runtime identity | `65534:65534` (upstream non-root `nobody`)                                                                                      |
| Browser endpoint | `http://karakeep-chrome:9222` on the internal browser network only                                                              |
| Readiness check  | HTTP `GET /json/version` on `127.0.0.1:9222`                                                                                    |
| Memory           | `${CHROME_MEM_LIMIT:-2048m}`                                                                                                    |
| PID limit        | `100`                                                                                                                           |

The image entrypoint supplies Chromium's `--no-sandbox` option and publishes
the browser through socat from `0.0.0.0:9222` to Chrome on
`127.0.0.1:9223`. The Compose command retains these upstream browser flags
exactly:

- `--disable-gpu`
- `--disable-dev-shm-usage`
- `--hide-scrollbars`
- `--disable-blink-features=AutomationControlled`
- `--window-size=1440,900`

No Compose-level remote-debugging override is added. Chrome has no published
ports or Traefik labels and does not join `karakeep-frontend` or
`karakeep-backend`.

Enabling Chrome adds a default 2 GiB memory allowance and capacity for up to
100 additional PIDs. Size the host for that extra headroom on top of the web,
worker, Meilisearch, init, and backup containers. Override the Chrome memory
limit with `CHROME_MEM_LIMIT` when the host needs a different bound.

#### Browser Threat Model

<!-- dprint-ignore -->
!!! warning "Chromium runs without its browser sandbox"
    Saved URLs can cause Chrome to process attacker-controlled HTML,
    JavaScript, media, and browser subresources. The upstream entrypoint's
    `--no-sandbox` option is an explicit residual browser-engine risk, not a
    safe operating mode. A Chromium compromise or an SSRF flaw may still reach
    destinations available through the container's egress path.

Chrome runs under an explicit non-root identity with `init: true`, a read-only
root filesystem, `no-new-privileges=true`, all capabilities dropped, a
`/tmp` tmpfs, a 2 GiB default memory limit, and a 100-PID limit. Network
isolation prevents direct attachment to the frontend and backend application
networks, while an internal browser link exposes DevTools only to Karakeep web
and workers. These controls reduce blast radius; they do not eliminate browser
exploitation or SSRF risk.

Karakeep validates HTTP(S) URLs, resolved A/AAAA addresses, redirects, and
browser subrequests against private and reserved address ranges. No internal
hostname allowlists are configured in this deployment. The plain HTTP crawling
path pins the validated DNS result, but Playwright and Chrome resolve
hostnames independently after validation. DNS-rebinding and other
time-of-check/time-of-use protection is therefore not established for the
browser path.

The dedicated `karakeep-browser-egress` bridge supplies outbound routing; it is
not an RFC1918, link-local, or host-destination firewall. The internal browser
network limits Chrome's Docker service-to-service path to Karakeep web and
workers, but the egress bridge does not by itself prevent requests to private
destinations reachable through host routing. Review the upstream
[security considerations](https://docs.karakeep.app/administration/security-considerations/)
and the
[source revision reviewed for this deployment](https://github.com/karakeep-app/karakeep/tree/a1a887d5a0c311aacfbe13fcc080b1ddef5b8175)
when changing crawler or network controls.

#### Roll Back to Plain HTTP Crawling

To disable browser rendering and restore plain HTTP crawling:

1. Set `CRAWLER_HEADLESS_BROWSER=false`.
2. Remove `BROWSER_WEB_URL` from the shared Karakeep environment.
3. Remove the web service's `karakeep-chrome` dependency.
4. Remove the web and worker services from `karakeep-browser`.
5. Remove or disable the `karakeep-chrome` service and remove
   `karakeep-browser` and `karakeep-browser-egress`.

Links can still be fetched through the plain HTTP crawler, but JavaScript
rendering and screenshots are unavailable after this rollback.

### Security Model

- `karakeep-init` creates `./backups/db-backup`, then chowns it and both data
  directories to `3130:3130` before the runtime services start. It reaches the
  backup child through the `./backups:/backups` parent mount.
- The web, worker, and Meilisearch containers run as `3130:3130`.
- `karakeep-db-backup` starts s6 as root, then uses `USER_DBBACKUP=3130` and
  `GROUP_DBBACKUP=3130` to drop the backup process to the app-owned identity.
  It has no network and accesses Karakeep data only through a read-only mount.
- The backup sidecar drops all capabilities and adds only `CHOWN`,
  `DAC_OVERRIDE`, `FOWNER`, `SETGID`, `SETUID`, and `SETPCAP`.
  `DAC_OVERRIDE` is runtime-proven necessary for s6 to create root-owned
  runtime paths before dropping privileges; the others are the documented s6
  path-preparation and privilege-drop set.
- The web, worker, and Meilisearch containers use read-only root filesystems,
  `no-new-privileges=true`, dropped capabilities, PID limits, and memory
  limits. The backup sidecar omits the read-only root filesystem required by
  s6 but retains the other controls.
- Chrome uses its upstream non-root identity, a read-only root filesystem,
  `no-new-privileges=true`, dropped capabilities, `init: true`, a `/tmp`
  tmpfs, and explicit memory and PID limits. Its `/json/version` health check
  gates web startup.
- Only the web container is routed through Traefik. Meilisearch remains on the
  internal backend network, and Chrome remains on its isolated browser and
  egress networks.

## Volumes and Networks

### Volumes

| Host path            | Container path           | Used by         | Purpose                                                        |
| -------------------- | ------------------------ | --------------- | -------------------------------------------------------------- |
| `./backups`          | `/backups`               | Init            | Creates and assigns ownership of the `db-backup` child         |
| `./backups`          | `/backup-data`           | Database backup | Parent mount; output is written below `/backup-data/db-backup` |
| `./data/karakeep`    | `/data`                  | Web, workers    | SQLite database and saved assets                               |
| `./data/karakeep`    | `/karakeep-data` (`:ro`) | Database backup | Read-only source containing `db.db`                            |
| `./data/meilisearch` | `/meili_data`            | Meilisearch     | Regeneratable full-text search index                           |

### Networks

| Network                   | Members and purpose                                                          |
| ------------------------- | ---------------------------------------------------------------------------- |
| `karakeep-backend`        | Web, workers, and Meilisearch; internal application and search traffic       |
| `karakeep-browser`        | Web, workers, and Chrome; internal browser-control traffic only              |
| `karakeep-browser-egress` | Chrome only; outbound page fetches through a dedicated bridge                |
| `karakeep-frontend`       | Web and workers; Traefik access plus outbound crawling and optional AI calls |

## Secrets

Store these values in `secret.sops.env`, committed only in SOPS-encrypted form
and decrypted to `.env` during deployment. Do not commit plaintext values.

| Variable                      | Classification  | Purpose                                                        |
| ----------------------------- | --------------- | -------------------------------------------------------------- |
| `DB_ENC_PASSPHRASE`           | Required secret | Encrypts the `karakeep-db-backup` SQLite backup                |
| `DOMAINNAME`                  | Required config | Base domain for Traefik routing and NextAuth                   |
| `KARAKEEP_NEXTAUTH_SECRET`    | Required secret | Random secret used to protect Karakeep authentication sessions |
| `KARAKEEP_MEILI_MASTER_KEY`   | Required secret | Random Meilisearch master key                                  |
| `KARAKEEP_MOBILE_PROXY_TOKEN` | Required secret | Authenticates the official mobile client's Traefik bypass      |
| `KARAKEEP_OPENAI_API_KEY`     | Optional secret | User-supplied OpenAI API key for automatic AI tagging          |

Before rollout, ensure every required variable above exists in the
SOPS-encrypted service file. Add or rotate `KARAKEEP_MOBILE_PROXY_TOKEN` only
through the approved
[SOPS editing workflow](../CONTRIBUTING.md#generating-random-sops-secrets).
Do not regenerate or replace the other values during rollout. Preserve
`DB_ENC_PASSPHRASE` with the SOPS-encrypted service secrets because backups
cannot be decrypted without it.

`KARAKEEP_OPENAI_API_KEY` must be populated through SOPS to enable automatic AI
tagging. Leave it empty to keep automatic AI tagging disabled.

## Database Backup

The `karakeep-db-backup` sidecar (`tiredofit/db-backup`) produces an
application-consistent SQLite backup independently of the broader dataset
coverage:

| Property    | Value                                                                                                                                                                                                                                           |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cadence     | One-shot — runs whenever a full `dccd.sh`/`dccd-all` deployment starts it (`MODE=MANUAL`, `MANUAL_RUN_FOREVER=FALSE`, then exits); cadence follows the operator's deployment/cron schedule, documented as every 15 minutes with `-f` on TrueNAS |
| Source      | `/karakeep-data/db.db` (`./data/karakeep/db.db` on the host, mounted read-only); the result is a binary database copy, not a plain-text SQL dump                                                                                                |
| Consistency | SQLite Online Backup API while Karakeep remains online in WAL mode (`DB_WAL_MODE=true`)                                                                                                                                                         |
| Compression | ZSTD                                                                                                                                                                                                                                            |
| Checksum    | SHA1 sidecar file                                                                                                                                                                                                                               |
| Encryption  | GPG, via `DB_ENC_PASSPHRASE`                                                                                                                                                                                                                    |
| Retention   | 2880 minutes (48 hours)                                                                                                                                                                                                                         |
| Output      | `services/karakeep/backups/db-backup/`                                                                                                                                                                                                          |

The sidecar mounts the parent `./backups` directory at `/backup-data` and sets
`DEFAULT_FILESYSTEM_PATH=/backup-data/db-backup`. The image resets read-write
mount roots to root ownership during startup, while the pre-owned child keeps
the `3130:3130` ownership assigned by `karakeep-init`. Host output therefore
remains exactly `./backups/db-backup`.

The `*-db-backup` container name lets the default `dccd.sh -B` check discover
the job. `dccd-all` verifies that `karakeep-db-backup` exited successfully and
finished within the previous 48 hours; see
[Backup Strategy § Application-Level Database Backups](../BACKUP.md#application-level-database-backups)
for the full freshness-check mechanics.

The database backup does not include `./data/karakeep/assets`. These saved
assets are **critical mutable file state** and remain protected by the
`vm-pool` ZFS snapshot, replication, and off-site layers. The
`./data/meilisearch` directory is a regeneratable search index and is protected
by the same storage layers, but it does not need application-level backup.

### Synthetic Backup and Restore Validation

On September 13, 2026, the production Karakeep image, backup image, reduced
capability set, and `3130:3130` backup identity passed an end-to-end synthetic
test with Podman 5.8.6 while the source database remained live in WAL mode.
This was not a production deployment or a test on the TrueNAS host.

| Stage    | Evidence                                                                                                                                                                                                                                                                                          |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Source   | Karakeep 0.33.2 ran in WAL mode against the real `/data/db.db` schema; `karakeep-backup-sentinel` was inserted into a synthetic `synthetic_restore_probe` table                                                                                                                                   |
| Backup   | The exact pinned `tiredofit/db-backup:4.1.100` image started s6 as root with the reduced capability set, dropped the backup process to `3130:3130`, and produced exactly one encrypted GPG+ZSTD `sqlite3_db_*.sqlite3.zst.gpg` artifact, its `.sha1` sidecar, and the `latest-sqlite3_db` symlink |
| Artifact | SHA1 verification and GPG passphrase decryption passed; ZSTD decompression produced a binary file with the `SQLite format 3` header                                                                                                                                                               |
| Restore  | The database was restored into a disposable volume with the configured Karakeep service-account ownership, opened with Karakeep's own `better-sqlite3` runtime, and returned `ok` from `PRAGMA integrity_check`; the sentinel row matched                                                         |

**Restore guidance:** see
[Backup Strategy § Restore a Database Dump](../BACKUP.md#restore-a-database-dump)
for the decrypt, decompress, WAL/SHM cleanup, ownership restore, integrity
check, and restart procedure.

## First-Run Setup

The aliases from `/mnt/vm-pool/apps/scripts/aliases.sh` must already be sourced
in the current TrueNAS shell. The SOPS-encrypted service file must contain all
required values from [Secrets](#secrets). Preserve existing values when
provisioning the mobile proxy token.

1. Pull the repository changes and decrypt the committed SOPS secrets with the
   app-scoped alias:

   ```sh
   dccd-app karakeep
   ```

   On this first pass, dccd is expected to report that the `karakeep` TrueNAS
   Custom App configuration directory is missing and skip deployment. The pull
   and secret decryption still complete.

   **Do not start with `dccd-all`.** Traefik references the
   `karakeep-frontend` network before it exists; the Karakeep Custom App must
   create that network first.
2. From the updated TrueNAS checkout, provision the Karakeep host
   prerequisites:

   ```sh
   cd /mnt/vm-pool/apps
   sudo bash scripts/truenas-prep-app.sh karakeep
   ```

   The idempotent helper creates or verifies the `truenas-apps.json`-declared
   `svc-app-karakeep` group and user with the configured matching IDs and
   primary group. It does not add `truenas_admin` as an auxiliary group member.
   It creates the `vm-pool/apps/services/karakeep` child dataset, staging and
   restoring the existing service directory when needed, then sets the app
   directory ownership and mode. It refuses account identity collisions or
   mismatches. See
   [Infrastructure](../INFRASTRUCTURE.md#karakeep-dataset) for storage details.
3. In the TrueNAS UI, create a Custom App named `karakeep` with this standalone
   YAML:

   ```yaml
   include:
     - /mnt/vm-pool/apps/services/karakeep/compose.yaml
   services: {}
   ```

4. Run the canonical full deployment:

   ```sh
   dccd-all
   ```

   This decrypts the committed secrets, deploys Karakeep and its dependent
   integrations, runs the first one-shot database backup after Karakeep becomes
   healthy, and performs the default backup freshness check. Confirm that
   `karakeep-init` completes successfully and the Chrome, Meilisearch, web, and
   worker services become healthy.
5. Complete the application setup and validation:

   - Open `https://karakeep.${DOMAINNAME}` through Forward Auth and create the
     first local Karakeep account.
   - Configure the registration and access policy.
   - Save a bookmark for a public JavaScript-rendered page, then verify its
     browser-rendered content and screenshot. Do not use a private or internal
     URL as a crawler test.
   - Save a test note, then verify that full-text search returns the bookmark
     and note.
   - Verify that `karakeep-db-backup` exited successfully and that
     `services/karakeep/backups/db-backup/` contains a fresh backup artifact.

   AI tagging remains disabled until `KARAKEEP_OPENAI_API_KEY` is configured.
6. Configure every official mobile client as described in
   [Configure the Official Mobile App](#configure-the-official-mobile-app),
   then verify sign-in, bookmark retrieval, and an asset upload.

## Upgrade Notes

- Renovate manages image updates. Review the
  [Karakeep releases](https://github.com/karakeep-app/karakeep/releases) before
  major upgrades. For Chrome image changes, also review the upstream
  [Chrome image migration guide](https://docs.karakeep.app/administration/chrome-image-migration/).
- The web container applies database migrations before startup and uses a
  stop-first update order so the replacement does not serve traffic before
  migrations finish.
- Before a major upgrade, confirm a fresh `karakeep-db-backup` artifact exists
  and snapshot the complete `vm-pool/apps/services/karakeep` dataset so the
  SQLite database, saved assets, and Meilisearch index have a coordinated
  rollback point.
- Preserve the SOPS-encrypted secrets with the backup. The repository's ZFS
  snapshot, replication, and off-site strategy covers the child dataset; see
  [Backup Strategy](../BACKUP.md).
