# Pangolin

[Pangolin](https://github.com/fosrl/pangolin) is an identity-aware VPN and tunneled reverse proxy for remote access, built around WireGuard tunnels and Pangolin-managed resources.

## Why

Pangolin provides a controlled way to expose private resources without publishing each backend service directly. It pairs a dashboard/API with Gerbil WireGuard tunnels and an internal Traefik instance managed by Pangolin, while the dashboard itself stays behind the existing repo Traefik and `chain-auth@file`.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/pangolin/compose.yaml)

## Access

| URL                              | Auth                          | Description                  |
| -------------------------------- | ----------------------------- | ---------------------------- |
| `https://pangolin.${DOMAINNAME}` | Traefik `chain-auth@file`     | Pangolin dashboard and API   |

Gerbil also publishes the ports Pangolin uses for tunnels and public resources. These optional overrides can be added to the decrypted `.env` when the defaults need to change:

| Variable                  | Default | Protocol | Purpose                           |
| ------------------------- | ------- | -------- | --------------------------------- |
| `GERBIL_WIREGUARD_PORT`   | `51820` | UDP      | WireGuard tunnel endpoint         |
| `GERBIL_CLIENTS_PORT`     | `21820` | UDP      | Gerbil client tunnel endpoint     |
| `PANGOLIN_HTTP_PORT`      | `8088`  | TCP      | Pangolin-managed HTTP entrypoint  |
| `PANGOLIN_HTTPS_PORT`     | `8448`  | TCP      | Pangolin-managed HTTPS entrypoint |
| `PANGOLIN_MEM_LIMIT`      | `1024m` | n/a      | Pangolin dashboard/API memory cap |
| `GERBIL_MEM_LIMIT`        | `256m`  | n/a      | Gerbil tunnel service memory cap  |
| `TRAEFIK_MEM_LIMIT`       | `512m`  | n/a      | Internal Traefik memory cap       |

## Architecture

- **Images**: [fosrl/pangolin](https://github.com/fosrl/pangolin), [fosrl/gerbil](https://github.com/fosrl/gerbil), [Traefik](https://traefik.io/), [busybox](https://hub.docker.com/_/busybox)
- **Deployment target**: primary TrueNAS host
- **Runtime user**: UID/GID `3127` (`svc-app-pangolin`) for `pangolin` and `pangolin-traefik`
- **Networks**: `pangolin-frontend` (repo Traefik-facing), `pangolin-backend` (internal)
- **Reverse proxy**: repo Traefik routes `https://pangolin.${DOMAINNAME}` to `pangolin:3001` with `chain-auth@file`
- **Config model**: `./config` contains read-only templates; `pangolin-init` renders them into `./data/config`
- **Runtime data**: `./data` stores generated config, database files, keys, ACME state, and logs

### Services

| Container           | Role                                                                                       |
| ------------------- | ------------------------------------------------------------------------------------------ |
| `pangolin-init`     | One-shot init: renders config templates into `./data/config` and chowns runtime data only |
| `pangolin`          | Dashboard/API service running as `3127:3127`                                               |
| `gerbil`            | WireGuard tunnel service; runs as root with `NET_ADMIN` and `/dev/net/tun`                 |
| `pangolin-traefik`  | Pangolin-managed internal Traefik sharing Gerbil's network namespace                       |

### Volumes

| Host Path  | Container Path                         | Mode | Purpose                                      |
| ---------- | -------------------------------------- | ---- | -------------------------------------------- |
| `./config` | `/config`                              | ro   | Git-tracked config templates                 |
| `./data`   | `/data`                                | rw   | Init-rendered runtime config and state       |
| `./data/config` | `/app/config`, `/var/config`      | rw   | Pangolin/Gerbil runtime config, DB, and keys |
| `./data/config/traefik` | `/etc/traefik`           | ro   | Rendered internal Traefik config             |
| `./data/config/letsencrypt` | `/letsencrypt`       | rw   | Internal Traefik ACME state                  |

No git-tracked config is chowned. Ownership changes are limited to `./data`.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

| Variable        | Description                                 |
| --------------- | ------------------------------------------- |
| `DOMAINNAME`    | Base domain for Pangolin and Traefik routes |
| `SERVER_SECRET` | Pangolin server secret                      |
| `ACME_EMAIL`    | Let's Encrypt account email                 |

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/pangolin` in TrueNAS.
2. Create the `svc-app-pangolin` group (GID 3127), then user (UID 3127) on the TrueNAS host. See [Infrastructure § TrueNAS Host Setup](../INFRASTRUCTURE.md#truenas-host-setup) for the standard creation order.
3. Ensure WireGuard/TUN kernel support is available and `/dev/net/tun` exists on the host.
4. Populate `secret.sops.env` with `DOMAINNAME`, `SERVER_SECRET`, and `ACME_EMAIL`, then encrypt it:

    ```sh
    sops -e -i services/pangolin/secret.sops.env
    ```

5. Expose or forward Gerbil's UDP ports and the configured Pangolin HTTP/HTTPS host ports if Pangolin will serve public resources.
6. Deploy the stack, then visit `https://pangolin.${DOMAINNAME}`.

## Upgrade Notes

- Image updates are managed by Renovate.
- Pangolin runtime state lives under `./data`; protect it with the `vm-pool/apps/services/pangolin` dataset snapshots.
- Review Pangolin and Gerbil release notes before major upgrades because tunnel behavior, config schema, or managed Traefik integration may change.
