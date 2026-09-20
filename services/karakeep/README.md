# Karakeep

[Karakeep](https://karakeep.app/) is a self-hosted bookmark manager for links,
notes, and images, with full-text search and optional AI tagging.

## Why

Karakeep keeps saved content and its search index on locally managed storage.
The split web, worker, and search services isolate background crawling and
indexing from the user-facing application. Crawling currently uses plain HTTP:
JavaScript rendering and new screenshots are disabled while a DHI browser
and filtering proxy are staged pending a verified patched browser image.

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
  `docker.io/getmeili/meilisearch:v1.41.0`, and
  `docker.io/tiredofit/db-backup:4.1.100`
- **Staged, disabled images**: `dhi.io/playwright:1.63.0-debian13` and
  `docker.io/ubuntu/squid:7.2-26.04_edge`
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

| Container                | Role                                                                          |
| ------------------------ | ----------------------------------------------------------------------------- |
| `karakeep`               | Web UI and API on the internal container port `3000`                          |
| `karakeep-browser-proxy` | Staged stateless Squid proxy; disabled by default                             |
| `karakeep-chrome`        | Staged DHI browser; disabled by default and blocked by a minimum-version gate |
| `karakeep-db-backup`     | One-shot encrypted SQLite backup sidecar                                      |
| `karakeep-init`          | Validates required settings and assigns runtime directory ownership           |
| `karakeep-meilisearch`   | Full-text search engine on the internal port `7700`                           |
| `karakeep-workers`       | Background crawling, asset processing, indexing, and optional AI work         |

### Browser Rendering and Screenshots

**Current mode: plain HTTP only.** `CRAWLER_HEADLESS_BROWSER=false`,
`BROWSER_WEB_URL` is absent, and the web service has no Chrome dependency.
Both Chrome and Squid are in the default-off
`browser-pending-security-update` profile. JavaScript rendering, new
screenshots, and browser interactions are unavailable; existing saved assets
are retained.

<!-- dprint-ignore -->
!!! warning "Existing deployments must explicitly stop the old browser"
    Stop `karakeep-chrome` and its old browser proxy if present, and verify
    they are stopped before relying on HTTP-only operation. If changedetection
    was also deployed, explicitly stop `changedetection-chrome` and its proxy.
    An inactive profile is not a guarantee that dccd removes already-running
    containers. Keep the browser profile off.

The staged browser is `dhi.io/playwright:1.63.0-debian13`, initially tag-only
under the repository's DHI adoption rule; Renovate will add the digest pin.
The inspected image contains vulnerable Chromium `153.0.8010.47-2~deb13u1`.
The shared read-only `../shared/config/browser/launch.mjs` rejects versions
below `153.0.8010.52` before launching Chromium. It stages a stable IPv4 CDP
relay on port `9222` to Chromium's loopback port `9223`, not a working-browser
claim. The Node health check verifies `/json/version` and its WebSocket URL.
No custom image publication is needed.

The staged definition runs as DHI's `65532:65532`, joins only the internal
IPv4 `karakeep-browser` network, and waits for a healthy Squid proxy. It has
no published ports, Traefik labels, frontend, or backend membership.
Its command sets `--proxy-server=http://karakeep-browser-proxy:3128`,
`--proxy-bypass-list=<-loopback>` (removes the implicit loopback bypass),
`--disable-quic`, and
`--force-webrtc-ip-handling-policy=disable_non_proxied_udp`.

If later approved for enablement, Chrome has a default 2 GiB memory allowance
and the proxy adds `${BROWSER_PROXY_MEM_LIMIT:-256m}`. Each has its own 100-PID limit. Size the
host for both in addition to the web, worker, Meilisearch, init, and backup
containers.

#### Public-Website-Only Browser Proxy

`karakeep-browser-proxy` uses the operator-approved, digest-pinned Canonical
`docker.io/ubuntu/squid:7.2-26.04_edge` image and mounts
`../shared/config/browser/squid.conf` read-only. The staged policy permits
only eligible public destinations on ports `80`/`443`, with `CONNECT`
restricted to `443`.
See the [shared browser egress policy](../ARCHITECTURE.md#browser-egress-policy-public-websites-only)
for private/reserved IPv4, native IPv6, and transition-address filtering.

The proxy runs as `65534:65534`, with a read-only root, `cap_drop: ALL`,
`no-new-privileges`, a 100-PID limit, and only `/tmp` as writable scratch.
It has no published ports, persistent state, disk cache, or URL access log.
Its bundled Perl health check requires an HTTP `403` for a loopback
destination. Both staged services use `config.watch=../shared/config/browser`
and `config.sha256` so the launcher and policy are watched together.
Config-change recreation applies when services are enabled; it does not
activate the profile. No new secret, database, or host dependency is required.

Internal-site crawling is intentionally unsupported. Do not add `DIRECT`
fallbacks, proxy bypass rules, or extra Chrome egress networks to restore it.

#### Browser Threat Model

<!-- dprint-ignore -->
!!! warning "Staged browser hardening does not make the image safe"
    If enabled, Chrome would process attacker-controlled HTML, JavaScript,
    media, and subresources. The launcher's `--no-sandbox` option is an
    explicit residual browser-engine risk, not a safe operating mode.
    Filtering browser HTTP(S) does not make Chrome
    zero-day-proof or fully contain a native-code compromise. Chrome can
    still reach its web, worker, and proxy peers on the shared internal
    control network.

The staged Chrome definition has an explicit non-root identity, `init: true`,
a read-only root filesystem, `no-new-privileges=true`, all capabilities dropped, a
`/tmp` tmpfs, a 2 GiB default memory limit, and a 100-PID limit. Network
isolation prevents direct attachment to the frontend and backend application
networks. The internal browser network necessarily includes Karakeep web,
workers, and the proxy, so these peers can reach DevTools. Removing Chrome's
direct internet route and filtering its HTTP(S) requests reduces exposure;
it does not isolate a compromised native browser from those peers.

Karakeep validates HTTP(S) URLs, resolved A/AAAA addresses, redirects, and
browser subrequests against private and reserved address ranges. No internal
hostname allowlists are configured in this deployment. The plain HTTP crawling
path pins the validated DNS result. The staged browser HTTP(S) path uses Squid's
destination checks rather than relying only on app-side validation before
browser resolution. This targets redirect/subresource SSRF; it is not a
blanket guarantee against every DNS-rebinding or native-code attack. The
web/worker plain HTTP path and optional AI calls retain their own egress and
are not forced through this browser proxy. Review the upstream
[security considerations](https://docs.karakeep.app/administration/security-considerations/)
and the
[source revision reviewed for this deployment](https://github.com/karakeep-app/karakeep/tree/a1a887d5a0c311aacfbe13fcc080b1ddef5b8175)
when changing crawler or network controls.

#### Browser Remediation Status

The pinned Squid image passed public HTTP and certificate-validated HTTPS
tests plus controlled denial tests for private literals/hostnames,
IPv4-mapped IPv6, NAT64, 6to4, forbidden ports, and disallowed `CONNECT`.
The tests used only the controlled proxy, without contacting real LAN
services. See the [rootful test-runtime requirement](../INFRASTRUCTURE.md#stateless-browser-proxies).

**The mitigation is disabled browser execution, not restored JavaScript
features.** Prior browser evidence is historical, not proof that the DHI
image works or is patched. Future enablement requires a verified patched DHI
image, browser integration tests, and reviewed app environment/dependency
changes. Setting `COMPOSE_PROFILES` alone does not enable the app's fetcher.
Do not enable the current image or lower the version gate. See
[the shared security gate](../ARCHITECTURE.md#browser-egress-policy-public-websites-only).

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
- Staged Chrome uses DHI's non-root identity, a read-only root filesystem,
  `no-new-privileges=true`, dropped capabilities, `init: true`, a `/tmp`
  tmpfs, and explicit memory and PID limits. Its `/json/version` check does
  not gate web startup while browser features are disabled.
- The staged stateless browser proxy uses `65534:65534`, distinct from DHI.
  It has a read-only root, dropped capabilities, and bounded resources.
  The staged Chrome definition waits for its denial-check health probe.
- Only the web container is routed through Traefik. Meilisearch remains on the
  internal backend network. Chrome is internal-browser-network-only; only the
  browser proxy joins the browser egress bridge.

## Volumes and Networks

### Volumes

| Host path                             | Container path                    | Used by              | Purpose                                                        |
| ------------------------------------- | --------------------------------- | -------------------- | -------------------------------------------------------------- |
| `./backups`                           | `/backups`                        | Init                 | Creates and assigns ownership of the `db-backup` child         |
| `./backups`                           | `/backup-data`                    | Database backup      | Parent mount; output is written below `/backup-data/db-backup` |
| `./data/karakeep`                     | `/data`                           | Web, workers         | SQLite database and saved assets                               |
| `./data/karakeep`                     | `/karakeep-data` (`:ro`)          | Database backup      | Read-only source containing `db.db`                            |
| `./data/meilisearch`                  | `/meili_data`                     | Meilisearch          | Regeneratable full-text search index                           |
| `../shared/config/browser/launch.mjs` | `/opt/browser/launch.mjs` (`:ro`) | Staged Chrome        | Shared version gate and CDP relay; no persistent browser data  |
| `../shared/config/browser/squid.conf` | `/etc/squid/squid.conf` (`:ro`)   | Staged browser proxy | Shared public-website-only policy; no persistent proxy data    |

### Networks

Chrome/proxy memberships below are staged definitions; neither service runs
under the default profile selection.

| Network                   | Members and purpose                                                          |
| ------------------------- | ---------------------------------------------------------------------------- |
| `karakeep-backend`        | Web, workers, and Meilisearch; internal application and search traffic       |
| `karakeep-browser`        | Web, workers, Chrome, and browser proxy; internal CDP and HTTP proxy traffic |
| `karakeep-browser-egress` | Browser proxy only; outbound connections to permitted public websites        |
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
   `karakeep-init` completes successfully and Meilisearch, web, and workers
   become healthy. Chrome and the browser proxy must remain stopped.
5. Complete the application setup and validation:

   - Open `https://karakeep.${DOMAINNAME}` through Forward Auth and create the
     first local Karakeep account.
   - Configure the registration and access policy.
   - Save a public-page bookmark that works without JavaScript and verify its
     plain HTTP content. Do not use a private/internal URL as a crawler test
     or expect a new browser screenshot.
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
  major upgrades. Keep browser features off until the staged DHI image is
  verified patched and the browser integration has passed review and tests.
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
