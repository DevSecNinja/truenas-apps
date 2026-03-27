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
    security_opt:
      - no-new-privileges=true             # Block privilege escalation
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
- Memory limits with env-var overrides for per-environment tuning
- Health checks are mandatory — `dccd.sh` uses `docker compose up --wait`
- Volumes mounted `:ro` wherever the container only reads

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

## Secret Management

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [Age](https://github.com/FiloSottile/age) and stored in git as `secret.sops.env`. The CD script decrypts them to `.env` at deploy time using an Age key stored on the TrueNAS host.
