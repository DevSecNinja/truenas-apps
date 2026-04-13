# Spottarr

Spottarr is a Spotnet Usenet indexer that reads Spotnet posts from Usenet and serves them as an indexer to the arr stack via Newznab API.

## Why

Spotnet is a Dutch Usenet indexing system. Spottarr indexes Spotnet posts locally and exposes them as a standard Newznab indexer, letting Sonarr, Radarr, and Lidarr search Spotnet content alongside other indexers managed by Prowlarr — without needing a separate Spotnet client.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/spottarr/compose.yaml)

## Access

| URL                              | Description                   |
| -------------------------------- | ----------------------------- |
| `https://spottarr.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [spottarr/spottarr](https://github.com/Spottarr/Spottarr) (.NET application)
- **User/Group**: `3117:3117` (`svc-app-spottarr`) — runs directly as non-root, no s6-overlay
- **Networks**: `arr-egress` (macvlan, default route), `spottarr-frontend` (bridge, Traefik-facing, `internal: true`), `arr-stack-backend` (internal bridge for arr inter-communication)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware

### Services

| Container        | Role                                          |
| ---------------- | --------------------------------------------- |
| `spottarr-chown` | One-shot init: chowns `./data` to `3117:3117` |
| `spottarr`       | Spotnet indexer with Newznab API              |

### Networking

Uses the arr-stack egress pattern — `arr-egress` is listed first for default route, `spottarr-frontend` is `internal: true`.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing
- `EGRESS_IP` / `EGRESS_MAC` — static IP and MAC for the arr-egress macvlan network
- `SPOTTARR_USENET_*` — Usenet server credentials (hostname, username, password, port, TLS, max connections)
- `SPOTTARR_SPOTNET_*` — Spotnet settings (retrieve-after date, batch size, retention days)

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/spottarr` in TrueNAS
2. Create a `svc-app-spottarr` group (GID 3117) and user (UID 3117) on the TrueNAS host
3. Configure Usenet provider credentials in `secret.sops.env`
4. Deploy — Spottarr starts indexing Spotnet posts immediately
5. Add Spottarr as a Newznab indexer in Prowlarr (URL: `http://spottarr:8383`)

## Upgrade Notes

No special upgrade procedures. Image updates are managed by Renovate.
