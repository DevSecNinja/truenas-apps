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
  worker, and Meilisearch processes
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

- `karakeep-init` chowns both runtime directories to `3130:3130`, then exits
  before the runtime services start.
- The web, worker, and Meilisearch containers run as `3130:3130`.
- `karakeep-db-backup` uses its root backup identity (`USER_DBBACKUP=0` and
  `GROUP_DBBACKUP=0`) rather than the Karakeep service account. It has no
  network and accesses Karakeep data only through a read-only mount.
- Runtime containers use read-only root filesystems,
  `no-new-privileges=true`, dropped capabilities, PID limits, and memory
  limits.
- Only the web container is routed through Traefik. Meilisearch remains on the
  internal backend network.

## Volumes and Networks

### Volumes

| Host path             | Container path           | Used by         | Purpose                                    |
| --------------------- | ------------------------ | --------------- | ------------------------------------------ |
| `./data/karakeep`     | `/data`                  | Web, workers    | SQLite database and saved assets           |
| `./data/karakeep`     | `/karakeep-data` (`:ro`) | Database backup | Read-only source containing `db.db`        |
| `./data/meilisearch`  | `/meili_data`            | Meilisearch     | Regeneratable full-text search index       |
| `./backups/db-backup` | `/backup`                | Database backup | Encrypted, compressed SQLite backup output |

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

`DB_ENC_PASSPHRASE` is an independent, random, app-owned secret. Generate it
once and preserve it with the SOPS-encrypted service secrets; backups cannot be
decrypted without it.

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

On September 13, 2026, the production Karakeep image, backup image, and
configuration passed an end-to-end synthetic test with Podman 5.8.6. This was
not a production deployment or a test on the TrueNAS host.

| Stage    | Evidence                                                                                                                                                                                                                                  |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Source   | Karakeep 0.33.2 ran in WAL mode against the real `/data/db.db` schema; `karakeep-backup-sentinel` was inserted into a synthetic `synthetic_restore_probe` table                                                                           |
| Backup   | The exact pinned `tiredofit/db-backup:4.1.100` image and production settings exited successfully and produced exactly one `sqlite3_db_*.sqlite3.zst.gpg` artifact, its `.sha1` sidecar, and the `latest-sqlite3_db` symlink               |
| Artifact | SHA1 verification and GPG passphrase decryption passed; ZSTD decompression produced a binary file with the `SQLite format 3` header                                                                                                       |
| Restore  | The database was restored into a disposable volume with the configured Karakeep service-account ownership, opened with Karakeep's own `better-sqlite3` runtime, and returned `ok` from `PRAGMA integrity_check`; the sentinel row matched |

**Restore guidance:** see
[Backup Strategy § Restore a Database Dump](../BACKUP.md#restore-a-database-dump)
for the decrypt, decompress, WAL/SHM cleanup, ownership restore, integrity
check, and restart procedure.

## First-Run Setup

1. From the repository root on TrueNAS, provision the Karakeep host
   prerequisites:

   ```sh
   sudo bash scripts/truenas-prep-app.sh karakeep
   ```

   The helper creates or verifies the `svc-app-karakeep` group with GID 3130,
   the `svc-app-karakeep` user with UID 3130 and that primary group, and the
   `vm-pool/apps/services/karakeep` child dataset. It does not add
   `truenas_admin` to the service group (`ADMIN_GROUP_MEMBER=false`). When
   creating the child dataset, it stages and restores the existing service
   directory. The command is safe to rerun and refuses account identity
   collisions or mismatches. See
   [Infrastructure](../INFRASTRUCTURE.md#karakeep-dataset) for storage details.
2. Generate independent random values for `KARAKEEP_NEXTAUTH_SECRET`,
   `KARAKEEP_MEILI_MASTER_KEY`, and `DB_ENC_PASSPHRASE`, then populate and
   encrypt `services/karakeep/secret.sops.env` with SOPS.
3. Optionally populate `KARAKEEP_OPENAI_API_KEY` through SOPS to enable
   automatic AI tagging; otherwise leave it empty.
4. Run `dccd-all`. It deploys the stack, starts the first one-shot database
   backup after Karakeep becomes healthy, and runs the default backup freshness
   check. Confirm `karakeep-init` completes successfully; Meilisearch, the web
   service, and the worker service become healthy; the web process completes
   its database migrations; and `karakeep-db-backup` exits successfully.
5. Open `https://karakeep.${DOMAINNAME}` through Forward Auth and complete the
   Karakeep local account setup.

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
