# Infrastructure

This page covers host-level setup, identity allocation, storage configuration, and multi-server deployment — everything outside the Docker Compose files themselves. For compose patterns and container security rules, see [Architecture](ARCHITECTURE.md).

## Hardware (svlnas)

The primary TrueNAS server is a compact, passively-cooled build optimised for low noise and low power consumption.

| Category    | Qty | Component                       | Notes                              |
| ----------- | --- | ------------------------------- | ---------------------------------- |
| CPU         | 1   | Intel Core i3-9100              | 4C/4T, 65 W TDP, UHD Graphics 630  |
| Motherboard | 1   | Fujitsu D3644-B                 | LGA 1151, supports ECC UDIMMs      |
| Memory      | 2   | Kingston KSM26ED8/32MF (32 GB)  | DDR4-2666 ECC UDIMM — 64 GB total  |
| Boot SSD    | 1   | Crucial M4 128 GB               | SATA 2.5″ — TrueNAS OS boot drive  |
| Apps SSD    | 1   | Samsung 970 Evo Plus 2 TB       | NVMe M.2 — apps pool (vm-pool)     |
| Data HDDs   | 2   | Seagate IronWolf 4 TB           | CMR, 5900 RPM — ZFS mirror pool    |
| Case        | 1   | Fractal Design Core 1000        | Micro-ATX tower, USB 3.0 front I/O |
| CPU Cooler  | 1   | Arctic Alpine 12 Passive        | Fanless — zero noise from CPU      |
| Case Fan    | 1   | Noctua NF-A9 PWM (92 mm)        |                                    |
| Case Fan    | 1   | Scythe Slip Stream PWM (120 mm) |                                    |
| PSU         | 1   | Mini-box PicoPSU-160-XT         | DC-DC picoPSU — very low idle draw |
| Accessory   | 1   | Mini-box PCI Bracket            | Mounts picoPSU connector to case   |

## UID/GID Allocation

Every service runs under a dedicated non-root user with a unique UID. Each user has an auto-created primary group with the same GID (UID = GID). This ensures file ownership is unambiguous in `ls -la` and allows fine-grained access control via TrueNAS group membership.

### Naming Convention

TrueNAS service accounts follow the pattern `svc-app-<name>` (e.g., `svc-app-traefik`). This distinguishes them from human users and makes their purpose immediately clear in `ls -la` output.

### VM and Host Naming Convention

All servers and workstations follow a structured naming scheme:

```
<type><os>[az]<description>
```

| Segment         | Values          | Meaning                                          |
| --------------- | --------------- | ------------------------------------------------ |
| `<type>`        | `sv`            | Server                                           |
|                 | `ws`            | Workstation                                      |
| `<os>`          | `l`             | Linux                                            |
|                 | `w`             | Windows                                          |
| `[az]`          | `az` (optional) | Running in Azure; omit for on-premises           |
| `<description>` | short noun      | What the machine does (e.g. `nas`, `dev`, `ext`) |

**Examples:**

| Name       | Meaning                                       |
| ---------- | --------------------------------------------- |
| `svlnas`   | Server · Linux · NAS (the TrueNAS host)       |
| `svlazdev` | Server · Linux · Azure · development VM       |
| `svlazext` | Server · Linux · Azure · external-facing      |
| `wsldev`   | Workstation · Linux · development workstation |

### ID Ranges

| Range     | Purpose                                          |
| --------- | ------------------------------------------------ |
| 911       | Reserved for Plex (LinuxServer image default)    |
| 3100–3199 | Per-app service accounts (UID = GID)             |
| 3200+     | Shared purpose groups (no matching user account) |

Each service account has a matching `svc-app-<name>` group created at the same GID as its UID. These groups are **GID reservations only** — they exist to prevent TrueNAS from assigning the GID to an unrelated group in the future. The app's _functional_ primary group is typically a shared purpose group (e.g., `media` at GID 3200), not the `svc-app-*` placeholder. There is no need to add `truenas_admin` or other users to the `svc-app-*` groups.

### App Service Accounts

| UID/GID | TrueNAS user          | Service(s)                                  | Git-tracked config? |
| ------- | --------------------- | ------------------------------------------- | ------------------- |
| 3100    | `svc-app-traefik`     | traefik, traefik-init                       | Yes (`./config`)    |
| 3101    | `svc-app-adguard`     | adguard, adguard-init, adguard-unbound-init | No (`./data/conf`)  |
| 3102    | `svc-app-homepage`    | homepage, homepage-init                     | Yes (`./config`)    |
| 3103    | `svc-app-gatus`       | gatus, gatus-db-backup                      | No                  |
| 3104    | `svc-app-echo`        | echo-server                                 | No                  |
| 3105    | `svc-app-tfa`         | traefik-forward-auth, init                  | No (`./data`)       |
| 3106    | `svc-app-immich`      | immich-server, immich-ml, immich-init       | No                  |
| 3107    | `svc-app-metube`      | metube, metube-init                         | No                  |
| 3108    | `svc-app-unifi`       | unifi, unifi-db-backup                      | No                  |
| 3109    | `svc-app-dozzle`      | dozzle, dozzle-init                         | No                  |
| 3110    | `svc-app-radarr`      | radarr                                      | No                  |
| 3118    | `svc-app-tubesync`    | tubesync                                    | No                  |
| 3119    | `svc-app-drawio`      | drawio                                      | No                  |
| 3120    | `svc-app-outline`     | outline-db-backup†                          | No                  |
| 3121    | `svc-app-hadiscover`  | hadiscover-api, hadiscover-init             | No                  |
| 3122    | `svc-app-mosquitto`   | mosquitto, mosquitto-init                   | Yes (`./config`)    |
| 3123    | `svc-app-wmbusmeters` | wmbusmeters, wmbusmeters-init               | Yes (`./config`)    |
| 3124    | `svc-app-matter`      | matter-server, matter-server-init           | No                  |
| 3125    | `svc-app-prometheus`  | prometheus, prometheus-init                 | Yes (`./config`)    |

† The `outlinewiki/outline` image does not support PUID/PGID — it runs as the
image-internal `node` user (UID/GID 1000). UID 3120 is used only for the
db-backup sidecar. The Outline server itself runs without a `user:` directive;
an `outline-init` container pre-chowns `./data/data` to UID 1000 so the node
process can write to the bind-mount path. See:
https://github.com/outline/outline/discussions/9452

### Shared Purpose Groups

These groups have no matching user account. They grant cross-service access to shared datasets.

| GID  | Group               | Purpose                                      | Used as primary group by                                                                                                                                                       |
| ---- | ------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 3200 | `media`             | Read/write access to media datasets          | Plex (UID 911), MeTube (UID 3107), Radarr (UID 3110), Bazarr (UID 3111), Lidarr (UID 3112), qBittorrent (UID 3114), SABnzbd (UID 3115), Sonarr (UID 3116), TubeSync (UID 3118) |
| 3202 | `private-photos`    | Access to private photos (Immich upload dir) | Immich (UID 3106)                                                                                                                                                              |
| 3203 | `private-documents` | Access to private documents (reserved)       | —                                                                                                                                                                              |

### Plex Exception

Plex stays at UID 911 (LinuxServer image default) with PGID 3200 (`media`). The s6-overlay init system manages permissions internally. UID 911 is reserved exclusively for Plex — no other service may use it. For naming consistency, create a `svc-app-plex` user on TrueNAS with UID 911 and primary group `media` (GID 3200).

### TrueNAS Host Setup

**Important:** When creating service accounts in TrueNAS, always **create the group first**, then the user. If you rely on TrueNAS's "auto-create primary group" checkbox when creating a user, TrueNAS assigns the earliest available GID — which may not match the desired UID. By pre-creating the group with the correct GID, the auto-created primary group step is skipped and UID = GID is guaranteed.

Creation order for each app service account:

1. Create group `svc-app-<name>` with GID matching the UID (e.g., GID 3100) — this is a GID reservation to prevent conflicts
2. Create user `svc-app-<name>` with UID matching the GID (e.g., UID 3100), primary group set to the app's functional group (e.g., `media` for media apps, or the `svc-app-*` placeholder for apps that don't need shared access)
3. For apps with git-tracked config (`./config`): add `truenas_admin` to the app's functional primary group — this grants group-write access to chown'd config files, allowing `git pull` without permission conflicts

For shared purpose groups (`media`, `private-photos`, `private-documents`):

1. Create the groups with the designated GIDs (3200, 3202, 3203).
2. Configure the relevant service accounts' group memberships:
   - `svc-app-plex` (911): primary group `media` (3200)
   - `svc-app-metube` (3107): primary group `media` (3200)
   - `svc-app-immich` (3106): primary group `private-photos` (3202)
3. Add `truenas_admin` as an auxiliary group member of each group if admin access to those datasets is needed

### apps Dataset ACLs

The git repo lives on the `vm-pool/apps` dataset. Because `dccd.sh` decrypts `secret.sops.env` → `.env` files into this tree, access must be restricted to prevent other users from reading secrets.

Create the `vm-pool/apps` dataset via the TrueNAS GUI with these properties:

| Setting      | Value | Why                                                                                            |
| ------------ | ----- | ---------------------------------------------------------------------------------------------- |
| Compression  | `lz4` | Low CPU overhead; reduces snapshot size, replication transfer time, and Cloud Sync uploads     |
| Enable Atime | Off   | Prevents a write on every read; no benefit for app data workloads                              |
| ACL Type     | Off   | Plain Unix permissions; NFSv4 adds complexity with no benefit (same as `archive-pool/content`) |

Verify compression is active: `zfs get compression vm-pool/apps` should return `lz4`. For the `archive-pool/content` dataset, `zstd` is configured instead — see [Dataset Layout](#dataset-layout).

**Owner:** `truenas_admin` — allows `git pull` without sudo. Root does not need ownership because it bypasses all permission checks on Linux/ZFS.

**Owning group:** `truenas_admin`.

Configure the following Unix permissions on the `vm-pool/apps` dataset using the TrueNAS **Unix Permissions Editor**:

| Setting | Value                    |
| ------- | ------------------------ |
| User    | `truenas_admin`          |
| Group   | `truenas_admin`          |
| User    | Read ✓ Write ✓ Execute ✓ |
| Group   | Read ✓ Write ✓ Execute ✓ |
| Other   | No permissions           |

Enable both **Apply permissions recursively** and **Apply permissions to child datasets**. Child datasets are created as `root:root` regardless of the parent's permissions, so this must be done after all child datasets exist.

This gives `truenas_admin` full access while blocking all other users from reading decrypted `.env` files containing secrets. Root does not need explicit permissions — it bypasses all permission checks.

**Per-app config directories** are handled separately by init containers, not by dataset-level permissions:

1. Init containers chown `./config` subdirectories to the app's UID:GID with group-write (`775`/`664`)
2. `truenas_admin` (a member of each app's primary group) gets group-write access via POSIX group permissions
3. Next deploy, the init container re-chowns everything (idempotent)

## Media Access

> **Troubleshooting:** If a container cannot read or write media files, see [TROUBLESHOOTING.md § Permissions](TROUBLESHOOTING.md#permissions).

All services that interact with media datasets share a single `media` group (GID 3200). Every media-touching service account on TrueNAS has `media` as its primary group. Unix permissions replace NFSv4 ACLs on these datasets.

**Why not separate reader/writer groups?** Consumer services (e.g., Plex) are already restricted to read-only at the kernel level via `:ro` Docker volume mounts — a filesystem-level write restriction would only be a secondary layer for a modest risk. The same `media` group for all services keeps the model simple, debuggable with plain `ls -la`, and trivially extensible to SMB (add a user to the group, done).

Each media service (e.g., MeTube) runs under its own dedicated UID so file ownership is auditable — `ls -la` shows which service wrote a file.

### Dataset Layout

All media and download data lives under a **single** ZFS dataset `archive-pool/content`, mounted at `/mnt/archive-pool/content/`. No child datasets are created beneath it — everything is plain directories.

**Why one dataset?** Hardlinks only work within the same filesystem. When an arr app (Radarr, Sonarr) imports a finished download, it can create a hardlink from `downloads/` to `media/` instead of copying the file — but only if both paths are on the same ZFS dataset. Child datasets would act as separate filesystems and break this.

```
/mnt/archive-pool/content/
├── downloads/           ← download clients (arr stack)
│   ├── isos/
│   ├── torrents/        ← torrent client (qBittorrent, Deluge, etc.)
│   │   ├── movies/
│   │   ├── music/
│   │   └── tv/
│   └── usenet/          ← Usenet client (SABnzbd, NZBGet, etc.)
│       ├── incomplete/
│       └── complete/
│           ├── movies/
│           ├── music/
│           └── tv/
└── media/               ← final library; Plex reads this
    ├── audiobooks/
    ├── movies/
    ├── music/
    ├── study/
    ├── tv/
    └── youtube/
        └── metube/      ← MeTube writes here
```

All folder names are lowercase — Linux is case-sensitive and lowercase avoids ambiguity.

### TrueNAS Scale Setup

On the TrueNAS host, create or confirm:

- A `media` group (GID 3200) — for all media-touching services
- A `svc-app-plex` user (UID 911) with primary group `media` (GID 3200)
  - UID 911 is fixed by the LinuxServer image; it cannot be changed via `PUID`
  - **UID 911 is reserved exclusively for Plex.** No other service may use this UID unless strictly necessary, and any exception must be documented with a comment in the relevant compose file.
- A dedicated user per media service (e.g., `svc-app-metube` at UID 3107)
  - Primary group: `media` (GID 3200)
  - Use a distinct UID per tool so file ownership is unambiguous in `ls -la`
  - To add a new media service: create its user with primary group `media` — no dataset permission changes needed
- Add `truenas_admin` as an auxiliary group member of `media` for admin access

Create the `archive-pool/content` dataset via the TrueNAS GUI as a **Dataset** (not a zvol) with the following settings:

| Setting      | Value   | Why                                                                                       |
| ------------ | ------- | ----------------------------------------------------------------------------------------- |
| ACL Type     | Off     | Plain Unix permissions; NFSv4 adds complexity with no benefit                             |
| ACL Mode     | Discard | Ensures `chmod` works cleanly without ACL interference                                    |
| Compression  | `zstd`  | Free compression on metadata and small files; video/audio files are already compressed    |
| Enable Atime | Off     | Prevents a write on every read; useless for media workloads                               |
| Exec         | Off     | No binaries run from this path; init containers use their own image layer, not this mount |

Do **not** create child datasets beneath it — everything under `content/` must be plain directories on the same filesystem for hardlinks and atomic moves to work.

The `content-init` container (in the `_bootstrap` service) creates the full directory tree, sets group ownership to `media` (GID 3200), and applies the setgid bit (`2775`) on all directories on every deploy. The `_bootstrap` service deploys first because its directory name sorts before all other services alphabetically. No manual shell setup is needed after the dataset exists.

The **setgid bit** (`2775`) on every directory causes new files and subdirectories to inherit the `media` group automatically. `UMASK=002` in writing services ensures new files are created as `664` (group-readable).

### Container Configuration

All media-touching services hardcode GID 3200 (`media`). Consumer services mount paths `:ro`:

```yaml
environment:
  - PUID=911
  - PGID=3200 # media group — all media-touching services use this GID
volumes:
  - /mnt/archive-pool/content/media/movies:/media/movies:ro
```

Media-writing services omit `:ro` and set `UMASK=002` so created files are group-readable (`664`) and directories group-traversable (`775`):

```yaml
user: "3107:3200" # svc-app-metube:media
environment:
  - UMASK=002
volumes:
  - /mnt/archive-pool/content/media/youtube/metube:/downloads  # read-write; no :ro
```

Future arr apps (Radarr, Sonarr) must mount the entire `/mnt/archive-pool/content/` root so that `downloads/` and `media/` are on the same filesystem inside the container — this is what enables hardlinks and atomic moves:

```yaml
volumes:
  - /mnt/archive-pool/content:/data  # downloads/ and media/ both visible; hardlinks work
```

> **Plex exception:** The LinuxServer Plex image starts as root and drops to `PUID:PGID` via s6-overlay — `read_only: true` breaks this silently, so it is omitted. `user:` is also omitted for the same reason. Despite this, Plex ends up running as 911:3200 matching the dataset group ownership. **UID 911 is reserved for Plex** — no other service may use it unless strictly necessary, and any exception must be documented with a comment in the relevant compose file.

### Service Summary

| Service     | UID               | Primary group  | Media mount | UMASK |
| ----------- | ----------------- | -------------- | ----------- | ----- |
| Plex        | 911 (image-fixed) | 3200 (`media`) | `:ro`       | —     |
| MeTube      | 3107              | 3200 (`media`) | read-write  | `002` |
| Radarr      | 3110              | 3200 (`media`) | read-write  | `002` |
| Bazarr      | 3111              | 3200 (`media`) | read-write  | `002` |
| Lidarr      | 3112              | 3200 (`media`) | read-write  | `002` |
| qBittorrent | 3114              | 3200 (`media`) | read-write  | `002` |
| SABnzbd     | 3115              | 3200 (`media`) | read-write  | `002` |
| Sonarr      | 3116              | 3200 (`media`) | read-write  | `002` |
| TubeSync    | 3118              | 3200 (`media`) | read-write  | —     |

## Private Storage: Access Model

Private data (photos, documents) is intentionally separated from the shared media group hierarchy. Each category of private data gets its own dedicated group, ensuring services can only access the specific subdirectory they need — Immich cannot read a future documents directory, and a future documents service cannot read photos.

### Isolation Model

Access isolation is enforced at two layers:

1. **Parent dataset (`/mnt/archive-pool/private`):** Owned by `truenas_admin:truenas_admin` with Unix permissions 770 (no access for others). Same model as the `apps` dataset. This prevents any service account from traversing the parent path unless Docker mounts it directly — and Docker bind-mounts are resolved by the root daemon, so the container does not need host-path traversal rights.

2. **Subdirectory ownership via init containers:** Each service's init container chowns its specific subdirectory to the service's UID:GID. Because the parent dataset is root-inaccessible to service accounts, a service that doesn't have its path bind-mounted cannot reach sibling directories even if it somehow escapes its container.

### Per-Category Group Allocation

Each private data category has its own group. Services only receive the group for their specific category:

| GID  | Group               | Subdirectory                              | Service           |
| ---- | ------------------- | ----------------------------------------- | ----------------- |
| 3202 | `private-photos`    | `/mnt/archive-pool/private/photos/immich` | Immich (UID 3106) |
| 3203 | `private-documents` | `/mnt/archive-pool/private/documents/...` | Reserved          |

`truenas_admin` is added as an auxiliary group member of each group, granting admin access to each category's subdirectory after the init container sets ownership.

### TrueNAS Host Setup

On the TrueNAS host, create or confirm:

- A `private-photos` group (GID 3202), with `truenas_admin` as an auxiliary member
- A `svc-app-immich` user (UID 3106) with primary group `private-photos` (GID 3202)

On the parent private dataset (`/mnt/archive-pool/private`), using the TrueNAS **Unix Permissions Editor**:

| Setting | Value                    |
| ------- | ------------------------ |
| User    | `truenas_admin`          |
| Group   | `truenas_admin`          |
| User    | Read ✓ Write ✓ Execute ✓ |
| Group   | Read ✓ Write ✓ Execute ✓ |
| Other   | No permissions           |

No NFSv4 ACLs are needed on the parent dataset. Subdirectory permissions are managed entirely by init containers.

The init container chowns the service-specific subdirectory to the service UID:GID on every deploy. This is the single recovery point that restores access after any host-level permission reset.

### Container Configuration

Private-data containers hardcode the category-specific GID in `user:` directives and the init container:

```yaml
user: "3106:3202" # svc-app-immich:private-photos
```

### Adding a New Private-Data Service

1. Allocate the next GID from the `private-documents` row (3203+) in the Shared Purpose Groups table
2. Create the group on TrueNAS with that GID, add `truenas_admin` as auxiliary member
3. Create the service account user with its UID and the new group as primary
4. Add an init container that chowns the service's specific subdirectory under `/mnt/archive-pool/private/`
5. Bind-mount only that subdirectory into the container — never the parent `private/` path

## Multi-Server Deployment

This repository supports deploying apps to multiple servers beyond the primary TrueNAS host. Server-app mappings are defined in `servers.yaml` at the repo root.

### servers.yaml

The `servers.yaml` file maps servers to the apps they should deploy. Schema is validated by `servers.schema.json`.

```yaml
servers:
  svlazext:
    description: "Azure VM — DNS (AdGuard + Unbound), Cloudflare Tunnel, and public app backends"
    age_public_key: "age1..."
    apps:
      - adguard
      - cloudflared
      - hadiscover
      - traefik
      - traefik-forward-auth
```

**TrueNAS (svlnas)** uses TrueNAS mode (`-t`) which has its own app discovery, but is listed in `servers.yaml` for SOPS key scoping.

### Deploying to a Server

Use the `-S <server>` flag with `dccd.sh`:

```sh
# Deploy only apps assigned to svlazext
bash scripts/dccd.sh -d /opt/apps -S svlazext -k /opt/apps/age.key -x shared -f

# Cron job example (runs every 5 minutes)
*/5 * * * * bash /opt/apps/scripts/dccd.sh -d /opt/apps -S svlazext -k /opt/apps/age.key -x shared
```

The `-S` flag:

- Reads `servers.yaml` and resolves the app list for the named server
- Only decrypts `secret.sops.env` files for those apps (not all apps)
- Only deploys compose stacks for those apps
- Auto-detects server-specific compose overrides (`compose.<server>.yaml`)
- Is mutually exclusive with `-a` (single app filter) and `-t` (TrueNAS mode)
- Requires `yq` on `PATH`

### Compose Overrides

Some apps (notably Traefik) need different configurations per server. Server-specific compose override files use the naming convention:

```text
services/<app>/compose.<server>.yaml
```

When `dccd.sh -S <server>` detects a matching override file, it automatically applies it using Docker Compose's multi-file syntax (`-f compose.yaml -f compose.<server>.yaml`). Docker Compose's list-replacement semantics mean the override cleanly replaces sections like the network list.

**Example**: Traefik on svlnas joins 25+ app frontend networks, but Traefik on svlazext only needs `adguard-frontend`. The override at `services/traefik/compose.svlazext.yaml` replaces the network list and adjusts labels.

Shared config (traefik.yml, rules/, TLS options) is reused via the same volume mounts — no config duplication.

### Per-Server Age Keys

Each server has its own Age keypair for SOPS decryption. The `.sops.yaml` creation_rules scope which servers can decrypt which app secrets:

```yaml
creation_rules:
  # adguard runs on svlnas + svlazext
  - path_regex: services/adguard/secret\.sops\.env$
    age: "deploy_key,svlnas_key,svlazext_key"
  # cloudflared runs on svlnas + svlazext
  - path_regex: services/cloudflared/secret\.sops\.env$
    age: "deploy_key,svlnas_key,svlazext_key"
  # traefik runs on svlnas + svlazext
  - path_regex: services/traefik/secret\.sops\.env$
    age: "deploy_key,svlnas_key,svlazext_key"
  # fallback: new apps default to deploy + svlnas
  - path_regex: secret\.sops\.env$
    age: "deploy_key,svlnas_key"
```

**Key roles**:

- **Deploy key**: Lives on your dev machine. Can decrypt everything. Used for `sops -e` / `sops -d` during development.
- **Server keys**: Each server stores only its own private key at `age.key`. It can only decrypt secrets for apps assigned to it.

Generate rules from `servers.yaml` using:

```sh
bash scripts/generate-sops-rules.sh -d /path/to/repo
```

The script reads the deploy key from `age.key` (the `# public key:` comment) and all server keys from `servers.yaml`. Servers without an `apps` list are treated as all-access.

After updating rules, re-encrypt all files: `sops updatekeys services/<app>/secret.sops.env` for each app.

### Ansible Integration

Each remote server (Azure VMs) is managed by Ansible-pull which:

1. Clones this repository to the configured directory (e.g., `/opt/apps`)
2. Installs `yq` (required for server mode)
3. Places the server's Age private key at `<base_dir>/age.key`
4. Sets up a cron job running `dccd.sh -S <server>` at the desired interval

## Retiring an App

Retirement is the inverse of adding an app. Use the skill at `.github/skills/retire-docker-app/SKILL.md` for the full checklist — it covers removing compose files, Traefik networks/middleware, DNS records, documentation entries, and post-merge host cleanup.

Key mechanisms:

- **`dccd-down <app>`** (or `dccd.sh -R <app>`): Server-aware teardown that applies compose overrides and uses the correct project name for each deployment mode.
- **Auto-cleanup**: When `dccd.sh` pulls new commits that remove a service directory, it automatically detects the orphaned compose project and tears it down — no manual intervention needed on any server.
- **Retired services log**: Add an entry to `docs/RETIRED-SERVICES.md` with the retirement date, reason, and the last active commit hash so the old configuration is easy to find.
