# Folding@home

[Folding@home](https://foldingathome.org/) is a distributed computing project that simulates protein dynamics — including protein folding and the movements of proteins implicated in a variety of diseases — to help researchers find new therapies.

## Why

`svlazext` is an Azure ARM64 VM (Standard D2ps v6, 2 vCPUs, 8 GiB RAM) and otherwise idles outside DNS / Cloudflare-tunnel work. Donating its spare CPU cycles to scientific research makes practical use of that headroom while keeping the workload entirely outbound (no inbound firewall changes needed).

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/foldingathome/compose.yaml)

## Access

| URL                                   | Description                              |
| ------------------------------------- | ---------------------------------------- |
| `https://foldingathome.${DOMAINNAME}` | Web control UI (Traefik forward-auth)    |

## Architecture

- **Image**: [lscr.io/linuxserver/foldingathome](https://docs.linuxserver.io/images/docker-foldingathome/) — multi-arch image with an arm64 build, suitable for the ARM64 svlazext VM
- **Runtime**: s6-overlay (LinuxServer image — see [ARCHITECTURE.md § s6-overlay exceptions](../../docs/ARCHITECTURE.md))
- **User/Group**: `3127:3127` (`svc-app-foldingathome`) — set via `PUID` / `PGID`
- **Networks**: `foldingathome-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik (svlazext instance) with `chain-auth@file` middleware
- **Persistent state**: `./data/config` — FAH client configuration, slot state, and current work-unit checkpoints

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing

The donor name, team number, and passkey are configured through the FAH web UI on first run (see below) and persisted to `./data/config`, not in the compose env.

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/foldingathome` (or the equivalent path on `svlazext`) and chown it to `3127:3127`
2. Create a `svc-app-foldingathome` group (GID 3127) and user (UID 3127) on the host
3. Deploy: `dccd.sh -S svlazext -a foldingathome` (or rely on the regular cron pull)
4. Visit `https://foldingathome.${DOMAINNAME}` and configure your donor name, team, passkey, and folding power level in the web UI

## Resource Tuning

The default `MEM_LIMIT` of 6144 MB leaves ~2 GiB for the host on the 8 GiB VM. Override via `compose.env` or shell env if you want to dedicate more or less memory to folding. The FAH client respects `cgroup` CPU limits, so co-located DNS / Traefik containers continue to receive their share of CPU under load.

## Upgrade Notes

No special upgrade procedure. The LinuxServer image is updated by Renovate; FAH state under `./data/config` is preserved across upgrades.
