# Kromgo

Kromgo is a lightweight proxy that safely exposes individual Prometheus metric values as public badge endpoints. Define named metrics backed by PromQL queries and serve them as SVG badges or shields.io-compatible JSON — without exposing your Prometheus instance directly.

- **Project**: [kashalls/kromgo](https://github.com/kashalls/kromgo)

## Why

Embedding live status badges in READMEs, dashboards, or status pages requires a public-facing endpoint — but exposing the raw Prometheus API to the internet is not acceptable. Kromgo acts as a thin, read-only proxy: it queries Prometheus on behalf of badge consumers, applies per-metric PromQL, and returns only the specific value the caller asked for. The badges on this home lab expose compose pipeline health (last update, last success, CD status) and infrastructure scale (running containers, running services) without leaking raw metrics or query interfaces.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/kromgo/compose.yaml)

## Access

| URL                            | Description                           |
| ------------------------------ | ------------------------------------- |
| `https://badges.${DOMAINNAME}` | Badge API — public, no authentication |

## Architecture

- **Image**: [ghcr.io/kashalls/kromgo](https://github.com/kashalls/kromgo) (`v0.4.2`)
- **User/Group**: `3125:3125` (`svc-app-kromgo`)
- **Networks**: `kromgo-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-no-auth@file` middleware — badge endpoints are intentionally public-facing
- **Config**: `./config/config.yaml` mounted read-only at `/kromgo/config.yaml`; file is git-tracked so no init container is needed
- **Read-only root filesystem**: tmpfs mounted at `/tmp`
- **Health check**: `GET http://localhost:8888/healthz` (port 8888, separate from the API on port 8080)

## Metrics

All metrics are defined in `config/config.yaml`. Each metric is served at two endpoints:

- `GET /badges/<name>` — SVG badge (rendered with the configured font and colors)
- `GET /<name>?format=endpoint` — shields.io-compatible JSON

| Metric name                 | Badge title  | Description                                                                   |
| --------------------------- | ------------ | ----------------------------------------------------------------------------- |
| `docker_containers_running` | Containers   | Count of running Docker containers across all Compose projects (via cAdvisor) |
| `docker_services_running`   | Services     | Count of distinct Compose services across all projects (via cAdvisor)         |
| `compose_last_update`       | Last Update  | Human-readable duration since the CD pipeline last ran                        |
| `compose_last_success`      | Last Success | Human-readable duration since the CD pipeline last succeeded                  |
| `compose_update_status`     | CD Status    | `Success` or `Failed` result of the most recent CD run                        |

<!-- dprint-ignore -->
!!! note "Exporter dependency"
    The `docker_*` metrics require cAdvisor (or a compatible exporter) to be scraped by Prometheus with `container_label_com_docker_compose_project` labels populated. The `compose_*` metrics require the CD pipeline to push `dccd_last_run_timestamp_seconds`, `dccd_last_success_timestamp_seconds`, and `dccd_last_run_success` gauges to a Prometheus Pushgateway.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

| Variable         | Description                                                          |
| ---------------- | -------------------------------------------------------------------- |
| `PROMETHEUS_URL` | URL of the Prometheus instance Kromgo queries for all PromQL metrics |
| `DOMAINNAME`     | Base domain for Traefik routing                                      |

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/kromgo` in TrueNAS
2. Create a `svc-app-kromgo` group (GID `3125`) and user (UID `3125`) on the TrueNAS host
3. Set `PROMETHEUS_URL` in `secret.sops.env` to the internal URL of your Prometheus instance
4. Review `config/config.yaml` — adjust PromQL queries and label selectors to match your Prometheus exporter's label schema (cAdvisor label names vary by version and deployment)
5. Deploy — verify a badge at `https://badges.${DOMAINNAME}/badges/docker_containers_running`

## Upgrade Notes

No persistent data to migrate. The config is git-tracked in `config/config.yaml` and is unaffected by container image updates. Redeploy replaces the container cleanly.

If a new Kromgo version changes the `config.yaml` schema, compare the upstream [config.schema.json](https://raw.githubusercontent.com/kashalls/kromgo/main/config.schema.json) against the local file before deploying.

Image updates are managed by Renovate.
