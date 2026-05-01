# Grafana Alloy

[Grafana Alloy](https://grafana.com/oss/alloy/) is a unified telemetry collector. One agent ships **host metrics** and **container logs** to [Grafana Cloud](https://grafana.com/products/cloud/) — replacing what would otherwise be two separate processes (node_exporter, Promtail). Per-container metrics are deferred to a later phase of #15 (see [Out of scope](#out-of-scope) below).

## Why

The lab needs trend-based visibility (per-container CPU/memory over weeks, host disk pressure, ZFS pool health) and centralised logs that survive container restarts. Self-hosting the full Grafana + Prometheus + Loki stack would cost ~500 MB RAM and require ongoing maintenance for zero functional benefit over the Grafana Cloud Free tier.

Alloy collapses what previously required several agents into a single process:

- **Host metrics** via `prometheus.exporter.unix` (the embedded `node_exporter` library — `/proc`, `/sys`, and the rootfs are bind-mounted from the host).
- **Container logs** via `loki.source.docker`, with a `discovery.docker` step that auto-discovers running containers and promotes compose project/service labels. Reaches the Docker socket through a read-only LinuxServer socket-proxy. A `loki.process` stage drops entries older than 167h before they reach Loki to stay inside Grafana Cloud Free's 7-day ingest window — this is what keeps a post-restart backfill of long-lived containers (immich-db-backup, matter-server) from getting whole batches rejected with HTTP 400.
- **Traefik metrics** via `prometheus.scrape "traefik"`, targeting the local Traefik instance at `traefik:8082/metrics` over the shared `alloy-frontend` Docker network (60s interval, `host` and `job=traefik` labels added via relabeling). Per-router, per-service, and per-entrypoint label cardinality is enabled on the Traefik side. The `:8082` entrypoint is internal-only and gated by an `ipAllowList` restricted to the pinned `alloy-frontend` subnet (`172.30.100.8/29`) — see [Architecture § Alloy Metrics Scrape Entrypoint](../ARCHITECTURE.md#alloy-metrics-scrape-entrypoint).
- **Immich Postgres** via `prometheus.scrape "postgres_immich"`, targeting `immich-db-exporter:9187` over the `immich-backend` Docker network (60s interval, `host` and `job=postgres_immich` labels added via relabeling). The exporter sidecar lives in `services/immich/compose.yaml` and reuses Immich's `IMMICH_DB_PASSWORD` — no DB credentials are added to Alloy's `secret.sops.env`. Scoped to svlnas (dropped on svlazext via `compose.svlazext.yaml`).
- **Outline Postgres** via `prometheus.scrape "postgres_outline"`, targeting `outline-db-exporter:9187` over the `outline-backend` Docker network (60s interval, `host` and `job=postgres_outline` labels added via relabeling). The exporter sidecar lives in `services/outline/compose.yaml` and reuses Outline's `OUTLINE_DB_PASSWORD`. Scoped to svlnas (dropped on svlazext via `compose.svlazext.yaml`).
- **GitHub repo stats** via `prometheus.exporter.github` polling the GitHub REST API for `DevSecNinja/truenas-apps` and `DevSecNinja/dotfiles` (10m interval, `host` and `job=integrations/github_exporter` labels added via relabeling). Surfaces rate-limit headroom, stars/forks/watchers, open PR/issue counts, and repo size. Authenticates with a fine-grained GitHub PAT (`Metadata` + `Issues` + `Pull requests` read-only on the listed repos) stored as `GITHUB_API_TOKEN` in `secret.sops.env`. **Single-host scrape**: gated to `svlnas` via a `discovery.relabel` keep rule on `HOSTNAME_OVERRIDE` so only one Alloy instance polls the API; on svlazext the target list filters to empty and `prometheus.scrape` is a no-op.
- **Self-observability** via `prometheus.exporter.self`.

### Out of scope

**Per-container metrics** (CPU, memory, network per container) are deliberately deferred. Alloy's only built-in option is `prometheus.exporter.cadvisor`, which wraps the embedded cAdvisor library and requires `privileged: true` plus mounts on `/sys`, `/var/lib/docker`, `/dev/disk`, and `/var/run` — conflicting with the hardened-container posture used elsewhere in this repo. Container logs already surface the signals that matter for alerting (restarts, OOM, crashes), so this is a deliberate Phase 2 decision rather than an oversight.

Everything is shipped to **Grafana Cloud Free** (Frankfurt region) — Prometheus for metrics, Loki for logs, Grafana for dashboards and alerting.

See [issue #15](https://github.com/DevSecNinja/truenas-apps/issues/15) for the full monitoring/IRM rollout plan.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/alloy/compose.yaml)
- [compose.svlazext.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/alloy/compose.svlazext.yaml) — per-host override (sets `HOSTNAME_OVERRIDE=svlazext`)

## Access

| URL                               | Description                                                    |
| --------------------------------- | -------------------------------------------------------------- |
| `https://alloy.${DOMAINNAME}`     | Alloy debug UI (component graph, scrape state) — SSO-protected |
| `https://alloy-ext.${DOMAINNAME}` | Same UI on svlazext                                            |

## Architecture

- **Image**: [`dhi/alloy`](https://hub.docker.com/hardened-images/catalog/dhi/alloy) (Docker Hardened Image, Debian 13 base) — minimal rootfs, no shell beyond `/bin/sh` (dash), continuously rebuilt against patched bases. Requires the host to be logged in to a DHI-entitled Docker Hub account.
- **User/Group**: `3125:3125` (`svc-app-alloy`)
- **Networks**: `alloy-frontend` (Traefik-facing, also used for outbound Grafana Cloud traffic), `alloy-backend` (internal — Docker socket proxy)
- **Reverse proxy**: Traefik with `chain-auth@file` (SSO required)

### Services

| Container            | Role                                                                                                    |
| -------------------- | ------------------------------------------------------------------------------------------------------- |
| `alloy-init`         | One-shot init: chowns `./data` to `3125:3125` so the Alloy WAL + queue path is writable                 |
| `alloy`              | Telemetry collector — reads host `/proc`/`/sys`/rootfs, polls Docker stats, tails container logs        |
| `alloy-docker-proxy` | LinuxServer socket-proxy — read-only Docker API access (`CONTAINERS=1`, `EVENTS=1`, `INFO=1`, `POST=0`) |

### Volumes

- `./config:/etc/alloy:ro` — `config.alloy` (git-tracked, read-only)
- `./data:/var/lib/alloy` — Alloy state directory; Alloy creates `data/` (WAL + queue) and `remotecfg/` subdirectories at startup (gitignored, chowned by init container)
- `/:/host/rootfs:ro,rslave`, `/proc:/host/proc:ro`, `/sys:/host/sys:ro` — host filesystem visibility for `prometheus.exporter.unix`

### Resource footprint

Target on a host with ~30 containers: **<200 MB RAM, <2% sustained CPU**. Adjust `MEM_LIMIT` in `secret.sops.env` if a host scrapes additional targets.

## Secrets

Managed via `secret.sops.env` (decrypted to `.env` at deploy time):

| Variable                | Source                                                                               |
| ----------------------- | ------------------------------------------------------------------------------------ |
| `GRAFANA_PROM_URL`      | Grafana Cloud → stack details → Prometheus push URL                                  |
| `GRAFANA_PROM_USERNAME` | Numeric instance ID shown next to the push URL                                       |
| `GRAFANA_PROM_PASSWORD` | Access Policy token with `metrics:write` scope                                       |
| `GRAFANA_LOKI_URL`      | Grafana Cloud → stack details → Loki push URL                                        |
| `GRAFANA_LOKI_USERNAME` | Numeric instance ID shown next to the Loki URL                                       |
| `GRAFANA_LOKI_PASSWORD` | Same Access Policy token (or a separate one with `logs:write` scope)                 |
| `GITHUB_API_TOKEN`      | Fine-grained GitHub PAT, read-only `Metadata`/`Issues`/`Pull requests` (svlnas only) |

Optional resource overrides: `MEM_LIMIT`, `SOCKET_PROXY_MEM_LIMIT`.

### Per-host configuration

The static `host` label injected into every metric and log line is set via the
`HOSTNAME_OVERRIDE` environment variable in
[compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/alloy/compose.yaml)
(default: `svlnas`). For non-default hosts, override it in a `compose.<server>.yaml`
file — see
[compose.svlazext.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/alloy/compose.svlazext.yaml).
It is **not a secret** and lives in the compose file rather than `secret.sops.env`.

## First-Run Setup

1. **Create the dataset**: `vm-pool/apps/services/alloy` on TrueNAS.
2. **Create the TrueNAS service account**: `svc-app-alloy` with UID/GID `3125:3125`.
3. **Create a Grafana Cloud Access Policy token**:
   - Grafana Cloud → "Access Policies" → "Create access policy".
   - Scopes: `metrics:write`, `logs:write`. Realms: limit to your stack.
   - Generate a token; copy the `glc_…` value.
4. **Populate `secret.sops.env`** with the URLs from the stack details page and the token from step 3.
5. **Encrypt the secrets**:

   ```sh
   bash scripts/encrypt-secrets.sh
   ```

6. **Validate the compose file**:

   ```sh
   docker compose -f services/alloy/compose.yaml config --quiet
   ```

7. **Deploy**:

   ```sh
   bash scripts/dccd.sh -d /mnt/vm-pool/apps -t -f -A alloy   # svlnas
   bash scripts/dccd.sh -d /opt/apps -S svlazext -A alloy      # svlazext
   ```

8. **Verify** in Grafana Cloud Explore:
   - Metrics: `up{job="alloy",host="svlnas"} == 1`
   - Logs: `{host="svlnas", job="docker"}`

## Privacy Notes

Container logs **leave the network** to Grafana Cloud. The default `loki.source.docker` config ships everything from every container; per-service redaction and exclusion rules are added in Phase 2 of #15. Until then, treat this as "everything that goes to stdout/stderr from any container is in Grafana Cloud (EU region) for 30 days."

If a service must never have its logs leave the network, exclude it temporarily by adding a `discovery.relabel` drop rule against `__meta_docker_container_name` in `config.alloy`.

## Reference

- Alloy components: <https://grafana.com/docs/alloy/latest/reference/components/>
- Grafana Cloud free-tier limits: <https://grafana.com/pricing/>
- Issue #15 — full monitoring rollout plan: <https://github.com/DevSecNinja/truenas-apps/issues/15>
