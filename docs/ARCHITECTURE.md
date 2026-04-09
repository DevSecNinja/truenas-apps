# Architecture

## Renovate

Dependency updates are managed by Renovate. The configuration lives in `renovate.json5` (root) and split files under `.renovate/`:

| File                              | Purpose                                                              |
| --------------------------------- | -------------------------------------------------------------------- |
| `renovate.json5`                  | Root config — global settings and `extends` index                    |
| `.renovate/autoMerge.json5`       | Auto-merge policy for GitHub Actions                                 |
| `.renovate/customManagers.json5`  | Regex managers for SOPS version, mise min_version, workflow versions |
| `.renovate/groups.json5`          | Grouped updates (postgres, mise)                                     |
| `.renovate/labels.json5`          | PR labels by update type and datasource                              |
| `.renovate/packageRules.json5`    | Release age gates, stale-dependency flag, linuxserver versioning     |
| `.renovate/semanticCommits.json5` | Scoped commit messages with version arrows                           |

### Update timing policy

All updates must meet a minimum release age before Renovate opens a PR, giving time for bad releases to be retracted:

| Update type            | Manager / datasource       | Minimum age           |
| ---------------------- | -------------------------- | --------------------- |
| minor / patch          | `actions/*` GitHub Actions | 3 days, auto-merged   |
| digest                 | All GitHub Actions         | 14 days, auto-merged  |
| minor / patch          | All other GitHub Actions   | 14 days, manual merge |
| major                  | Everything                 | 14 days, manual merge |
| minor / patch / digest | Docker images              | 14 days, manual merge |
| minor / patch / digest | GitHub Releases            | 14 days, manual merge |
| minor / patch / digest | `mise` tools               | 14 days, manual merge |

Auto-merges use `automergeType: "branch"` (direct push, no PR) and require CI to pass. Major updates always require a manual merge regardless of datasource.

### Rule precedence note

`packageRules` are applied in the order they appear across all `extends` entries — **last matching rule wins** for each property. `autoMerge.json5` is loaded before `packageRules.json5`, so `packageRules.json5` must not contain a `matchManagers: ["github-actions"]` timing rule or it would override the 3-day exception for `actions/*`.

## Commit Message Convention

All commits follow the [Conventional Commits](https://www.conventionalcommits.org) specification:

```
<type>(<scope>): <description>
```

Common types: `feat`, `fix`, `chore`, `docs`, `refactor`, `ci`. The scope is typically the service folder name (e.g. `feat(immich):`, `fix(traefik):`). Compliance is enforced locally by a lefthook `commit-msg` hook using `cog verify`.

## Release Process

Releases are version-tagged on `main` and automatically published as GitHub Releases via a CI workflow.

### Creating a release

```sh
# Bump the minor version (updates CHANGELOG.md, commits, tags, and pushes)
cog bump --minor

# Or patch for bug-fix releases
cog bump --patch

# Dry-run to preview the next version without making changes
cog bump --minor --dry-run
```

`cog bump` orchestrates the full release:

1. Calculates the next semver version from conventional commits since the previous tag
2. Runs `git-cliff --tag <version> --output CHANGELOG.md` to regenerate the full changelog
3. Runs `dprint fmt CHANGELOG.md` to ensure the changelog passes CI formatting checks
4. Creates a `chore(release): bump version to <version>` commit containing the changelog update
5. Creates the `v<version>` git tag
6. Pushes the commit and tag to `origin`

The tag push triggers `.github/workflows/release.yml`, which runs `git-cliff --latest --strip all`
to produce release-scoped notes and creates the GitHub Release automatically.

### Tools

| Tool         | Role                                                             |
| ------------ | ---------------------------------------------------------------- |
| `cog`        | Version bump, bump commit, git tag, push orchestration           |
| `git-cliff`  | Changelog generation (`CHANGELOG.md` + GitHub Release notes)     |
| `cliff.toml` | Commit grouping, body template, GitHub commit link configuration |
| `cog.toml`   | Bump hooks, tag prefix, merge-commit filtering                   |

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
    deploy:
      restart_policy:
        condition: on-failure             # Restart only on crash (non-zero exit)
        max_attempts: 3                   # Stop after 3 rapid crashes within the window
        window: 120s                      # Counter resets if the container is up > 2 min
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
      chown -Rv <UID>:<GID> /path/a /path/b &&
      find /path/b -type d -exec chmod 775 {} + &&
      find /path/b -type f -exec chmod 664 {} +
  volumes:
    - <app>-volume:/path/a
    - ./config:/path/b     # git-tracked config — group-write for truenas_admin
```

For services that only chown runtime-only paths (named Docker volumes, `./data/`), the `chmod 775/664` step and `FOWNER`/`DAC_OVERRIDE` capabilities can be omitted — only `CHOWN` is needed. Docker creates named volumes and `./data/` directories as `root:root 755`, so UID 0 is always the owner and can traverse them without `DAC_OVERRIDE`.

**Exception — external bind-mount paths with non-root ownership:** If the bind-mount source is a host directory owned by a non-root user (e.g., a TrueNAS dataset with `truenas_admin:truenas_admin 770`), UID 0 inside the container matches neither owner nor group and has no permissions. Busybox `chown -Rv` opens the directory before chowning it, which fails without `DAC_OVERRIDE`. Add `DAC_OVERRIDE` to any init container that chowns such a path.

**Exceptions — images that manage their own permissions:**

- **s6-overlay images** (LinuxServer, tiredofit/db-backup) start as root and chown their own directories during their own init phase. They do not need an external init container.
- **Database images** (postgres, MongoDB) initialise their own data directories. They do not need an external init container.

**Services using this pattern:**

| Service              | Init container              | Volumes chown'd                                                                    |
| -------------------- | --------------------------- | ---------------------------------------------------------------------------------- |
| _bootstrap           | `content-init`              | `/mnt/archive-pool/content` (full tree: mkdir + chown `:3200` + setgid `2775`)     |
| adguard              | `adguard-init`              | `./data/work`, `./data/conf`                                                       |
| dozzle               | `dozzle-init`               | `./data`                                                                           |
| homepage             | `homepage-init`             | `./config`                                                                         |
| metube               | `metube-init`               | `./data/state`                                                                     |
| traefik              | `traefik-init`              | `./data/acme`, `./config`                                                          |
| traefik-forward-auth | `traefik-forward-auth-init` | `./data`                                                                           |
| immich               | `immich-init`               | `/mnt/archive-pool/private/photos/immich` (+ `DAC_OVERRIDE`), `./data/model-cache` |
| spottarr             | `spottarr-chown`            | `./data`                                                                           |

---

**Exceptions — s6-overlay and root-start containers:**

Some images cannot use `read_only: true` or `user:` because their init system (s6-overlay) requires a writable root filesystem and starts as root before dropping privileges internally. `cap_drop: ALL` is **still required** for these images — only the specific capabilities that s6-overlay needs are re-added via `cap_add`. Each such container must include a comment block in the compose file explaining the deviation. This applies to:

- **LinuxServer images** (e.g., `unifi-network-application`, `plex`) — use `PUID`/`PGID` environment variables for internal privilege dropping; omit `user:` and `read_only`. Add back `CHOWN`, `SETUID`, `SETGID`, and `SETPCAP` via `cap_add`.
- **LinuxServer socket-proxy** — runs as root by design to proxy the Docker socket. Does not support custom users, mods, or scripts. Omit `cap_drop: ALL`; `no-new-privileges` and `read_only` are still applied.
- **tiredofit/db-backup** — uses `USER_DBBACKUP`/`GROUP_DBBACKUP` for internal privilege dropping; omit `user:` and `read_only`.
- **mvance/unbound** — starts as root and drops privileges to the `_unbound` user internally; its startup script generates `unbound.conf` and creates subdirectories at runtime, so omit `user:` and `read_only`.
- **meeb/tubesync** — uses its own `start.sh` init script to create the `PUID:PGID` user, chown `/config`, and launch supervisord; omit `user:` and `read_only:`. Add back `CHOWN`, `SETUID`, `SETGID`, and `SETPCAP` via `cap_add`.
- **ghcr.io/home-assistant/home-assistant** — a Python application that runs as root (UID 0) with no PUID/PGID support and no init system. It writes Python bytecache files into the image layer and state files outside `/config` at startup. Omit `user:` and `read_only:`. No `cap_add` is required since HA only uses file I/O and normal TCP networking (port 8123 > 1024). No init container is needed — HA manages its own `/config` directory permissions. No TrueNAS service account is required; data files in `./data/config` will be owned by `root:root` on the host.

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

### Exception: arr-stack-backend

The arr stack (Radarr, Sonarr, Bazarr, Lidarr, Prowlarr, qBittorrent, SABnzbd, Spottarr) shares a single `arr-stack-backend` internal bridge network so the apps can communicate directly for API calls (e.g., Prowlarr pushing indexer results to Sonarr). This network is created by the `_bootstrap` service and referenced as `external: true` by each arr app. All internet traffic still exits through each app's dedicated VLAN 70 macvlan network — the backend bridge is `internal: true` and carries no internet route.

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
services/<service>/
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

Each service account has a matching `svc-app-<name>` group created at the same GID as its UID. These groups are **GID reservations only** — they exist to prevent TrueNAS from assigning the GID to an unrelated group in the future. The app's _functional_ primary group is typically a shared purpose group (e.g., `media` at GID 3200), not the `svc-app-*` placeholder. There is no need to add `truenas_admin` or other users to the `svc-app-*` groups.

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
| 3109    | `svc-app-dozzle`   | dozzle, dozzle-init                         | No                  |
| 3110    | `svc-app-radarr`   | radarr                                      | No                  |
| 3118    | `svc-app-tubesync` | tubesync                                    | No                  |
| 3119    | `svc-app-drawio`   | drawio                                      | No                  |

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

## Shared Environment Files

Reusable env files live in `services/shared/env/` and are referenced via relative paths in `env_file` blocks. They are committed to Git because they contain no secrets.

| File     | Purpose                    | When to include |
| -------- | -------------------------- | --------------- |
| `tz.env` | Sets `TZ=Europe/Amsterdam` | Every container |

UID and GID values are **not** stored in shared env files or in `secret.sops.env`. They are hardcoded directly in each service's `compose.yaml` (in the `user:` directive and init container commands) so they are visible, auditable, and not treated as secrets. See § UID/GID Allocation for the full allocation table.

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
