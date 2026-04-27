# Prometheus

[Prometheus](https://prometheus.io/) is an open-source systems monitoring and alerting toolkit. It collects metrics from configured targets at given intervals, evaluates rule expressions, and stores the results in a time-series database.

## Why

Prometheus is the de-facto standard for pull-based metrics collection in container environments. It is the foundation needed before adding visualisation (Grafana — [#194](https://github.com/DevSecNinja/truenas-apps/issues/194)), node-level metrics (node_exporter — [#233](https://github.com/DevSecNinja/truenas-apps/issues/233)), or alert routing (Alertmanager — [#15](https://github.com/DevSecNinja/truenas-apps/issues/15)).

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/prometheus/compose.yaml)

## Access

| URL                                 | Description                   |
| ----------------------------------- | ----------------------------- |
| `https://prometheus.${DOMAINNAME}`  | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [prom/prometheus](https://hub.docker.com/r/prom/prometheus) (busybox-based)
- **User/Group**: `3125:3125` (`svc-app-prometheus`)
- **Networks**: `prometheus-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **Retention**: 30 days TSDB retention (`--storage.tsdb.retention.time=30d`)

### Services

| Container         | Role                                                         |
| ----------------- | ------------------------------------------------------------ |
| `prometheus-init` | One-shot init: chowns `./data` to `3125:3125`                |
| `prometheus`      | Prometheus server — scrapes metrics, serves web UI on `9090` |

### Volumes

| Host path                     | Container path                  | Mode | Purpose                             |
| ----------------------------- | ------------------------------- | ---- | ----------------------------------- |
| `./config/prometheus.yml`     | `/etc/prometheus/prometheus.yml` | ro   | Scrape config (git-tracked)         |
| `./data`                      | `/prometheus`                    | rw   | TSDB time-series database (chown'd) |

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing

> **Note for first deploy:** the file in this repository is committed unencrypted as a placeholder. Run `sops -e -i services/prometheus/secret.sops.env` after setting the real `DOMAINNAME` value, then re-commit before deploying.

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/prometheus` in TrueNAS
2. Create a `svc-app-prometheus` group (GID 3125) and user (UID 3125) on the TrueNAS host
3. Encrypt `secret.sops.env` with SOPS (see note above)
4. Deploy — Prometheus starts scraping itself on `localhost:9090`

## Adding Scrape Targets

Edit [`config/prometheus.yml`](config/prometheus.yml) to add new `scrape_configs`. Targets must be reachable from the `prometheus-frontend` network. To scrape another container, attach it to `prometheus-frontend` (just like Traefik does) and reference it by container name.

After editing the config either:

- Restart the container: `docker compose -f services/prometheus/compose.yaml up -d --force-recreate`, **or**
- Hot-reload with `curl -X POST https://prometheus.${DOMAINNAME}/-/reload` (lifecycle endpoint is enabled via `--web.enable-lifecycle`).

## Upgrade Notes

No special upgrade procedures. Image updates are managed by Renovate. Prometheus uses an append-only TSDB on disk; the format is forward-compatible within a major version (v3.x).
