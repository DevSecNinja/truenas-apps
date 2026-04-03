# Architecture

## Compose File Standards

Every service in this repo follows these conventions:

```yaml
services:
  example:
    image: registry/image:tag@sha256:...   # Always pin to digest
    container_name: example                # Explicit name for predictable references
    env_file:
      - .env                               # SOPS-decrypted secrets
      - ../shared/env/tz.env               # Shared timezone
    user: "3100:3100"                     # Hardcoded UID:GID (see § UID/GID Allocation)
    restart: always                        # Auto-recover on failure
    networks:
      - <service>-frontend                 # Traefik-facing network
    mem_limit: ${MEM_LIMIT:-<default>}     # Prevent runaway memory
    pids_limit: 100                        # Prevent fork-bomb DoS
    security_opt:
      - no-new-privileges=true             # Block privilege escalation
    cap_drop:
      - ALL                                # Drop every capability …
    # cap_add:                            # … re-add only what is provably needed
    #   - NET_BIND_SERVICE
    read_only: true                        # Immutable root filesystem
    tmpfs:
      - /tmp                               # Writable scratch space
    healthcheck:                           # Required for --wait deploys
      test: [...]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s
    labels:
      - "traefik.enable=true"              # Opt-in to Traefik discovery
      - "traefik.http.routers...middlewares=chain-auth@file"
```

**Key rules:**

- Images must always include an explicit registry prefix (e.g. `docker.io/library/busybox`, `ghcr.io/gethomepage/homepage`). Bare image names like `busybox` or `user/image` are not allowed — Docker's implicit `docker.io` default is not reliable across runtimes and Renovate cannot enforce the correct registry without it
- Images are digest-pinned (`@sha256:...`) — Renovate manages updates via PRs
- `read_only: true` with `tmpfs` mounts for writable paths
- `no-new-privileges` on every container, no exceptions
- `cap_drop: ALL` on every container — this is a hard security requirement. If a container needs a specific capability, declare `cap_add` with only the minimum required capability and add a comment on the container in the compose file explaining why the exception is necessary
- Memory limits with env-var overrides for per-environment tuning
- `pids_limit` on every container to prevent fork-bomb DoS
- Health checks are mandatory — `dccd.sh` uses `docker compose up --wait`
- Volumes mounted `:ro` wherever the container only reads

## Volume Permissions: Init Container Pattern

Named Docker volumes and bind-mounted directories are created as `root:root` by Docker. A container with a hardcoded non-root `user:` and `cap_drop: ALL` has no `CAP_CHOWN` and cannot fix this at runtime — it will fail to write on first deploy.

**Rule:** Any service with both of the following requires a `<app>-init` container:

1. `user: "<UID>:<GID>"` (explicit non-root)
2. At least one writable volume (named volume or bind mount)

The init container runs as root, chowns the volume paths to the service's UID:GID, and exits before the main container starts. The main service declares `depends_on: <app>-init: condition: service_completed_successfully`.

**Bind-mount directories (`./config`, `./data`, `./backup`) must always be included in the init container's chown command**, even when the main container mounts a path inside them as `:ro`. A host-level `chown` (e.g. a TrueNAS dataset permission reset) can make those directories unreadable or untraversable. The init container is the single recovery point that restores ownership on every deploy.

**Git-tracked config directories** (`./config`) must be set to group-write permissions (`775` for directories, `664` for files) by the init container. This allows `truenas_admin` (who is a member of each app's primary group) to run `git pull` without permission conflicts. The init container restores both ownership and permissions on every deploy, so manual permission fixes are never needed.

```yaml
# Pattern — copy this block, adjust container_name, UID:GID, command paths, and volumes
<app>-init:
  image: docker.io/library/busybox:1.37.0@sha256:1487d0af5f52b4ba31c7e465126ee2123fe3f2305d638e7827681e7cf6c83d5e
  container_name: <app>-init
  env_file:
    - path: .env          # Decrypted from secret.sops.env
      required: false
  restart: "no"
  network_mode: none
  mem_limit: 64m
  pids_limit: 50
  security_opt:
    - no-new-privileges=true
  cap_drop:
    - ALL
  cap_add:
    - CHOWN    # Required to chown volume paths
    - FOWNER   # Required to chmod after ownership transfer
    - DAC_OVERRIDE # Required to traverse previously-chowned directories
  read_only: true
  command:
    - "sh"
    - "-c"
    - |-
      chown -R <UID>:<GID> /path/a /path/b &&
      find /path/b -type d -exec chmod 775 {} + &&
      find /path/b -type f -exec chmod 664 {} +
  volumes:
    - <app>-volume:/path/a
    - ./config:/path/b     # git-tracked config — group-write for truenas_admin
```

For services that only chown runtime-only paths (named volumes, `./data/`), the `chmod 775/664` step and `FOWNER`/`DAC_OVERRIDE` capabilities can be omitted — only `CHOWN` is needed.

**Exceptions — images that manage their own permissions:**

- **s6-overlay images** (LinuxServer, tiredofit/db-backup) start as root and chown their own directories during their own init phase. They do not need an external init container.
- **Database images** (postgres, MongoDB) initialise their own data directories. They do not need an external init container.

**Services using this pattern:**

| Service              | Init container              | Volumes chown'd                                                 |
| -------------------- | --------------------------- | --------------------------------------------------------------- |
| adguard              | `adguard-init`              | `adguard-data`, `./data/conf`                                   |
| homepage             | `homepage-init`             | `./config`                                                      |
| metube               | `metube-init`               | `metube-state`                                                  |
| traefik              | `traefik-init`              | `traefik-acme`, `./config`                                      |
| traefik-forward-auth | `traefik-forward-auth-init` | `./data`                                                        |
| immich               | `immich-init`               | `/mnt/archive-pool/private/photos/immich`, `immich-model-cache` |

---

**Exceptions — s6-overlay and root-start containers:**

Some images cannot use `read_only: true` or `user:` because their init system (s6-overlay) requires a writable root filesystem and starts as root before dropping privileges internally. `cap_drop: ALL` is **still required** for these images — only the specific capabilities that s6-overlay needs are re-added via `cap_add`. Each such container must include a comment block in the compose file explaining the deviation. This applies to:

- **LinuxServer images** (e.g., `unifi-network-application`, `plex`) — use `PUID`/`PGID` environment variables for internal privilege dropping; omit `user:` and `read_only`. Add back `CHOWN`, `SETUID`, `SETGID`, and `SETPCAP` via `cap_add`.
- **tiredofit/db-backup** — uses `USER_DBBACKUP`/`GROUP_DBBACKUP` for internal privilege dropping; omit `user:` and `read_only`.
- **mvance/unbound** — starts as root and drops privileges to the `_unbound` user internally; its startup script generates `unbound.conf` and creates subdirectories at runtime, so omit `user:` and `read_only`.

Each exception is documented with a comment block in the compose file explaining why the deviation is necessary.

**Minimum `cap_add` for LinuxServer/s6-overlay images:**

| Capability | Why it is needed                                                                     |
| ---------- | ------------------------------------------------------------------------------------ |
| `CHOWN`    | s6-overlay chowns mounted volumes (e.g., `/config`) to `PUID:PGID` at startup        |
| `SETUID`   | s6-overlay calls `setuid()` to drop from root to `PUID`                              |
| `SETGID`   | s6-overlay calls `setgid()` to drop from root to `PGID`                              |
| `SETPCAP`  | s6-overlay clears the bounding capability set before exec-ing the application daemon |

All other default Docker capabilities (`NET_RAW`, `NET_BIND_SERVICE`, `MKNOD`, `AUDIT_WRITE`, `SYS_CHROOT`, `FSETID`, `FOWNER`, `DAC_OVERRIDE`, `KILL`) are dropped and not needed.

**Pitfalls specific to s6-overlay images:**

- **`read_only: true` silently breaks `PUID`/`PGID`.** s6-overlay writes the UID/GID entries to `/etc/passwd` and `/etc/group` during startup before dropping privileges. With `read_only: true` those writes fail silently and the container continues running as the image default (UID 911 for LinuxServer Plex), ignoring `PUID`/`PGID` entirely. Always omit `read_only` for s6-overlay images when working with subprcesses in the container such as Plex that need access to volumes.

- **`group_add` does not grant supplementary groups to the application process.** `group_add` adds GIDs to the credentials of PID 1 (s6-overlay, which runs as root). When s6-overlay drops privileges to run the application it re-initialises the process's supplementary groups from `/etc/group` inside the container — where the host-only GID does not exist. The result is that the application process has no membership in the added group. To grant an s6-overlay image membership in a host GID, set that GID as `PGID` (primary group) or ensure the image's own group-setup mechanism adds it. The correct approach for LinuxServer images is to set the desired GID via the `PGID` env var; s6-overlay will then create the `/etc/group` entry and the application process will run with that GID.

## Config Template Substitution: Envsubst Init Containers

Some services need secrets or environment-specific values (domain names, API keys) injected into their configuration files at deploy time. Since these config files are committed to Git as templates with `${VAR}` placeholders, a separate init container processes them before the main service starts.

**Pattern:** An `<app>-init` container mounts `./config` as `/templates:ro`, runs `envsubst.sh` to replace `${VAR}` placeholders with values from `secret.sops.env`, and writes the processed output to `./data/`. The main container then mounts the processed file from `data/` as `:ro`.

This keeps secrets out of Git (the template only contains placeholder names) while the processed config with real values lives in `data/` which is gitignored.

**Services using this pattern:**

| Service              | Init container              | Template → Output                               |
| -------------------- | --------------------------- | ----------------------------------------------- |
| adguard (unbound)    | `adguard-unbound-init`      | `config/unbound/*.conf` → `data/unbound/*.conf` |
| traefik-forward-auth | `traefik-forward-auth-init` | `config/config.yaml` → `data/config.yaml`       |

## Networking: Per-Service Isolation

Each service gets its own frontend network (e.g., `echo-server-frontend`, `homepage-frontend`). Traefik joins each frontend network individually.

**Why not a single shared `traefik-public` network?**

Network-level isolation. With per-service networks, containers cannot communicate with each other — only with Traefik. A shared network would let any compromised container reach every other service. The trade-off is that adding a new service requires adding its network to Traefik's compose file.

Services that need Docker API access get a dedicated **internal** backend network with a socket proxy (e.g., `homepage-backend`). The same pattern applies to databases and other backing services — they sit on an internal backend network with `internal: true`, preventing external routing and ensuring only the application container can reach them.

## Docker Socket Proxy

Services never mount `/var/run/docker.sock` directly. Instead, each gets its own [LinuxServer socket-proxy](https://github.com/linuxserver/docker-socket-proxy) instance with minimal permissions:

- `CONTAINERS=1` — read container metadata only
- `POST=0` — read-only, no mutations (Homepage)
- Separate proxy per service to prevent lateral movement

**Why one proxy per service instead of sharing?**

If Traefik and Homepage shared one proxy, compromising either would grant the attacker the union of both permission sets. Separate proxies enforce least privilege per consumer.

## Directory Conventions

Each service follows a consistent layout:

```text
src/<service>/
  compose.yaml       # Service definition — committed to Git
  secret.sops.env    # SOPS-encrypted secrets — committed to Git
  config/            # Static configuration — committed to Git
  data/              # Runtime data — NOT committed to Git
  backups/           # Backup output — NOT committed to Git
```

**`compose.yaml`** defines the service: images, networks, volumes, labels, and resource limits. It is the source of truth for how the service runs and is always committed to Git.

**`secret.sops.env`** stores secrets (API keys, passwords, tokens) encrypted with SOPS + Age. Because the values are encrypted, the file is safe to commit to Git. At deploy time, the CD script decrypts it to `.env` which is excluded from Git.

**`config/`** holds files that you author and version-control: configuration files, rule sets, and any other inputs the container reads at startup. For example, Traefik's `config/` contains `traefik.yml` and the dynamic rules under `rules/`. These are mounted `:ro` into the container because the container should only read them, never write to them.

**`data/`** holds files that are produced or mutated by the running container: databases, certificates, caches, state files, and other dynamic output. This directory lives only on the host machine and is excluded from Git via `.gitignore`. It is mounted read-write so the container can persist its runtime state across restarts.

**`backups/`** holds database backup files produced by the backup sidecar container (e.g., `tiredofit/db-backup`). Like `data/`, this directory is excluded from Git and mounted read-write. Each backup type gets its own subdirectory (e.g., `backups/db-backup/`).

## Secret Management

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [Age](https://github.com/FiloSottile/age) and stored in git as `secret.sops.env`. The CD script decrypts them to `.env` at deploy time using an Age key stored on the TrueNAS host.

`PUID` and `PGID` are hardcoded directly in each service's `compose.yaml` so they are visible, auditable, and self-documenting. See § UID/GID Allocation.

## UID/GID Allocation

Every service runs under a dedicated non-root user with a unique UID. Each user has an auto-created primary group with the same GID (UID = GID). This ensures file ownership is unambiguous in `ls -la` and allows fine-grained access control via TrueNAS group membership.

### Naming Convention

TrueNAS service accounts follow the pattern `svc-app-<name>` (e.g., `svc-app-traefik`). This distinguishes them from human users and makes their purpose immediately clear in `ls -la` output.

### ID Ranges

| Range     | Purpose                                          |
| --------- | ------------------------------------------------ |
| 911       | Reserved for Plex (LinuxServer image default)    |
| 3100–3199 | Per-app service accounts (UID = GID)             |
| 3200+     | Shared purpose groups (no matching user account) |

### App Service Accounts

| UID/GID | TrueNAS user       | Service(s)                                  | Git-tracked config? |
| ------- | ------------------ | ------------------------------------------- | ------------------- |
| 3100    | `svc-app-traefik`  | traefik, traefik-init                       | Yes (`./config`)    |
| 3101    | `svc-app-adguard`  | adguard, adguard-init, adguard-unbound-init | No (`./data/conf`)  |
| 3102    | `svc-app-homepage` | homepage, homepage-init                     | Yes (`./config`)    |
| 3103    | `svc-app-gatus`    | gatus, gatus-db-backup                      | No                  |
| 3104    | `svc-app-echo`     | echo-server                                 | No                  |
| 3105    | `svc-app-tfa`      | traefik-forward-auth, init                  | No (`./data`)       |
| 3106    | `svc-app-immich`   | immich-server, immich-ml, immich-init       | No                  |
| 3107    | `svc-app-metube`   | metube, metube-init                         | No                  |
| 3108    | `svc-app-unifi`    | unifi, unifi-db-backup                      | No                  |

### Shared Purpose Groups

These groups have no matching user account. They grant cross-service access to shared datasets.

| GID  | Group           | Purpose                            | Used as primary group by |
| ---- | --------------- | ---------------------------------- | ------------------------ |
| 3200 | `media-readers` | Read access to media datasets      | Plex (UID 911)           |
| 3201 | `media-writers` | Write access to media/download dir | MeTube (UID 3107)        |
| 3202 | `private`       | Access to private datasets         | Immich (UID 3106)        |

### Plex Exception

Plex stays at UID 911 (LinuxServer image default) with PGID 3200 (`media-readers`). The s6-overlay init system manages permissions internally. UID 911 is reserved exclusively for Plex — no other service may use it. For naming consistency, create a `svc-app-plex` user on TrueNAS with UID 911 and primary group `media-readers` (GID 3200).

### TrueNAS Host Setup

**Important:** When creating service accounts in TrueNAS, always **create the group first**, then the user. If you rely on TrueNAS's "auto-create primary group" checkbox when creating a user, TrueNAS assigns the earliest available GID — which may not match the desired UID. By pre-creating the group with the correct GID, the auto-created primary group step is skipped and UID = GID is guaranteed.

Creation order for each app service account:

1. Create group `svc-app-<name>` with GID matching the UID (e.g., GID 3100)
2. Create user `svc-app-<name>` with UID matching the GID (e.g., UID 3100), primary group set to the group from step 1
3. Add `truenas_admin` to the group — this grants group-write access to chown'd config files, allowing `git pull` without permission conflicts

For shared purpose groups (`media-readers`, `media-writers`, `private`):

1. Create the group with the designated GID (3200, 3201, 3202)
2. Configure the relevant service accounts' group memberships:
   - `svc-app-plex` (911): primary group `media-readers` (3200)
   - `svc-app-metube` (3107): primary group `media-writers` (3201), auxiliary group `media-readers` (3200)
   - `svc-app-immich` (3106): primary group `private` (3202)
3. Add `truenas_admin` as an auxiliary group member of each group if admin access to those datasets is needed

### Apps Dataset ACLs

The git repo lives on the `vm-pool/Apps` dataset. Because `dccd.sh` decrypts `secret.sops.env` → `.env` files into this tree, access must be restricted to prevent other users from reading secrets.

**Owner:** `truenas_admin` — allows `git pull` without sudo. Root does not need ownership because it bypasses all permission checks on Linux/ZFS.

**Owning group:** `truenas_admin` (or `root` — irrelevant since access is controlled via named ACL entries, not `group@`).

Configure the following NFSv4 ACL entries on the `vm-pool/Apps` dataset:

| Entry                      | Permission     | File Inherit | Directory Inherit |
| -------------------------- | -------------- | ------------ | ----------------- |
| `owner@` (`truenas_admin`) | Full Control   | ✓            | ✓                 |
| `everyone@`                | No permissions | —            | —                 |

- **`owner@`**: `truenas_admin` can git pull, edit configs, and administer the repo interactively.
- **`everyone@`**: No permissions — blocks all other users from reading decrypted `.env` files containing secrets. Remove or deny any default `everyone@` read entry.
- **Root** does not need an explicit ACL entry — it bypasses all permission checks.

Apply recursively and to child datasets.

**Per-app config directories** are handled separately by init containers, not by dataset-level ACLs:

1. Init containers chown `./config` subdirectories to the app's UID:GID with group-write (`775`/`664`)
2. `truenas_admin` (a member of each app's primary group) gets group-write access via POSIX group permissions
3. Next deploy, the init container re-chowns everything (idempotent)

## Shared Environment Files

Reusable env files live in `src/shared/env/` and are referenced via relative paths in `env_file` blocks. They are committed to Git because they contain no secrets.

| File     | Purpose                    | When to include |
| -------- | -------------------------- | --------------- |
| `tz.env` | Sets `TZ=Europe/Amsterdam` | Every container |

UID and GID values are **not** stored in shared env files or in `secret.sops.env`. They are hardcoded directly in each service's `compose.yaml` (in the `user:` directive and init container commands) so they are visible, auditable, and not treated as secrets. See § UID/GID Allocation for the full allocation table.

## Media Access: Consumer/Producer Model

Services that interact with media datasets are divided into two roles:

**Consumers** (e.g., Plex) only read media files. All media bind-mounts carry `:ro`, enforcing this at the kernel level regardless of filesystem permissions. Consumers run with the shared `media-readers` group (GID 3200) so that dataset ACLs grant them read access.

**Producers** (e.g., download clients) write new media files. Each producer runs under its own dedicated UID so file ownership is auditable — `ls -la` shows which service created a file. All producers share the `media-writers` group (GID 3201) as their primary group, so dataset write access is controlled by a single ACL entry per dataset. Adding a new producer tool only requires joining it to the group on TrueNAS — no dataset ACL edits needed.

Producers are also members of the `media-readers` group (as an auxiliary group on the user) on the TrueNAS host. This is set at the OS level and applies at the filesystem layer regardless of what the container knows about its groups — so consumers can read whatever a producer writes without any additional configuration.

### TrueNAS Scale Setup

On the TrueNAS host, create or confirm:

- A `media-readers` group (GID 3200) — for all consumers
- A `media-writers` group (GID 3201) — for all producers
- A `svc-app-plex` user (UID 911) with primary group `media-readers`
  - UID 911 is fixed by the LinuxServer image when `read_only: true`; it cannot be changed via `PUID`
  - **UID 911 is reserved exclusively for Plex.** No other service may use this UID unless strictly necessary, and any exception must be documented with a comment in the relevant compose file explaining why.
- A dedicated user per producer (e.g., `svc-app-metube` at UID 3107)
  - Primary group: `media-writers` (controls write access via ACL)
  - Auxiliary group: `media-readers` (ensures consumers can read files the producer writes)
  - Use a distinct UID per producer tool so file ownership is unambiguous in `ls -la`
  - To add a new producer tool: create its user, set primary group to `media-writers`, add `media-readers` as an auxiliary group — no dataset ACL changes needed

On each media dataset under `/mnt/archive-pool/Media/`:

1. Set the owning group to `media-writers` and enable **Apply Group**
2. Configure NFSv4 ACLs (TrueNAS Scale default on ZFS datasets) using Basic presets:
   - `owner@`: **Full Control** — dataset owner (root)
   - `group@` (= `media-writers`, GID 3201): **Modify** — all producers; because `media-writers` is the owning group, `group@` covers it — no separate named ACL entry needed
   - Named entry for `media-readers` group (GID 3200): **Read** — all consumers, including Plex
3. Enable ACL inheritance on both the `group@` and the named `media-readers` group ACL entries. In the TrueNAS dataset ACL editor, edit each entry and enable **File Inherit** and **Directory Inherit**. This ensures new files and subdirectories created inside the dataset automatically receive the correct ACL entries.
4. Select **Apply permissions recursively** and **Apply permissions to child datasets** when appropriate.

### Container Configuration

**Consumers** hardcode the media GID in their `user:` directive or `PGID` environment variable. Mount all media paths `:ro`:

```yaml
environment:
  - PUID=911
  - PGID=3200 # media-readers group — consumers read media datasets via this GID
volumes:
  - /mnt/archive-pool/Media/Movies:/media/movies:ro
```

**Producers** hardcode the media-writers GID. Set `UMASK=002` so created files are group-writable (`664`) and directories group-traversable (`775`). The supplementary `media-readers` group membership is configured on the TrueNAS host at the OS level — no container-side config needed for consumers to read produced files:

```yaml
user: "3107:3201" # svc-app-metube:media-writers
environment:
  - UMASK=002
volumes:
  - /mnt/archive-pool/Media/Movies:/media/movies  # read-write; no :ro
```

> **Plex exception:** The LinuxServer Plex image forces UID/GID 911:911 internally when `read_only: true`, so `PUID`/`PGID` env vars have no effect. The host-level ACL entry for `svc-app-plex` (UID 911) on each media dataset handles access instead. **UID 911 is reserved for Plex** — no other service may use it unless strictly necessary, and any exception must be documented with a comment in the relevant compose file.

### Role Summary

| Role     | Example service | UID                | Primary group            | Auxiliary group         | Media mount | UMASK |
| -------- | --------------- | ------------------ | ------------------------ | ----------------------- | ----------- | ----- |
| Role     | Example service | UID                | Primary group            | Auxiliary group         | Media mount | UMASK |
| -------- | --------------- | ------------------ | ------------------------ | ----------------------- | ----------- | ----- |
| Consumer | Plex            | 911 (image-fixed)  | 3200 (`media-readers`)   | —                       | `:ro`       | —     |
| Producer | MeTube          | 3107               | 3201 (`media-writers`)   | 3200 (`media-readers`)  | read-write  | `002` |

## Private Storage: Access Model

Private data (photos, documents) is intentionally separated from the shared media group hierarchy. Containers that access private datasets use a dedicated `private` group (GID 3202) rather than the `media-readers` or `media-writers` groups, ensuring media consumers like Plex cannot access personal data.

### TrueNAS Host Setup

On the TrueNAS host, create or confirm:

- A `private` group (GID 3202)
- A dedicated user per private-data service (e.g., `svc-app-immich` at UID 3106) with primary group `private` (GID 3202)

On the private dataset (`/mnt/archive-pool/private`):

1. Set the owning group to `private` and enable **Apply Group**
2. Configure NFSv4 ACLs:
   - `owner@`: **Full Control**
   - `group@` (= `private`, GID 3202): **Modify**
3. Enable **File Inherit** and **Directory Inherit** on ACL entries

### Container Configuration

Private-data containers hardcode the GID in `user:` directives and the init container:

```yaml
user: "3106:3202" # svc-app-immich:private
```
