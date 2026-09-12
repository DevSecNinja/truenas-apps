# Memos

[Memos](https://usememos.com/) is a private, self-hosted note-taking and knowledge service.

## Why

Memos provides a lightweight place to capture and organize notes while keeping the database and uploaded assets on the TrueNAS host.

## Compose Files

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/memos/compose.yaml)
- [secret.sops.env](https://github.com/DevSecNinja/truenas-apps/blob/main/services/memos/secret.sops.env)

## Access

| URL                           | Auth                                 | Description |
| ----------------------------- | ------------------------------------ | ----------- |
| `https://memos.${DOMAINNAME}` | Traefik Forward Auth + Memos account | Web UI      |

Traefik applies `chain-auth@file` before requests reach Memos, which then uses its own account authentication.

## Architecture

- **Image**: `docker.io/neosmemo/memos:0.30.0`
- **User/Group**: `3129:3129` (`svc-app-memos`)
- **Network**: `memos-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **Storage**: `./data` is mounted at `/var/opt/memos`
- **Init image**: `docker.io/library/busybox:1.38.0`

### Services

| Container         | Role                                                                             |
| ----------------- | -------------------------------------------------------------------------------- |
| `memos-init`      | One-shot init: chowns `./data` to `3129:3129`                                    |
| `memos`           | Non-root Memos application using SQLite                                          |
| `memos-db-backup` | One-shot `tiredofit/db-backup` sidecar — see [Database Backup](#database-backup) |

### Volumes

| Host path             | Container path   | Purpose                                      |
| --------------------- | ---------------- | -------------------------------------------- |
| `./data`              | `/var/opt/memos` | SQLite database and locally uploaded assets  |
| `./data` (`:ro`)      | `/memos-data`    | Read-only source for `memos-db-backup`       |
| `./backups/db-backup` | `/backup`        | Encrypted, compressed database backup output |

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

| Variable            | Purpose                                                                       |
| ------------------- | ----------------------------------------------------------------------------- |
| `DOMAINNAME`        | Existing user-supplied deployment domain used for Traefik routing             |
| `DB_ENC_PASSPHRASE` | Encrypts the `memos-db-backup` SQLite backup (GPG, via `tiredofit/db-backup`) |

Memos itself does not require any application-generated random secrets;
`DB_ENC_PASSPHRASE` is generated once for the backup sidecar following the
[SOPS secrets skill](../../.github/skills/sops-secrets/SKILL.md).

## Database Backup

The `memos-db-backup` sidecar (`tiredofit/db-backup`) produces an
application-consistent SQLite backup that is independent of the broader
`./data` coverage described below:

| Property    | Value                                                                                                                                                                                                                                                                                   |
| ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cadence     | One-shot — runs whenever a full `dccd.sh`/`dccd-all` deployment starts it (`MODE=MANUAL`, exits after one run); cadence follows the operator's deployment/cron schedule (documented as every 15 minutes with `-f` on TrueNAS) rather than an intrinsic in-container or nightly schedule |
| Source      | `/memos-data/memos_prod.db` (`./data` mounted `:ro`), read via the SQLite Online Backup API — produces a binary database file copy, not a plain-text SQL dump                                                                                                                           |
| Compression | ZSTD                                                                                                                                                                                                                                                                                    |
| Checksum    | SHA1 sidecar file                                                                                                                                                                                                                                                                       |
| Encryption  | GPG, via `DB_ENC_PASSPHRASE`                                                                                                                                                                                                                                                            |
| Retention   | 2880 minutes (48 hours)                                                                                                                                                                                                                                                                 |
| Output      | `services/memos/backups/db-backup/`                                                                                                                                                                                                                                                     |

`dccd-all` runs the default `dccd.sh -B` backup-freshness check, which
verifies `memos-db-backup` exited `0` and finished within the last 48 hours —
see [Backup Strategy § Application-Level Database Backups](../BACKUP.md#application-level-database-backups)
for the full freshness-check mechanics.

Memos 0.30 defaults attachment storage to SQLite blobs rather than local
files, so a single consistent `memos_prod.db` backup captures both notes and
uploaded attachments as of that backup — there is no separate attachment
directory to restore alongside it under this default configuration. If the
storage driver is later changed to local disk or S3, revisit this section and
the volumes above.

**Restore guidance:** see [Backup Strategy § Restore a Database Dump](../BACKUP.md#restore-a-database-dump)
for the full decrypt → decompress → restore procedure, including the
WAL/SHM cleanup and `chown 3129:3129` ownership-restore steps specific to
Memos (the application runs as the non-root `svc-app-memos` account).

**Broader `./data` coverage:** the entire `./data` directory (database plus
any non-blob assets) is also covered by the host's [ZFS snapshot, replication,
and off-site layers](../BACKUP.md#layer-1-zfs-periodic-snapshots) like every
other app's bind-mounted state on `vm-pool`. The `memos-db-backup` sidecar
exists in addition to that coverage — it provides a portable, encrypted,
engine-consistent backup that can be restored independently of the host's
ZFS state.

## First-Run Setup

The aliases must already be sourced from
`/mnt/vm-pool/apps/scripts/aliases.sh` on `svlnas`.

1. After the changes merge, pull them and decrypt the SOPS files with the
   app-scoped alias:

   ```sh
   dccd-app memos
   ```

   Because the `memos` TrueNAS Custom App does not exist yet, dccd will report
   that its TrueNAS app config directory is missing and skip deployment. This is
   expected for the first pass. Do not start with `dccd-all`: Traefik already
   references the frontend network that the new Custom App will create.
2. From the updated TrueNAS checkout, run the host preparation helper:

   ```sh
   cd /mnt/vm-pool/apps
   sudo bash scripts/truenas-prep-app.sh memos
   ```

   The idempotent helper creates or verifies the `truenas-apps.json`-declared
   Memos group and user, creates the child ZFS dataset without discarding the
   existing checkout, and sets the app directory ownership and mode. The Memos
   registry entry does not request administrative auxiliary group membership.
3. In the TrueNAS UI, create a Custom App named `memos` with:

   ```yaml
   include:
     - /mnt/vm-pool/apps/services/memos/compose.yaml
   services: {}
   ```

4. Run the canonical final deployment:

   ```sh
   dccd-all
   ```

   This deploys Memos and applies its dependent AdGuard and Traefik changes
   through the normal TrueNAS ordering, decrypts secrets, and runs the default
   backup freshness check. Confirm that `memos-init` completes and Memos is
   healthy.
5. Open `https://memos.${DOMAINNAME}`, create the first Memos account, configure
   the registration and access policy in the admin settings, and verify access.

## Upgrade Notes

Image updates are managed by Renovate; the initial tag-only adoption will receive
a digest pin automatically. Before major upgrades, snapshot `./data` and review
the [upstream release notes](https://github.com/usememos/memos/releases).
