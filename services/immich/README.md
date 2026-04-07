# Immich

Immich is a self-hosted photo and video management solution with mobile backup, facial recognition, and smart search.

## Access

| URL                                  | Description                                                         |
| ------------------------------------ | ------------------------------------------------------------------- |
| `https://photos.<DOMAINNAME>`        | Web UI and API (proxied through Traefik, forward-auth protected)    |
| `https://photos-noauth.<DOMAINNAME>` | Mobile app endpoint (no forward-auth — Immich handles its own auth) |

The dual-route setup is necessary because Immich does not support OAuth/OIDC for its mobile app clients. The `noauth` route is protected only by Immich's own authentication, not Traefik forward-auth.

## Architecture

- **Images**: [immich-app/immich-server](https://github.com/immich-app/immich), [immich-app/immich-machine-learning](https://github.com/immich-app/immich), [immich-app/postgres](https://github.com/immich-app/immich) (custom Postgres with pgvecto.rs + vectorchord extensions), [valkey/valkey](https://github.com/valkey-io/valkey)
- **Hardware transcoding**: Intel QuickSink via `/dev/dri` — switch the `extends.service` entry in `compose.yaml` to match your GPU (cpu, nvenc, rkmpp, vaapi)
- **User/Group**: `3106:3202` (`svc-app-immich:private-photos`) — all writable paths are owned to this UID:GID by the init container on every deploy
- **Networks**: `immich-frontend` (Traefik-facing) and `immich-backend` (internal — server, ML, Redis, Postgres)

### Config File

Immich settings that would normally live in the admin UI are instead managed via a git-tracked
YAML config file (`config/immich.yaml`). This makes the configuration auditable, version-controlled,
and reproducible across rebuilds.

The config file uses `${VAR}` placeholders for secrets. The `immich-config-init` container runs
`config/envsubst.sh` at deploy time to substitute values from `secret.sops.env` and writes the
processed output to `data/immich.yaml`, which `immich-server` mounts read-only via `IMMICH_CONFIG_FILE`.

Key settings in `config/immich.yaml`:

- **`oauth`**: Microsoft Entra ID OIDC login — credentials from `secret.sops.env`, mobile redirect
  points to the `photos-noauth` route so the Immich mobile app bypasses forward-auth
- **`passwordLogin`**: Kept enabled alongside OAuth; disable once OAuth is confirmed working
- **`storageTemplate`**: Enabled with `{{y}}/{{MM}}/{{filename}}` — organizes originals by year/month
  on disk, keeping the raw file tree readable by any future tool without Immich running
- **`server.externalDomain`**: Set to `https://photos.${DOMAINNAME}` for correct share link generation

### Services

| Container                 | Role                                                                                        |
| ------------------------- | ------------------------------------------------------------------------------------------- |
| `immich-init`             | One-shot init: chowns all writable paths to `3106:3202` and substitutes config placeholders |
| `immich-server`           | Main API server and web UI                                                                  |
| `immich-machine-learning` | Face recognition, CLIP embeddings, smart search                                             |
| `immich-redis`            | Valkey (Redis-compatible) — job queue cache, ephemeral only                                 |
| `immich-db`               | Custom Postgres with pgvecto.rs and vectorchord vector extensions                           |
| `immich-db-backup`        | One-shot nightly backup sidecar (restarted by `dccd.sh`, then exits)                        |

### Init Container

`immich-init` runs once before the main services start and does two things in sequence:

1. **Chowns all writable bind-mount paths** to `3106:3202` — recovers from any host-level permission reset (e.g. a TrueNAS dataset ACL reset) on every deploy
2. **Runs `config/envsubst.sh`** — substitutes `${VAR}` placeholders in `config/immich.yaml` with values from `secret.sops.env` and writes the result to `data/immich.yaml`

`DAC_OVERRIDE` is required because the originals path (`/mnt/archive-pool/private/photos/immich`) is owned by `truenas_admin:truenas_admin 770` — UID 0 inside the container has no permissions without it. It also allows overwriting the existing `data/immich.yaml` on redeployments.

`CHOWN` is required to transfer ownership to `3106:3202`.

The GID `3202` is hardcoded in the `command:` block because `env_file` values are injected into the container environment and do not feed into Docker Compose variable substitution for `user:` and `command:` fields.

### Database

The `immich-db` image is a custom Postgres build from the Immich project that bundles the `pgvecto.rs` and `vectorchord` extensions required for ML-powered search. Standard `pgautoupgrade` images do not include these extensions, so **automated Postgres major version upgrades are not used here**. See [DATABASE-UPGRADES.md](../../docs/DATABASE-UPGRADES.md) and the [Immich Postgres upgrade docs](https://immich.app/docs/administration/postgres-upgrade) before performing any major version upgrade.

### Database Backup

`immich-db-backup` uses [tiredofit/db-backup](https://github.com/tiredofit/docker-db-backup) in `MODE=MANUAL` with `MANUAL_RUN_FOREVER=FALSE` — it runs one backup and exits cleanly. The nightly CD script (`dccd.sh`) restarts it each run. Backups are ZSTD-compressed, SHA1-checksummed, AES-encrypted with `DB_ENC_PASSPHRASE`, and retained for 48 hours.

## Storage Layout

Immich's storage is split across two pools to separate irreplaceable data (backed up) from regeneratable caches (not backed up):

| What              | Host Path                                 | Pool         | Backed up?                    |
| ----------------- | ----------------------------------------- | ------------ | ----------------------------- |
| Originals         | `/mnt/archive-pool/private/photos/immich` | archive-pool | ✅ ZFS snapshots              |
| Thumbnails        | `./data/thumbs`                           | vm-pool SSD  | ❌ Regeneratable              |
| Encoded video     | `./data/encoded-video`                    | vm-pool SSD  | ❌ Regeneratable              |
| ML model cache    | `./data/model-cache`                      | vm-pool SSD  | ❌ Regeneratable              |
| Postgres database | `./data/db`                               | vm-pool SSD  | ✅ `immich-db-backup` sidecar |

`THUMBS_DIR` and `ENCODED_VIDEO_DIR` are not official Immich environment variables — Immich stores all
media under a single internal path and creates subdirectories (`library/`, `thumbs/`, `encoded-video/`,
etc.) relative to it automatically. The split is achieved instead via Docker overlay bind mounts: the
archive-pool path is mounted at `/usr/src/app/upload`, then vm-pool SSD paths are mounted at the
specific subdirectories Immich writes caches to (`/usr/src/app/upload/thumbs`,
`/usr/src/app/upload/encoded-video`). Docker honors the more specific mount point — thumbnail and
encoded-video writes land on vm-pool SSD while originals (written under `library/`) stay on archive-pool.

The `private-photos` group (GID 3202) on the originals path means any future tool (e.g. PhotoPrism) can be granted read access by joining that group — no ownership restructuring needed.

## TrueNAS Host Setup

Perform these steps once on the TrueNAS host before first deploy:

1. Create a `private-photos` group (GID 3202) and add `truenas_admin` as an auxiliary member
2. Create a dedicated `svc-app-immich` user (UID 3106) with primary group `private-photos` (GID 3202)
3. Set Unix permissions on the parent private dataset (`/mnt/archive-pool/private`):
   - User: `truenas_admin`, Group: `truenas_admin`, mode `770` (no access for others)
   - No NFSv4 ACLs needed — subdirectory access is managed by init containers
4. Create the dataset `vm-pool/apps/services/immich` in TrueNAS

## Entra ID App Registration

Create an App Registration in the [Azure Portal](https://portal.azure.com/) → **Microsoft Entra ID → App registrations → New registration**:

1. **Name**: `Immich` (or any name you prefer)
2. **Supported account types**: Accounts in this organizational directory only (single tenant)
3. **Redirect URI**: leave blank for now — add them after creation (see below)
4. Click **Register**

After registration:

5. **Overview tab** — note the **Application (client) ID** and **Directory (tenant) ID**
6. **Authentication tab → Add a platform → Web**:
   - Redirect URI: `https://photos.YOURDOMAIN/auth/login`
   - Click **Configure**
7. **Authentication tab → Add a platform → Mobile and desktop applications**:
   - Custom redirect URI: `https://photos-noauth.YOURDOMAIN/api/oauth/mobile-redirect`
   - Click **Configure**
8. **Authentication tab** — under **Advanced settings**, set **Allow public client flows** to **No**
9. **Certificates & secrets tab → New client secret**:
   - Description: `Immich`
   - Expiry: choose your preferred rotation period
   - Note the **Value** immediately — it is only shown once
10. Add all three values to `secret.sops.env`:
    ```sh
    sops services/immich/secret.sops.env
    ```
    Set:
    - `IMMICH_OAUTH_CLIENT_ID` — Application (client) ID from step 5
    - `IMMICH_OAUTH_CLIENT_SECRET` — Secret value from step 9
    - `IMMICH_OAUTH_ISSUER_URL` — `https://login.microsoftonline.com/TENANT_ID/v2.0` (substitute Directory (tenant) ID from step 5)

## First-Run Setup

1. Complete the [Entra ID App Registration](#entra-id-app-registration) above and populate `secret.sops.env`
2. Deploy the stack and confirm `immich-init` exits cleanly (no unresolved placeholder errors in its logs) before `immich-server` starts
3. Verify hardware transcoding is working by uploading a test video and checking the Jobs page in the admin panel
4. Test OAuth login via the **Login with Microsoft** button on the login page
5. Once OAuth is confirmed working, set `passwordLogin.enabled: false` in `config/immich.yaml` and redeploy

## Volumes

| Container Path                      | Host Path                                 | Mode | Purpose                                   |
| ----------------------------------- | ----------------------------------------- | ---- | ----------------------------------------- |
| `/usr/src/app/upload`               | `/mnt/archive-pool/private/photos/immich` | rw   | Originals (`library/`) + temp upload area |
| `/usr/src/app/upload/thumbs`        | `./data/thumbs`                           | rw   | Thumbnails overlay — vm-pool SSD          |
| `/usr/src/app/upload/encoded-video` | `./data/encoded-video`                    | rw   | Encoded video overlay — vm-pool SSD       |
| `/config/immich.yaml`               | `./data/immich.yaml`                      | ro   | Processed config file (from envsubst)     |
| `/cache`                            | `./data/model-cache`                      | rw   | ML model cache (vm-pool SSD)              |
| `/var/lib/postgresql`               | `./data/db`                               | rw   | Postgres database                         |
| `/backup`                           | `./backups/db-backup`                     | rw   | Nightly encrypted database backups        |

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time).
To add or change values, run `sops services/immich/secret.sops.env`.

| Variable                     | Purpose                                                                     |
| ---------------------------- | --------------------------------------------------------------------------- |
| `DOMAINNAME`                 | Base domain for Traefik routing rules and config file substitution          |
| `IMMICH_DB_PASSWORD`         | Postgres password for the `immich` user                                     |
| `IMMICH_REDIS_PASSWORD`      | Valkey (Redis) password                                                     |
| `DB_ENC_PASSPHRASE`          | Encryption passphrase for database backups                                  |
| `NOTIFICATIONS_EMAIL_*`      | SMTP settings for backup job email alerts                                   |
| `IMMICH_OAUTH_CLIENT_ID`     | Entra ID app registration client ID                                         |
| `IMMICH_OAUTH_CLIENT_SECRET` | Entra ID app registration client secret                                     |
| `IMMICH_OAUTH_ISSUER_URL`    | Entra ID OIDC issuer — `https://login.microsoftonline.com/<TENANT_ID>/v2.0` |
