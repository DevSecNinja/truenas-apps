# Architecture

This page covers Docker Compose patterns, container security rules, networking, and directory conventions. For host-level setup (UID/GID allocation, storage, multi-server deployment), see [Infrastructure](INFRASTRUCTURE.md). For development workflow (Renovate, commits, releases), see [Contributing](CONTRIBUTING.md).

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
    user: "3100:3100"                     # Hardcoded UID:GID (see Infrastructure § UID/GID Allocation)
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
- **`./config` volumes must always be mounted `:ro`** — config files are git-tracked and must never be modified by a container at runtime. If a service needs to write config at runtime, copy the file from `./config` to `./data` in an init container and mount the `./data` copy read-write (see the gatus pattern). Any exception requires explicit approval and a comment in the compose file explaining why

## Volume Permissions: Init Container Pattern

Named Docker volumes and bind-mounted directories are created as `root:root` by Docker. A container with a hardcoded non-root `user:` and `cap_drop: ALL` has no `CAP_CHOWN` and cannot fix this at runtime — it will fail to write on first deploy.

**Rule:** Any service with both of the following requires a `<app>-init` container:

1. `user: "<UID>:<GID>"` (explicit non-root)
2. At least one writable volume (named volume or bind mount)

The init container runs as root, chowns the volume paths to the service's UID:GID, and exits before the main container starts. The main service declares `depends_on: <app>-init: condition: service_completed_successfully`.

**Bind-mount directories (`./data`, `./backups`) that are runtime-only (gitignored) must be included in the init container's chown command**, even when the main container mounts a path inside them as `:ro`. A host-level `chown` (e.g. a TrueNAS dataset permission reset) can make those directories unreadable or untraversable. The init container is the single recovery point that restores ownership on every deploy.

**Git-tracked `./config` directories must NEVER be chowned or chmod'd by an init container.** Doing so changes file ownership away from the deploy user and causes `git pull` to fail with `error: unable to unlink old '...': Permission denied`. Config files checked out by git are already world-readable (`644` files, `755` directories), so any container user can read them without ownership changes. If a service needs to _write_ config at runtime, copy the file from `./config` to `./data` in the init container and mount the `./data` copy into the main container (see the gatus pattern).

```yaml
# Pattern — copy this block, adjust container_name, UID:GID, command paths, and volumes
# IMPORTANT: only chown ./data (runtime) paths — NEVER chown ./config (git-tracked)
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
  read_only: true
  command:
    - "sh"
    - "-c"
    - |-
      chown -Rv <UID>:<GID> /data
  volumes:
    - ./data:/data
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
| homepage             | _(removed)_                 | None — config is git-tracked and read-only; no init needed                         |
| metube               | `metube-init`               | `./data/state`                                                                     |
| traefik              | `traefik-init`              | `./data/acme`                                                                      |
| traefik-forward-auth | `traefik-forward-auth-init` | `./data`                                                                           |
| immich               | `immich-init`               | `/mnt/archive-pool/private/photos/immich` (+ `DAC_OVERRIDE`), `./data/model-cache` |
| spottarr             | `spottarr-chown`            | `./data`                                                                           |
| gatus                | `gatus-init`                | Copies `./config/config.yaml` → `./data/sidecar-config/` (config mounted `:ro`)    |
| home-assistant       | `home-assistant-init`       | Seeds `./config/configuration.yaml` → `./data/config/` on first deploy (`cp -n`)   |
| outline              | `outline-init`              | `./data/data` (chown to UID 1000 — image-internal `node` user)                     |
| hadiscover           | `hadiscover-init`           | `./data`                                                                           |
| matter-server        | `matter-server-init`        | `./data`                                                                           |
| mosquitto            | `mosquitto-init`            | `./data/data`, `./data/log`                                                        |
| wmbusmeters          | `wmbusmeters-init`          | `./data/logs`, `./data/state`                                                      |
| frigate              | `frigate-init`              | Seeds `./config/config.yml` → `./data/config/` on first deploy (`cp -n`)           |

---

**Exceptions — s6-overlay and root-start containers:**

Some images cannot use `read_only: true` or `user:` because their init system (s6-overlay) requires a writable root filesystem and starts as root before dropping privileges internally. `cap_drop: ALL` is **still required** for these images — only the specific capabilities that s6-overlay needs are re-added via `cap_add`. Each such container must include a comment block in the compose file explaining the deviation. This applies to:

- **LinuxServer images** (e.g., `unifi-network-application`, `plex`) — use `PUID`/`PGID` environment variables for internal privilege dropping; omit `user:` and `read_only`. Add back `CHOWN`, `SETUID`, `SETGID`, and `SETPCAP` via `cap_add`.
- **LinuxServer socket-proxy** — runs as root by design to proxy the Docker socket. Does not support custom users, mods, or scripts. Omit `cap_drop: ALL`; `no-new-privileges` and `read_only` are still applied.
- **tiredofit/db-backup** — uses `USER_DBBACKUP`/`GROUP_DBBACKUP` for internal privilege dropping; omit `user:` and `read_only`.
- **mvance/unbound** — starts as root and drops privileges to the `_unbound` user internally; its startup script generates `unbound.conf` and creates subdirectories at runtime, so omit `user:` and `read_only`.
- **meeb/tubesync** — uses its own `start.sh` init script to create the `PUID:PGID` user, chown `/config`, and launch supervisord; omit `user:` and `read_only:`. Add back `CHOWN`, `SETUID`, `SETGID`, and `SETPCAP` via `cap_add`.
- **ghcr.io/home-assistant/home-assistant** — uses s6-overlay (confirmed by `s6-rc` log lines). Omit `user:` and `read_only:`. Add back `CHOWN`, `SETUID`, `SETGID`, `SETPCAP` via `cap_add` (standard s6-overlay set). Also add `NET_RAW` — required by HA's built-in DHCP watcher integration, which opens raw `AF_PACKET` sockets to track devices; without it HA logs `[Errno 1] Operation not permitted` at startup and the DHCP integration stops working. No TrueNAS service account or init container is required — s6-overlay manages `/config` ownership internally.
- **ghcr.io/esphome/esphome** — compiles C++ firmware at runtime using platformio, downloading platform packages and managing build artifacts across `/config/.esphome/`. Requires extensive filesystem writes; omit `user:` and `read_only:`. `cap_drop: ALL` is applied; no additional capabilities are needed.
- **ghcr.io/blakeblackshear/frigate** — runs as root; manages its own internal processes (nginx, go2rtc, detector workers) and requires access to hardware devices (GPU, optional Coral TPU). Omit `user:` and `read_only:`. `cap_drop: ALL` is applied; no additional capabilities are needed.

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

### Exception: iot-backend

The IoT stack (Home Assistant, Mosquitto, ESPHome, Frigate, wmbusmeters) shares a single `iot-backend` internal bridge network so the services can communicate directly. For example, wmbusmeters publishes MQTT messages to Mosquitto, Home Assistant subscribes to MQTT topics, and Frigate sends events via MQTT. This network is created by the `_bootstrap` service and referenced as `external: true` by each IoT app. The backend bridge is `internal: true` and carries no internet route. Matter Server is excluded — it uses `network_mode: host` for mDNS device discovery and Thread border router communication.

### Gatus Internal Monitoring Entrypoint

Auth-protected services (those using `chain-auth@file`) redirect Gatus health checks to the OAuth login page, causing false-negative alerts. To monitor these services without bypassing network isolation, Traefik exposes a dedicated **monitoring entrypoint** on port 8444.

**How it works:**

1. Each auth-protected service declares a secondary Traefik router (`<app>-monitor`) that listens on the `monitoring` entrypoint and uses `chain-no-auth@file` instead of `chain-auth@file`.
2. Gatus sends HTTP requests to `http://172.30.100.6:8444` with the appropriate `Host` header. The IP is Traefik's **static address** on `gatus-frontend` (set via `ipv4_address` in `traefik/compose.yaml`) to avoid Docker DNS falling through to the host's external resolver.
3. Traefik routes the request to the target container over that service's dedicated frontend network.
4. Gatus endpoints also set `client.ignore-redirect: true` as defense-in-depth — if the monitoring router were misconfigured, Gatus would still detect a redirect rather than silently passing.

**Security model — three independent layers:**

1. **Unpublished port.** Port 8444 does not appear in Traefik's `ports:` mapping — the internet cannot reach it regardless of middleware misconfiguration.
2. **Docker network isolation.** Only containers that share a Docker network with Traefik can open a TCP connection to it. However, Traefik joins every service's frontend network, so this alone is insufficient — any container could reach `:8444`.
3. **Entrypoint-level `ipAllowList`.** The `monitoring` entrypoint in `traefik.yml` applies `monitoring-ipallowlist@file` (defined in `middlewares.yml`) which restricts source IPs to the `gatus-frontend` subnet (`172.30.100.0/29`). This runs before any router-level middleware, so it blocks all traffic from other frontend subnets. The `gatus-frontend` network uses a fixed IPAM subnet in `gatus/compose.yaml` to make this deterministic.

All three layers must be defeated for a container on another frontend network to bypass auth via the monitoring entrypoint.

**Why not a shared secret header instead of an IP allowlist?** Any container with a socket proxy (Dozzle, Homepage) could read the secret from `docker inspect` labels, so the secret is only as strong as the weakest socket-proxy consumer. The IP allowlist is infrastructure-derived, not stored anywhere a container can read it, and cannot be brute-forced.

**Traffic flow comparison:**

```text
Browser request (authenticated):
  Browser → Host:443 → Traefik :443 → chain-auth → (sonarr-frontend) → Sonarr

Gatus health check (internal monitoring):
  Gatus → (gatus-frontend 172.30.100.0/29) → Traefik :8444 [172.30.100.6]
    → ipAllowList ✓ → chain-no-auth → (sonarr-frontend) → Sonarr

Other container attempting to use monitoring entrypoint:
  Sonarr → (sonarr-frontend 172.x.x.x) → Traefik :8444
    → ipAllowList ✗ (403 Forbidden)
```

**Services with monitoring routers:** All services monitored by Gatus have a `-monitor` router on the monitoring entrypoint. This includes both auth-protected services (which need it to bypass forward-auth) and no-auth services (which need it to avoid TLS/SNI issues when checking by IP address). Only the Gatus service itself is excluded (`gatus.enabled=false`).

**Configuration locations (keep in sync when changing the subnet):**

| File                                            | What to update                                   |
| ----------------------------------------------- | ------------------------------------------------ |
| `services/gatus/compose.yaml`                   | `gatus-frontend` network `ipam.config[0].subnet` |
| `services/traefik/compose.yaml`                 | Traefik `gatus-frontend` `ipv4_address`          |
| `services/traefik/config/rules/middlewares.yml` | `monitoring-ipallowlist.ipAllowList.sourceRange` |
| `services/traefik/config/traefik.yml`           | Comment documenting the subnet (for reference)   |

## Docker Socket Proxy

Services never mount `/var/run/docker.sock` directly. Instead, each gets its own [LinuxServer socket-proxy](https://github.com/linuxserver/docker-socket-proxy) instance with minimal permissions:

- `CONTAINERS=1` — read container metadata only
- `POST=0` — read-only, no mutations (Homepage)
- Separate proxy per service to prevent lateral movement

**Why one proxy per service instead of sharing?**

If Traefik and Homepage shared one proxy, compromising either would grant the attacker the union of both permission sets. Separate proxies enforce least privilege per consumer.

## Docker Compose Profiles

Services with a `profiles:` key in their compose definition are **excluded from normal deploys**. Running `docker compose up -d` or `dccd.sh` does not start them — they only launch when their profile is explicitly activated. This is useful for services that are not always needed (e.g., an NVR that only runs when you are away from home).

**Services using profiles:**

| Profile        | Services                  | Purpose                               |
| -------------- | ------------------------- | ------------------------------------- |
| `surveillance` | `frigate-init`, `frigate` | NVR — only needed when away from home |

### Activating a Profile

**Environment variable (recommended):** Docker Compose natively reads the `COMPOSE_PROFILES` variable. Set it before running `dccd.sh`:

```sh
export COMPOSE_PROFILES=surveillance
```

Multiple profiles can be comma-separated:

```sh
export COMPOSE_PROFILES=surveillance,other
```

**On TrueNAS:** Add the export to the cron job that runs `dccd.sh`, or to `~/.bashrc` / `~/.profile` on the deployment user. The profiled services will start on the next deploy.

**CLI flag (one-off):** For a single manual run without persisting:

```sh
docker compose --profile surveillance up -d
```

### Deactivating a Profile

Unset the variable or remove the export line:

```sh
unset COMPOSE_PROFILES
```

On the next deploy, the profiled containers are no longer part of the active service set. `dccd.sh` uses `--remove-orphans` implicitly, so Docker Compose will stop and remove them automatically. To tear down immediately without waiting for a deploy cycle:

```sh
docker compose --profile surveillance down
```

### Gatus Monitoring

When a profile is inactive, its containers do not exist, so their Traefik labels are not discoverable by the Gatus sidecar. Monitoring for profiled services is automatically gated — no manual Gatus configuration is needed to suppress alerts.

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

**Named Docker volumes are not used in this repo.** All persistent container data uses bind mounts to `./data/` (or a subdirectory of it). This ensures that TrueNAS ZFS snapshots — taken at the dataset level — capture all container state without needing to snapshot opaque Docker-managed volumes. It also makes data locations explicit and auditable from the host filesystem.

**ZFS datasets do not need to be created manually for individual services.** The full dataset hierarchy is established once during initial setup (see `README.md § Setup`). Each `services/<app>/` directory lives on the `vm-pool/apps` dataset (or a child dataset created at setup time). TrueNAS handles snapshots and replication of these datasets automatically — no per-service backup containers are needed for file-level data (only for databases, which require consistent pg_dump / mongodump exports).

**`vm-pool/homes`** is a sibling dataset to `vm-pool/apps` (not a child). It holds user home directories. When a TrueNAS local user account has its home directory set to `/mnt/vm-pool/homes` and **Create Home Directory** is enabled, TrueNAS automatically creates a per-user subdirectory (e.g. `/mnt/vm-pool/homes/jean-paul`) with owner-only permissions (`rwx------`). Pool-level snapshots cover it automatically alongside `vm-pool/apps`.

**`backups/`** holds database backup files produced by the backup sidecar container (e.g., `tiredofit/db-backup`). Like `data/`, this directory is excluded from Git and mounted read-write. Each backup type gets its own subdirectory (e.g., `backups/db-backup/`).

## Secret Management

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [Age](https://github.com/FiloSottile/age) and stored in git as `secret.sops.env`. The CD script decrypts them to `.env` at deploy time using an Age key stored on the TrueNAS host.

`PUID` and `PGID` are hardcoded directly in each service's `compose.yaml` so they are visible, auditable, and self-documenting. See [Infrastructure § UID/GID Allocation](INFRASTRUCTURE.md#uidgid-allocation).

## Shared Environment Files

Reusable env files live in `services/shared/env/` and are referenced via relative paths in `env_file` blocks. They are committed to Git because they contain no secrets.

| File     | Purpose                    | When to include |
| -------- | -------------------------- | --------------- |
| `tz.env` | Sets `TZ=Europe/Amsterdam` | Every container |

UID and GID values are **not** stored in shared env files or in `secret.sops.env`. They are hardcoded directly in each service's `compose.yaml` (in the `user:` directive and init container commands) so they are visible, auditable, and not treated as secrets. See [Infrastructure § UID/GID Allocation](INFRASTRUCTURE.md#uidgid-allocation) for the full allocation table.
