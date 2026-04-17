# wmbusmeters

wmbusmeters is a tool for reading wireless M-Bus (wM-Bus) telegrams from smart meters (water, gas, electricity, heat) and publishing the readings via MQTT.

## Why

Many European smart meters transmit their readings over wireless M-Bus. wmbusmeters listens to these telegrams via a USB radio dongle, decodes them, and publishes structured JSON readings to Mosquitto via MQTT. Home Assistant can then consume these readings for energy monitoring dashboards and automations. Self-hosting keeps your utility data private and eliminates any dependency on the meter vendor's cloud portal.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/wmbusmeters/compose.yaml)

## Access

wmbusmeters has no web UI. It runs as a background service that reads meter telegrams and publishes them to Mosquitto via MQTT on the `iot-backend` Docker network.

## Architecture

- **Image**: [weetmuts/wmbusmeters](https://hub.docker.com/r/weetmuts/wmbusmeters)
- **User/Group**: `3123:3123` (`svc-app-wmbusmeters`)
- **Networks**: `iot-backend` (internal IoT communication — publishes readings to Mosquitto)
- **Reverse proxy**: None — no web UI
- **USB device**: Requires a wM-Bus radio dongle (e.g. WiMOD iM871A) passed through via the `devices:` directive

### Security

- `read_only: true` with config mounted `:ro`
- `user: "3123:3123"` — runs as non-root
- USB device must be accessible by the container UID — use udev rules or set device permissions on the host

### Init Container

`wmbusmeters-init` chowns `./data/logs` and `./data/state` to UID `3123:3123` so the non-root container can write log and state files.

### Services

| Container          | Role                                                       |
| ------------------ | ---------------------------------------------------------- |
| `wmbusmeters-init` | One-shot init: chowns `./data` to `3123:3123`              |
| `wmbusmeters`      | Reads wM-Bus telegrams and publishes readings to Mosquitto |

### Configuration

- `config/wmbusmeters.conf` — main configuration (mounted `:ro`). Configures the radio device, log level, MQTT output via `mosquitto_pub` shell command.
- `config/meters.d/` — meter definition files (mounted `:ro`). Add one file per meter with the meter name, type, ID, and encryption key.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain (used for consistency; not required by wmbusmeters itself)

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/wmbusmeters` in TrueNAS
2. Create TrueNAS service account `svc-app-wmbusmeters` (UID/GID 3123)
3. Uncomment and adjust the `devices:` section in `compose.yaml` with the correct USB device path (e.g. `/dev/ttyUSB0`)
4. Add meter definition files to `config/meters.d/` — see the [wmbusmeters documentation](https://github.com/wmbusmeters/wmbusmeters) for format
5. Deploy the stack
6. Verify readings appear in Mosquitto (e.g. via `mosquitto_sub -h localhost -t "wmbusmeters/#"`)
7. Configure Home Assistant MQTT sensors to consume the meter readings

## Upgrade Notes

Review the [wmbusmeters changelog](https://github.com/wmbusmeters/wmbusmeters/releases) before upgrading — meter driver changes may affect decoding of specific meter models.
