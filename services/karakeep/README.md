# Karakeep

[Karakeep](https://karakeep.app/) is a self-hosted bookmark manager for links,
notes, and images, with full-text search and optional AI tagging.

## Why

Karakeep keeps saved content and its search index on locally managed storage.
The split web, worker, and search services isolate background crawling and
indexing from the user-facing application. Headless browser support remains
available only as an explicit opt-in reference.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/karakeep/compose.yaml)

## Access and Authentication

| URL                              | Authentication                                      |
| -------------------------------- | --------------------------------------------------- |
| `https://karakeep.${DOMAINNAME}` | Traefik Forward Auth, then Karakeep local user auth |

The Traefik router applies `chain-auth@file` to every request. Karakeep keeps
its own local account authentication as a second layer.

<!-- dprint-ignore -->
!!! warning "API and mobile client limitation"
    No API or mobile-client Forward Auth bypass is configured. Clients that
    cannot complete the interactive Forward Auth flow or reuse its browser
    session may not work with this deployment. Do not switch clients to an
    unprotected endpoint; add a narrowly scoped authenticated bypass only
    after reviewing the exposed API surface.

## Architecture

- **Active images**: `ghcr.io/karakeep-app/karakeep:0.33.2`,
  `docker.io/getmeili/meilisearch:v1.41.0`, and
  `docker.io/tiredofit/db-backup:4.1.100`
- **Application user/group**: `3130:3130` (`svc-app-karakeep`) for the web,
  worker, Meilisearch, and database backup processes
- **Reverse proxy**: Traefik with `chain-auth@file`
- **Process model**: split web and worker processes with
  `USING_LEGACY_SEPARATE_CONTAINERS=true`

The upstream all-in-one image normally starts the web and workers under
s6-overlay as root. This stack launches each process directly under the
dedicated service account. The web process runs database migrations before
starting the server.

### Services

| Container              | Role                                                                  |
| ---------------------- | --------------------------------------------------------------------- |
| `karakeep-init`        | Validates required settings and assigns runtime directory ownership   |
| `karakeep`             | Web UI and API on the internal container port `3000`                  |
| `karakeep-db-backup`   | One-shot encrypted SQLite backup sidecar                              |
| `karakeep-workers`     | Background crawling, asset processing, indexing, and optional AI work |
| `karakeep-meilisearch` | Full-text search engine on the internal port `7700`                   |

### Optional Browser Crawling

`CRAWLER_HEADLESS_BROWSER=false` is the default, and the complete
`karakeep-chrome` Compose service remains commented out as an opt-in reference.
The browser container is not created and does not join either Karakeep network
during a normal deployment.

Without Chrome, links, notes, images and other assets, SQLite persistence,
Meilisearch full-text search, and optional AI tagging continue to work.
Browser-rendered crawling, screenshots, and full-page browser captures are
unavailable.

The optional image reference is
`ghcr.io/karakeep-app/karakeep-chrome:151.0.7922.47-r1`.

<!-- dprint-ignore -->
!!! warning "Explicit risk acceptance required"
    The browser processes attacker-controlled pages, and Karakeep's upstream
    Chrome image starts Chromium with `--no-sandbox`. Running it as non-root
    with a read-only root filesystem, dropped capabilities, no published
    ports, and resource limits reduces exposure but does not make that
    additional attack surface acceptable by default.

To opt in later:

1. Explicitly reassess and accept the browser risk.
2. Uncomment the complete `karakeep-chrome` service definition in
   `compose.yaml`.
3. Add `BROWSER_WEB_URL: http://karakeep-chrome:9222` to the shared Karakeep
   environment.
4. Restore the `karakeep` web service's `service_healthy` dependency on
   `karakeep-chrome`.

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
- Only the web container is routed through Traefik. Meilisearch remains on the
  internal backend network.

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

| Network             | Members and purpose                                                          |
| ------------------- | ---------------------------------------------------------------------------- |
| `karakeep-frontend` | Web and workers; Traefik access plus outbound crawling and optional AI calls |
| `karakeep-backend`  | Internal communication between web, workers, and Meilisearch                 |

## Secrets

Store these values in `secret.sops.env`, committed only in SOPS-encrypted form
and decrypted to `.env` during deployment. Do not commit plaintext values.

| Variable                    | Classification  | Purpose                                                        |
| --------------------------- | --------------- | -------------------------------------------------------------- |
| `DB_ENC_PASSPHRASE`         | Required secret | Encrypts the `karakeep-db-backup` SQLite backup                |
| `DOMAINNAME`                | Required config | Base domain for Traefik routing and NextAuth                   |
| `KARAKEEP_NEXTAUTH_SECRET`  | Required secret | Random secret used to protect Karakeep authentication sessions |
| `KARAKEEP_MEILI_MASTER_KEY` | Required secret | Random Meilisearch master key                                  |
| `KARAKEEP_OPENAI_API_KEY`   | Optional secret | User-supplied OpenAI API key for automatic AI tagging          |

The encrypted service secrets are already committed. Do not regenerate or
replace them during rollout. Preserve `DB_ENC_PASSPHRASE` with the
SOPS-encrypted service secrets because backups cannot be decrypted without it.

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
in the current TrueNAS shell. The encrypted service secrets are committed and
must not be regenerated by the operator.

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
   `karakeep-init` completes successfully and the Meilisearch, web, and worker
   services become healthy.
5. Complete the application setup and validation:

   - Open `https://karakeep.${DOMAINNAME}` through Forward Auth and create the
     first local Karakeep account.
   - Configure the registration and access policy.
   - Save a test link and a test note, then verify that full-text search returns
     them.
   - Verify that `karakeep-db-backup` exited successfully and that
     `services/karakeep/backups/db-backup/` contains a fresh backup artifact.

   AI tagging remains disabled until `KARAKEEP_OPENAI_API_KEY` is configured.
   Browser crawling and screenshots remain disabled.

## Upgrade Notes

- Renovate manages image updates. Review the
  [Karakeep releases](https://github.com/karakeep-app/karakeep/releases) before
  major upgrades.
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
