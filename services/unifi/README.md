# Unifi Network Application

The Unifi Network Application is Ubiquiti's network controller for managing UniFi access points, switches, and gateways.

## Why

Ubiquiti's cloud-hosted controller requires an internet connection and sends your network data to their servers. Self-hosting the controller keeps management local, enables advanced features like guest portals and traffic analytics, and ensures your network configuration remains accessible even during internet outages. It also allows you to use automated backups with encryption.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/unifi/compose.yaml)

## Access

| URL                                 | Description                                                        |
| ----------------------------------- | ------------------------------------------------------------------ |
| `https://unifi.${DOMAINNAME}`       | Controller UI (no forward-auth — Unifi has its own authentication) |
| `https://unifi-guest.${DOMAINNAME}` | Guest WiFi captive portal (no auth — must be accessible to guests) |

## Architecture

- **Images**: [linuxserver/unifi-network-application](https://github.com/linuxserver/docker-unifi-network-application) (s6-overlay), [mongo](https://hub.docker.com/_/mongo), [tiredofit/db-backup](https://github.com/tiredofit/docker-db-backup)
- **User/Group**: `PUID=3108` / `PGID=3108` (`svc-app-unifi`)
- **Networks**: `unifi-frontend` (Traefik-facing), `unifi-backend` (internal — MongoDB)
- **Reverse proxy**: Traefik with `chain-no-auth@file` middleware — Unifi has its own authentication. Uses `insecure-skip-verify` server transport because Unifi serves HTTPS on port 8443 with a self-signed certificate.
- **pids_limit**: `300` — UniFi's JVM spawns 150+ threads at runtime

### Ports

| Port      | Protocol | Purpose                           |
| --------- | -------- | --------------------------------- |
| 3478      | UDP      | STUN (device discovery)           |
| 10001     | UDP      | Device discovery                  |
| 8080      | TCP      | Device ↔ controller communication |
| 6789      | TCP      | Mobile speed test                 |
| 2221 → 22 | TCP      | SSH access                        |

### Services

| Container         | Role                                                     |
| ----------------- | -------------------------------------------------------- |
| `unifi-db`        | MongoDB database                                         |
| `unifi-db-backup` | One-shot nightly backup sidecar (restarted by `dccd.sh`) |
| `unifi`           | Unifi Network Application (s6-overlay)                   |

### s6-overlay Exceptions

The LinuxServer Unifi image uses s6-overlay. Both `read_only` and `user:` are omitted, and `cap_drop: ALL` is also omitted because s6-overlay and the Java-based Unifi application need extensive writable paths beyond what can be covered by tmpfs mounts.

### Database Backup

`unifi-db-backup` uses `tiredofit/db-backup` in `MODE=MANUAL` with `MANUAL_RUN_FOREVER=FALSE`. Backups are ZSTD-compressed, SHA1-checksummed, AES-encrypted with `DB_ENC_PASSPHRASE`, and retained for 48 hours. Unifi also writes its own auto-backups to `./backups/autobackup/`.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing
- `UNIFI_MONGO_ROOT_PASS` — MongoDB root password
- `UNIFI_MONGO_PASS` — MongoDB application password
- `DB_ENC_PASSPHRASE` — encryption passphrase for database backups
- `NOTIFICATIONS_EMAIL_*` — SMTP settings for backup notifications

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/unifi` in TrueNAS
2. Create a `svc-app-unifi` group (GID 3108) and user (UID 3108) on the TrueNAS host
3. Deploy — MongoDB initializes automatically via `config/init-mongo.sh`
4. Complete the Unifi setup wizard in the web UI
5. Adopt your Unifi devices (set the inform URL to `http://<host-ip>:8080/inform`)

## Upgrade Notes

MongoDB does not support automatic major-version upgrades. Before upgrading to a new major version, set the feature compatibility version on the current release:

```sh
export MONGO_VERSION=8.2  # Set to your CURRENT MongoDB major version
docker compose exec unifi-db mongosh --eval 'db.adminCommand({ setFeatureCompatibilityVersion: "'$MONGO_VERSION'" })'
```

Then update the image tag and redeploy. Check the [MongoDB upgrade docs](https://www.mongodb.com/docs/manual/release-notes/) for breaking changes between major versions.
