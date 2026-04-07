# Immich

Immich is a self-hosted photo and video management solution with mobile backup, facial recognition, and smart search.

## Access

| URL                                  | Description                                                                           |
| ------------------------------------ | ------------------------------------------------------------------------------------- |
| `https://photos.<DOMAINNAME>`        | Web UI (Traefik forward-auth + Immich OAuth)                                          |
| `https://photos-mobile.<DOMAINNAME>` | Mobile app endpoint (no Traefik forward-auth — Immich handles its own authentication) |

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

- **`oauth`**: Microsoft Entra ID OIDC login — credentials from `secret.sops.env`; `autoLaunch` skips
  the login page; `roleClaim: roles` maps Entra App Roles to Immich admin/user at account creation;
  `mobileRedirectUri` points to `photos-mobile` so the OAuth callback relay bypasses forward-auth
- **`passwordLogin`**: Disabled — Entra OAuth is the only login method
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

1. **Chowns all writable paths** to `3106:3202` — recovers from any host-level permission reset on every deploy
2. **Runs `config/envsubst.sh`** — substitutes `${VAR}` placeholders in `config/immich.yaml` and writes the result to `data/immich.yaml`

`DAC_OVERRIDE` is required because the originals path is owned by `truenas_admin:truenas_admin 770` — UID 0 inside the container has no permissions to traverse it without this cap. It also allows overwriting the existing `data/immich.yaml` on redeployments.

`CHOWN` is required to transfer ownership to `3106:3202`.

The GID `3202` is hardcoded in the `command:` block because `env_file` values are injected into the container environment and do not feed into Docker Compose variable substitution for `user:` and `command:` fields.

### Database

The `immich-db` image is a custom Postgres build from the Immich project that bundles the `pgvecto.rs` and `vectorchord` extensions required for ML-powered search. Standard `pgautoupgrade` images do not include these extensions, so **automated Postgres major version upgrades are not used here**. See [DATABASE-UPGRADES.md](../../docs/DATABASE-UPGRADES.md) and the [Immich Postgres upgrade docs](https://immich.app/docs/administration/postgres-upgrade) before performing any major version upgrade.

### Database Backup

`immich-db-backup` uses [tiredofit/db-backup](https://github.com/tiredofit/docker-db-backup) in `MODE=MANUAL` with `MANUAL_RUN_FOREVER=FALSE` — it runs one backup and exits cleanly. The nightly CD script (`dccd.sh`) restarts it each run. Backups are ZSTD-compressed, SHA1-checksummed, AES-encrypted with `DB_ENC_PASSPHRASE`, and retained for 48 hours.

## Storage Layout

All Immich media is stored under a single bind-mount on archive-pool. Immich creates its subdirectory
layout (`library/`, `thumbs/`, `encoded-video/`, etc.) automatically within that tree.

| What              | Host Path                                 | Pool         | Backed up?                    |
| ----------------- | ----------------------------------------- | ------------ | ----------------------------- |
| All media         | `/mnt/archive-pool/private/photos/immich` | archive-pool | ✅ ZFS snapshots              |
| ML model cache    | `./data/model-cache`                      | vm-pool SSD  | ❌ Regeneratable              |
| Postgres database | `./data/db`                               | vm-pool SSD  | ✅ `immich-db-backup` sidecar |

Thumbnails and encoded video are regeneratable but stored on archive-pool alongside the originals.
This avoids cross-pool Docker nested bind mounts, which are unreliable on TrueNAS/ZFS due to mount
propagation constraints. The ML model cache and database are on vm-pool SSD as they are small,
frequently accessed, and never need snapshotting.

The `private-photos` group (GID 3202) on the originals path means any future tool (e.g. PhotoPrism)
can be granted read access by joining that group — no ownership restructuring needed.

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
   - Redirect URI 1: `https://photos.YOURDOMAIN/auth/login`
   - Redirect URI 2: `https://photos.YOURDOMAIN/user-settings` (for manually linking OAuth in the web UI)
   - Redirect URI 3: `https://photos-mobile.YOURDOMAIN/api/oauth/mobile-redirect` (OAuth callback relay for the mobile app)
   - Click **Configure**

   > **Important**: All three URIs must be under the **Web** platform. The mobile relay is a
   > server-side endpoint — Immich exchanges the code using its `client_secret`. Registering it
   > under "Mobile and desktop applications" enables public client mode and causes Entra to reject
   > the `client_secret` with `AADSTS700025`.

7. **Authentication tab** — under **Advanced settings**, set **Allow public client flows** to **No**
8. **Certificates & secrets tab → New client secret**:
   - Description: `Immich`
   - Expiry: choose your preferred rotation period
   - Note the **Value** immediately — it is only shown once
9. Add all three values to `secret.sops.env`:
   ```sh
   sops services/immich/secret.sops.env
   ```
   Set:
   - `IMMICH_OAUTH_CLIENT_ID` — Application (client) ID from step 5
   - `IMMICH_OAUTH_CLIENT_SECRET` — Secret value from step 8
   - `IMMICH_OAUTH_ISSUER_URL` — `https://login.microsoftonline.com/TENANT_ID/v2.0` (substitute Directory (tenant) ID from step 5)

### App Roles (admin/user assignment)

Immich's `roleClaim` feature does not work with Entra ID: Entra emits app roles as a JSON
array (e.g. `["admin"]`), but Immich's claim validator requires a scalar string. The check
silently fails and the account is created as a regular user regardless of the assigned role.

Admin access is assigned in two ways instead:

- **First user**: The onboarding wizard (first boot) automatically creates an admin account
- **Subsequent admins**: Go to **Administration → Users → Edit user → toggle Admin** in the Immich web UI

No App Roles configuration in Entra is needed or useful.

## First-Run Setup

1. Complete the [Entra ID App Registration](#entra-id-app-registration) above and populate `secret.sops.env`
2. Deploy the stack and confirm `immich-init` exits cleanly (no unresolved placeholder errors in its logs) before `immich-server` starts
3. Navigate to `https://photos.<DOMAINNAME>` — you will be presented with an **onboarding wizard** asking
   for Admin Email, Password, and Name. This is Immich's hardcoded first-boot flow that fires when there
   are zero users in the database. It runs before `autoLaunch` applies and cannot be bypassed via config.
   - Enter your **real email address** (must match what Entra returns as the `email` claim in your OAuth token)
   - Set any password — it will be immediately unusable for login since `passwordLogin: false` is set in `config/immich.yaml`
4. After completing the wizard, all subsequent visits will trigger the `autoLaunch` OAuth redirect to Microsoft
5. Log in via OAuth — Immich links the OAuth identity to the admin account by matching the email claim
6. Verify hardware transcoding is working by uploading a test video and checking the Jobs page in the admin panel

## Volumes

| Container Path        | Host Path                                 | Mode | Purpose                                    |
| --------------------- | ----------------------------------------- | ---- | ------------------------------------------ |
| `/usr/src/app/upload` | `/mnt/archive-pool/private/photos/immich` | rw   | All media (library, thumbs, encoded video) |
| `/config/immich.yaml` | `./data/immich.yaml`                      | ro   | Processed config file (from envsubst)      |
| `/cache`              | `./data/model-cache`                      | rw   | ML model cache (vm-pool SSD)               |
| `/var/lib/postgresql` | `./data/db`                               | rw   | Postgres database                          |
| `/backup`             | `./backups/db-backup`                     | rw   | Nightly encrypted database backups         |

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
