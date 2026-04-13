# Traefik

Traefik is a modern reverse proxy and load balancer that automatically discovers services via Docker labels and handles TLS certificate management.

## Why

Exposing 20+ services to the network without a reverse proxy would mean managing individual ports, TLS certificates, and authentication for each one. Traefik consolidates all of this — every service gets a clean `https://<app>.${DOMAINNAME}` URL with automatic Let's Encrypt certificates via Cloudflare DNS challenge. Adding a new service to Traefik requires only Docker labels in the compose file, not proxy configuration changes.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/traefik/compose.yaml)
- [compose.svlazext.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/traefik/compose.svlazext.yaml) — Azure external VM override
- [compose.svlazextpub.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/traefik/compose.svlazextpub.yaml) — Azure public VM override

## Access

| URL                             | Description                      |
| ------------------------------- | -------------------------------- |
| `https://traefik.${DOMAINNAME}` | Dashboard (Traefik forward-auth) |

## Architecture

- **Image**: [traefik](https://github.com/traefik/traefik) (official)
- **User/Group**: `3100:3100` (`svc-app-traefik`)
- **Networks**: Joins every service's frontend network individually for per-service isolation (see [Architecture](../ARCHITECTURE.md#networking-per-service-isolation))
- **Ports**: `80` (HTTP → HTTPS redirect), `443` (HTTPS), `8444` (internal monitoring entrypoint — not published)
- **Reverse proxy**: Self-proxied dashboard with `chain-auth@file` middleware

### Key Features

- **Automatic TLS**: Wildcard certificate for `*.${DOMAINNAME}` via Cloudflare DNS challenge (`dns-cloudflare` resolver)
- **Docker provider**: Auto-discovers services from Docker labels via socket proxy
- **Per-service networks**: Each service gets its own frontend network — containers can only talk to Traefik, not to each other
- **Monitoring entrypoint**: Port 8444 with IP allowlist restricted to the `gatus-frontend` subnet for auth-free health checks

### Services

| Container              | Role                                                                                            |
| ---------------------- | ----------------------------------------------------------------------------------------------- |
| `traefik-init`         | One-shot init: creates `acme.json`, chowns `./data/acme` to `3100:3100`, sets `600` permissions |
| `traefik`              | Reverse proxy — routes traffic to all services, manages TLS certificates                        |
| `traefik-docker-proxy` | LinuxServer socket-proxy — read-only Docker API access (`CONTAINERS=1`)                         |

### Config Structure

| Path                           | Purpose                                                                                  |
| ------------------------------ | ---------------------------------------------------------------------------------------- |
| `config/traefik.yml`           | Static configuration — entrypoints, providers, certificate resolvers                     |
| `config/rules/middlewares.yml` | Middleware chains (`chain-auth`, `chain-no-auth`, rate limiting, headers, IP allowlists) |
| `data/acme/acme.json`          | Let's Encrypt certificate store (runtime, `600` permissions)                             |

### Multi-Server Deployment

Traefik runs on multiple servers with compose overrides:

- **svlnas** (TrueNAS) — primary instance, joins all service frontend networks
- **svlazext** — Azure external VM, joins only AdGuard's frontend network
- **svlazextpub** — Azure public VM, joins only hadiscover's frontend network

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for routing and wildcard certificate
- `CF_DNS_API_TOKEN` — Cloudflare API token for DNS challenge TLS certificate issuance

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/traefik` in TrueNAS
2. Create a `svc-app-traefik` group (GID 3100) and user (UID 3100) on the TrueNAS host
3. Create a Cloudflare API token with `Zone:DNS:Edit` permissions for your domain
4. Set `CF_DNS_API_TOKEN` and `DOMAINNAME` in `secret.sops.env`
5. Deploy — Traefik requests a wildcard certificate on first start (check `docker logs traefik` for ACME status)
6. Point your domain's DNS to the host IP (or use split-horizon via AdGuard/Unbound)

## Upgrade Notes

No special upgrade procedures. Traefik handles configuration changes gracefully on restart. Check the [Traefik migration guides](https://doc.traefik.io/traefik/migration/) when upgrading across major versions (e.g. v2 → v3). Image updates are managed by Renovate.
