# Home Assistant

Home Assistant is an open-source home automation platform that integrates with thousands of smart home devices and services.

## Why

Home Assistant consolidates control of all your smart home devices — lights, sensors, locks, thermostats, media players — into a single local interface. Running it locally means automations execute without internet latency or cloud dependency, and your device data stays on your network. The self-hosted approach also avoids vendor lock-in from closed-ecosystem hubs.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/home-assistant/compose.yaml)

## Access

| URL                                    | Description                                                          |
| -------------------------------------- | -------------------------------------------------------------------- |
| `https://home-assistant.${DOMAINNAME}` | Web UI and API (no forward-auth — HA handles its own authentication) |

## Architecture

- **Image**: [home-assistant/home-assistant](https://github.com/home-assistant/core) (s6-overlay)
- **Networks**: `home-assistant-frontend` (Traefik-facing), `iot-backend` (internal IoT communication — connects to Mosquitto, ESPHome, Frigate, wmbusmeters)
- **Reverse proxy**: Traefik with `chain-no-auth@file` middleware — HA enforces its own login, MFA, and long-lived access tokens. Forward-auth would break the Companion mobile app's direct OAuth flow.

### s6-overlay Exceptions

Home Assistant uses s6-overlay internally. See [Architecture](../ARCHITECTURE.md) for the full rationale:

- **`user:` is omitted**: s6-overlay starts as root and drops privileges internally
- **`read_only` is omitted**: s6-overlay needs a writable root filesystem
- **`cap_add`**: `CHOWN`, `SETUID`, `SETGID`, `SETPCAP` (standard s6-overlay set) + `NET_RAW` (required by HA's DHCP watcher integration for raw `AF_PACKET` sockets — without it HA logs `[Errno 1] Operation not permitted`)

### Init Container

`home-assistant-init` seeds template config files from `./config` into `./data/config/` on first deploy only (`cp -n` — never overwrites). These templates include `configuration.yaml` (with `http: trusted_proxies` for Traefik), and empty stub files (`automations.yaml`, `scripts.yaml`, `scenes.yaml`) required by HA's `!include` directives. Without these stubs, HA enters recovery mode and ignores the `http:` block.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing
- `NOTIFICATIONS_EMAIL_HOST` — SMTP server hostname for db-backup notifications
- `NOTIFICATIONS_EMAIL_DOMAIN` — SMTP domain
- `NOTIFICATIONS_EMAIL_PORT` — SMTP port
- `NOTIFICATIONS_EMAIL_USERNAME` — SMTP username
- `NOTIFICATIONS_EMAIL_PASSWORD` — SMTP password
- `NOTIFICATIONS_EMAIL_TO` — notification recipient email address
- `NOTIFICATIONS_EMAIL_FROM` — notification sender email address
- `DB_ENC_PASSPHRASE` — encryption passphrase for backup files

## Database Backup

The `home-assistant-db-backup` sidecar (tiredofit/db-backup with s6-overlay) runs a one-shot `sqlite3 .dump` of the Home Assistant recorder database (`home-assistant_v2.db`), producing a consistent SQL snapshot even while HA is running in WAL mode. The backup is compressed with ZSTD and encrypted with `${DB_ENC_PASSPHRASE}`.

- **Mode**: `MANUAL` with `MANUAL_RUN_FOREVER=FALSE` — runs one backup and exits. The nightly CD script (`dccd.sh`) restarts the container fresh each run.
- **Notifications**: Sends email notifications on backup success/failure via SMTP.
- **Storage**: Backups are written to `./backups/db-backup/` (gitignored). Old backups are cleaned up after 48 hours (`DEFAULT_CLEANUP_TIME=2880`).
- **Network**: `network_mode: none` — the backup container has no network access.

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/home-assistant` in TrueNAS
2. Deploy the stack — no TrueNAS service account needed (s6-overlay manages permissions internally)
3. Complete the HA onboarding wizard in the web UI
4. Configure integrations for your smart home devices

## Upgrade Notes

Home Assistant uses the `beta` tag. Review the [release notes](https://www.home-assistant.io/blog/) before deploying major version changes — breaking changes to integrations are common. The init container uses `cp -n`, so config updates from the repo are only applied on first deploy — subsequent config changes should be made through the HA UI or by manually updating `./data/config/`.
