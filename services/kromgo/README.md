# Kromgo

Kromgo is a lightweight proxy that safely exposes individual Prometheus metric values as public badge endpoints. Define named metrics backed by PromQL queries and serve them as SVG badges or shields.io-compatible JSON — without exposing your Prometheus instance directly.

- **Project**: [kashalls/kromgo](https://github.com/kashalls/kromgo)

## Why

Embedding live status badges in READMEs, dashboards, or status pages requires a public-facing endpoint — but exposing the raw Prometheus API to the internet is not acceptable. Kromgo acts as a thin, read-only proxy: it queries an upstream Prometheus-compatible store on behalf of badge consumers, applies per-metric PromQL, and returns only the specific value the caller asked for. In this home lab, Kromgo points at **Grafana Cloud Mimir** (the same store Alloy writes host metrics and container logs to — see Issue #15) and exposes a small set of safe, public badges without leaking the raw metrics API or query interface.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/kromgo/compose.yaml)

## Access

| URL                            | Description                           |
| ------------------------------ | ------------------------------------- |
| `https://badges.${DOMAINNAME}` | Badge API — public, no authentication |

## Architecture

- **Image**: [ghcr.io/kashalls/kromgo](https://github.com/kashalls/kromgo) (`v0.4.2`)
- **User/Group**: `3126:3126` (`svc-app-kromgo`)
- **Networks**: `kromgo-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-no-auth@file` middleware — badge endpoints are intentionally public-facing
- **Upstream**: Grafana Cloud Mimir, addressed via `PROMETHEUS_URL` with credentials embedded as URL userinfo (`https://<id>:<token>@host/api/prom`). Go's `net/http` client picks up the userinfo and adds a Basic auth header automatically, so no auth sidecar is needed.
- **Config**: `./config/config.yaml` mounted read-only at `/kromgo/config.yaml`; file is git-tracked so no init container is needed
- **Read-only root filesystem**: tmpfs mounted at `/tmp`
- **Health check**: `GET http://localhost:8888/healthz` (port 8888, separate from the API on port 8080)

## Metrics

All metrics are defined in `config/config.yaml`. Each metric is served at two endpoints:

- `GET /<name>` — shields.io-compatible JSON (default)
- `GET /<name>?format=badge` — SVG badge

| Metric name             | Badge title  | Status   | Description                                                                       |
| ----------------------- | ------------ | -------- | --------------------------------------------------------------------------------- |
| `host_load1`            | Load (1m)    | Active   | 1-minute load average on the primary NAS host (Alloy `prometheus.exporter.unix`)  |
| `host_disk_free_pct`    | Disk Free    | Active   | Free space percentage on the apps pool root filesystem                            |
| `compose_last_update`   | Last Update  | Hidden   | Human-readable duration since the CD pipeline last ran — needs Issue #15 Phase 2  |
| `compose_last_success`  | Last Success | Hidden   | Human-readable duration since the CD pipeline last succeeded — same dependency   |
| `compose_update_status` | CD Status    | Hidden   | `Success` or `Failed` result of the most recent CD run — same dependency         |

<!-- dprint-ignore -->
!!! note "Pending follow-ups"
    The `compose_*` badges depend on `dccd.sh` pushing `dccd_last_run_timestamp_seconds`, `dccd_last_success_timestamp_seconds`, and `dccd_last_run_success` gauges to Alloy's `prometheus.receive_http` listener (planned for Issue #15 Phase 2). They are kept in `config/config.yaml` with `hidden: true` so the queries are ready to switch on once the push integration lands. Container-count badges (`docker_*`) are commented out and will return once cAdvisor scrape is added to Alloy.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

| Variable         | Description                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------------------ |
| `PROMETHEUS_URL` | Grafana Cloud Mimir endpoint with credentials as userinfo: `https://<instance-id>:<token>@<host>/api/prom`   |
| `DOMAINNAME`     | Base domain for Traefik routing                                                                              |

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/kromgo` in TrueNAS.
2. Create a `svc-app-kromgo` group (GID `3126`) and user (UID `3126`) on the TrueNAS host.
3. In Grafana Cloud → **My Account** → your stack → **Prometheus** → **Details**, copy the URL and instance ID. Create a Cloud Access Policy token scoped to `metrics:read` only, named `kromgo-read`. Compose the `PROMETHEUS_URL` value as `https://<instance-id>:<token>@<host>/api/prom` and write it to `secret.sops.env`, then encrypt with `scripts/encrypt-secrets.sh`.
4. Review `config/config.yaml` — adjust queries to match the metric labels Alloy is currently emitting (e.g. confirm `instance="svlnas"`).
5. Deploy — verify a badge at `https://badges.${DOMAINNAME}/host_load1?format=badge`.

## Upgrade Notes

No persistent data to migrate. The config is git-tracked in `config/config.yaml` and is unaffected by container image updates. Redeploy replaces the container cleanly.

If a new Kromgo version changes the `config.yaml` schema, compare the upstream [config.schema.json](https://raw.githubusercontent.com/kashalls/kromgo/main/config.schema.json) against the local file before deploying.

Image updates are managed by Renovate.
