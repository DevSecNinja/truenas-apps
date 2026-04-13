# Radarr

Radarr is a movie collection manager that automates searching, downloading, and organizing your movie library.

## Why

Manually searching for movie releases across indexers and managing downloads is repetitive. Radarr automates the entire pipeline — add a movie to your wanted list, and it searches indexers, sends downloads to your client, imports the completed file with proper naming, and notifies Plex to update its library. Combined with Prowlarr for indexer management and hardlinks for zero-copy imports, it's a fully hands-off workflow.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/radarr/compose.yaml)

## Access

| URL                            | Description                                                 |
| ------------------------------ | ----------------------------------------------------------- |
| `https://radarr.${DOMAINNAME}` | Web UI (no forward-auth — Radarr uses `chain-no-auth@file`) |

## Architecture

- **Image**: [linuxserver/radarr](https://github.com/linuxserver/docker-radarr) (s6-overlay)
- **User/Group**: `PUID=3110` / `PGID=3200` (`svc-app-radarr:media`)
- **Networks**: `arr-egress` (macvlan, default route), `radarr-frontend` (bridge, Traefik-facing, `internal: true`), `arr-stack-backend` (internal bridge for arr inter-communication)
- **Reverse proxy**: Traefik with `chain-no-auth@file` middleware
- **Media mount**: `/mnt/archive-pool/content` → `/data` — same filesystem for hardlink support

### s6-overlay Exceptions

See [Architecture](../ARCHITECTURE.md) for the full rationale. `read_only` and `user:` are omitted; `cap_add` includes `CHOWN`, `SETUID`, `SETGID`, `SETPCAP`.

### Networking

Uses the arr-stack egress pattern. The `hostname: radarr` directive makes the container identifiable on the egress network (visible in ARP/mDNS and UniFi client list).

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing
- `EGRESS_IP` / `EGRESS_MAC` — static IP and MAC for the arr-egress macvlan network

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/radarr` in TrueNAS
2. Create a `svc-app-radarr` group (GID 3110) and user (UID 3110, primary group `media` GID 3200) on the TrueNAS host
3. Deploy and configure root folders, download clients, and quality profiles in the web UI

## Upgrade Notes

No special upgrade procedures. s6-overlay and Radarr handle migrations automatically. Image updates are managed by Renovate.
