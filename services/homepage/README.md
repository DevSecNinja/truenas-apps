# Homepage

Homepage is a modern, customizable application dashboard for your home lab services.

## Why

With 20+ services running, you need a single entry point that shows what's available and whether it's healthy. Homepage auto-discovers services via Docker labels and displays service status, widgets, and quick links — all without storing state. It reads config from git-tracked YAML files, so the dashboard definition is version-controlled alongside everything else.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/homepage/compose.yaml)

## Access

| URL                          | Description                                                      |
| ---------------------------- | ---------------------------------------------------------------- |
| `https://apps.${DOMAINNAME}` | Dashboard (no forward-auth — Homepage uses `chain-no-auth@file`) |

## Architecture

- **Image**: [gethomepage/homepage](https://github.com/gethomepage/homepage) (Next.js)
- **User/Group**: `3102:3102` (`svc-app-homepage`)
- **Networks**: `homepage-frontend` (Traefik-facing), `homepage-backend` (internal — Docker socket proxy)
- **Reverse proxy**: Traefik with `chain-no-auth@file` middleware

### Services

| Container               | Role                                                                                             |
| ----------------------- | ------------------------------------------------------------------------------------------------ |
| `homepage`              | Dashboard web UI — reads config from `./config` (`:ro`) and discovers services via Docker labels |
| `homepage-docker-proxy` | LinuxServer socket-proxy — read-only Docker API access (`CONTAINERS=1`, `POST=0`)                |

### Config Management

Homepage's config files (`settings.yaml`, `services.yaml`, `widgets.yaml`, etc.) are git-tracked under `./config/` and mounted read-only. No init container is needed — config files are world-readable from the git checkout (`644`), so the non-root homepage process can read them without ownership changes.

### Docker Socket Proxy

Homepage never mounts the Docker socket directly. A dedicated socket proxy provides read-only container metadata access on the internal backend network.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing and service URL generation

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/homepage` in TrueNAS
2. Create a `svc-app-homepage` group (GID 3102) and user (UID 3102) on the TrueNAS host
3. Deploy — Homepage auto-discovers services from Docker labels (`homepage.*`)
4. Customize `config/services.yaml` and `config/settings.yaml` as needed

## Upgrade Notes

No special upgrade procedures. Image updates are managed by Renovate.
