# Mosquitto

Eclipse Mosquitto is a lightweight open-source MQTT broker, widely used for IoT messaging.

## Why

MQTT is the standard messaging protocol for IoT devices. Mosquitto provides a reliable, low-overhead broker that connects Home Assistant, ESPHome devices, Frigate, wmbusmeters, and other IoT services on the internal `iot-backend` Docker network. Self-hosting keeps all IoT traffic local with no cloud dependency.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/mosquitto/compose.yaml)

## Access

| Port | Protocol | Description                                   |
| ---- | -------- | --------------------------------------------- |
| 1883 | MQTT     | Published to LAN for direct IoT device access |

Mosquitto has no web UI. It is accessible via MQTT clients on the LAN (port 1883) and by containers on the `iot-backend` network.

## Architecture

- **Image**: [eclipse-mosquitto](https://hub.docker.com/_/eclipse-mosquitto)
- **Networks**: `iot-backend` (internal bridge for IoT service communication)
- **Reverse proxy**: None — MQTT is not an HTTP service
- **Init container**: `mosquitto-init` chowns `./data/data` and `./data/log` to UID 3122

### Security

- `read_only: true` with config mounted `:ro`
- `user: "3122:3122"` — runs as non-root
- Anonymous access is enabled by default since Mosquitto is only reachable on the internal Docker network and published LAN port. See `config/mosquitto.conf` to enable password authentication.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain (used for consistency; not required by Mosquitto itself)

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/mosquitto` in TrueNAS
2. Create TrueNAS service account `svc-app-mosquitto` (UID/GID 3122)
3. Deploy the stack
4. Configure Home Assistant's MQTT integration to connect to `mosquitto:1883`

## Upgrade Notes

Mosquitto follows semantic versioning. Review the [changelog](https://mosquitto.org/ChangeLog.txt) before major version upgrades.
