# SQLite Web

SQLite Web is a lightweight browser-based database viewer for SQLite databases.

## Why

Home Assistant uses SQLite as its default recorder database. When you need to inspect historical sensor data, debug automations, or verify database contents, SQLite Web provides a convenient read-only web UI — no need to SSH in and run `sqlite3` commands manually. It mounts the HA database as read-only, so there's zero risk of accidental data modification.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/sqlite-web/compose.yaml)

## Access

| URL                                | Description                   |
| ---------------------------------- | ----------------------------- |
| `https://sqlite-web.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [coleifer/sqlite-web](https://hub.docker.com/r/coleifer/sqlite-web)
- **Networks**: `sqlite-web-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **No init container**: The HA database is managed by Home Assistant; this container only reads it

### Security

- `read_only: true` with tmpfs for `/tmp`
- The `-r` flag enables read-only mode in the application
- The HA database is mounted `:ro` from `../home-assistant/data/config`

### Dependency

SQLite Web mounts the Home Assistant data directory. Home Assistant must be deployed first — without the HA database file, the container will fail to start.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing

## First-Run Setup

1. Ensure the `home-assistant` stack is deployed and has run at least once (the recorder database must exist)
2. Deploy the stack — no dataset or service account needed
3. Access the web UI to browse the Home Assistant SQLite database

## Upgrade Notes

No special upgrade procedures. Image updates are managed by Renovate.
