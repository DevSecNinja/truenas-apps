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
    user: "${PUID:-1000}:${PGID:-1000}"    # Non-root with fallback
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

- Images are digest-pinned (`@sha256:...`) — Renovate manages updates via PRs
- `read_only: true` with `tmpfs` mounts for writable paths
- `no-new-privileges` on every container, no exceptions
- `cap_drop: ALL` on every container — this is a hard security requirement. If a container needs a specific capability, declare `cap_add` with only the minimum required capability and add a comment on the container in the compose file explaining why the exception is necessary
- Memory limits with env-var overrides for per-environment tuning
- `pids_limit` on every container to prevent fork-bomb DoS
- Health checks are mandatory — `dccd.sh` uses `docker compose up --wait`
- Volumes mounted `:ro` wherever the container only reads

## Volume Permissions: Init Container Pattern

Named Docker volumes and bind-mounted directories are created as `root:root` by Docker. A container with `user: "${PUID}:${PGID}"` and `cap_drop: ALL` has no `CAP_CHOWN` and cannot fix this at runtime — it will fail to write on first deploy.

**Rule:** Any service with both of the following requires a `<app>-init` container:

1. `user: "${PUID}:${PGID}"` (explicit non-root)
2. At least one writable volume (named volume or bind mount)

The init container runs as root, chowns the volume paths to `${PUID}:${PGID}`, and exits before the main container starts. The main service declares `depends_on: <app>-init: condition: service_completed_successfully`.

```yaml
# Pattern — copy this block, adjust container_name, command paths, and volumes
<app>-init:
  image: docker.io/library/busybox:1.37.0@sha256:1487d0af5f52b4ba31c7e465126ee2123fe3f2305d638e7827681e7cf6c83d5e
  container_name: <app>-init
  env_file:
    - path: .env          # Provides PUID/PGID
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
    - CHOWN # Required to chown volume paths to ${PUID}:${PGID}
  read_only: true
  command:
    - "sh"
    - "-c"
    - "chown -R ${PUID:-1000}:${PGID:-1000} /path/a /path/b"
  volumes:
    - <app>-volume:/path/a
    - ./data/something:/path/b
```

Init containers follow the same `cap_drop: ALL` hard requirement as all other containers. The single re-added capability, `CAP_CHOWN`, is the minimum needed to set volume ownership and is documented with a comment. Since the container exits immediately after chowning and exposes no network surface, this is a contained, minimal exception.

**Exceptions — images that manage their own permissions:**

- **s6-overlay images** (LinuxServer, tiredofit/db-backup) start as root and chown their own directories during their own init phase. They do not need an external init container.
- **Database images** (postgres, MongoDB) initialise their own data directories. They do not need an external init container.

**Services using this pattern:**

| Service | Init container | Volumes chown'd |
|---------|---------------|-----------------|
| adguard | `adguard-init` | `adguard-data`, `./data/conf` |
| homepage | `homepage-init` | `./config` |
| traefik | `traefik-init` | `traefik-acme` |

---

**Exceptions — s6-overlay and root-start containers:**

Some images cannot use `read_only: true`, `user:`, or `cap_drop: ALL` because their init system (s6-overlay) requires a writable root filesystem and starts as root before dropping privileges internally. Each such container must include a comment block in the compose file explaining why `cap_drop: ALL`, `user:`, and/or `read_only` are omitted. This applies to:

- **LinuxServer images** (e.g., `unifi-network-application`) — use `PUID`/`PGID` environment variables for internal privilege dropping; omit the `user:` directive and `read_only`.
- **tiredofit/db-backup** — uses `USER_DBBACKUP`/`GROUP_DBBACKUP` for internal privilege dropping; omit `user:` and `read_only`.
- **mvance/unbound** — starts as root and drops privileges to the `_unbound` user internally; its startup script generates `unbound.conf` and creates subdirectories at runtime, so omit `user:` and `read_only`.

Each exception is documented with a comment block in the compose file explaining why the deviation is necessary.

## Config Template Substitution: Envsubst Init Containers

Some services need secrets or environment-specific values (domain names, API keys) injected into their configuration files at deploy time. Since these config files are committed to Git as templates with `${VAR}` placeholders, a separate init container processes them before the main service starts.

**Pattern:** An `<app>-init` container mounts `./config` as `/templates:ro`, runs `envsubst.sh` to replace `${VAR}` placeholders with values from `secret.sops.env`, and writes the processed output to `./data/`. The main container then mounts the processed file from `data/` as `:ro`.

This keeps secrets out of Git (the template only contains placeholder names) while the processed config with real values lives in `data/` which is gitignored.

**Services using this pattern:**

| Service | Init container | Template → Output |
|---------|---------------|-------------------|
| adguard (unbound) | `adguard-unbound-init` | `config/unbound/*.conf` → `data/unbound/*.conf` |
| traefik-forward-auth | `traefik-forward-auth-init` | `config/config.yaml` → `data/config.yaml` |

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

``` text
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

## Shared Environment Files

Reusable env files live in `src/shared/env/` and are referenced via relative paths in `env_file` blocks. They are committed to Git because they contain no secrets.

| File | Purpose | When to include |
|------|---------|-----------------|
| `tz.env` | Sets `TZ=Europe/Amsterdam` | Every container |
| `pgid-puid-media.env` | Sets `PUID=568` / `PGID=568` | **Only** containers that need read/write access to TrueNAS media content (e.g., media servers, download clients). This UID/GID matches the TrueNAS built-in `apps` user that owns media datasets. Do not include it for infrastructure services (reverse proxy, monitoring, DNS, etc.) — those get their PUID/PGID from `secret.sops.env` instead. |
