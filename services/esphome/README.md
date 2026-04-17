# ESPHome

ESPHome is a system for managing ESP8266/ESP32 microcontrollers through configuration files and building firmware over-the-air.

## Why

ESPHome provides a web-based dashboard for managing, compiling, and flashing firmware to ESP-based IoT devices (sensors, relays, displays). It integrates natively with Home Assistant via its API, allowing zero-config device discovery. Self-hosting keeps the build pipeline local and firmware updates instant.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/esphome/compose.yaml)

## Access

| URL                             | Description                   |
| ------------------------------- | ----------------------------- |
| `https://esphome.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

## Architecture

- **Image**: [esphome/esphome](https://github.com/esphome/esphome)
- **Networks**: `esphome-frontend` (Traefik-facing), `iot-backend` (internal IoT communication)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware

### Root Container Exception

ESPHome runs as root because it compiles C++ firmware using platformio at runtime, downloads platform packages from the internet, and manages build artifacts across `/config/.esphome/`. This requires extensive filesystem writes. `read_only` and `user:` are therefore omitted. `cap_drop: ALL` and `no-new-privileges` are still applied.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/esphome` in TrueNAS
2. Deploy the stack — no TrueNAS service account needed (runs as root)
3. Access the web UI and add your ESP device configurations
4. ESPHome device configs from the previous HA OS install can be copied into `./data/config/`

## Upgrade Notes

ESPHome releases monthly. Review the [changelog](https://esphome.io/changelog/) before upgrading — new versions may change component syntax.
