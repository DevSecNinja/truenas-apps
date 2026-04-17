# Frigate

Frigate is an open-source NVR (network video recorder) with real-time AI object detection for security cameras.

## Why

Traditional NVRs record continuously and leave you to scrub through hours of footage. Frigate uses AI object detection (via Google Coral TPU or CPU) to identify people, cars, animals, and other objects in real time — so you only get notified when something meaningful happens. It integrates natively with Home Assistant and publishes MQTT events to Mosquitto, making it the backbone of camera-based automations. Self-hosting keeps your camera feeds entirely on-network with no cloud dependency.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/frigate/compose.yaml)

## Access

| URL                             | Description                   |
| ------------------------------- | ----------------------------- |
| `https://frigate.${DOMAINNAME}` | Web UI (Traefik forward-auth) |

| Port | Protocol  | Description      |
| ---- | --------- | ---------------- |
| 8554 | RTSP      | RTSP restreaming |
| 8555 | TCP + UDP | WebRTC           |

## Architecture

- **Image**: [blakeblackshear/frigate](https://github.com/blakeblackshear/frigate)
- **Networks**: `frigate-frontend` (Traefik-facing), `iot-backend` (internal IoT communication — connects to Mosquitto for MQTT events)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware

### Root Container Exception

Frigate runs as root because it requires direct access to hardware devices (GPU for detection, optional Coral TPU) and manages its own internal processes (nginx, go2rtc, detector workers). `read_only` and `user:` are therefore omitted. `cap_drop: ALL` and `no-new-privileges` are still applied.

### Init Container

`frigate-init` seeds a minimal config file from `./config/config.yml` into `./data/config/` on first deploy only (`cp -n` — never overwrites). The config lives in `./data/` because Frigate's built-in UI config editor needs write access.

### Services

| Container      | Role                                                              |
| -------------- | ----------------------------------------------------------------- |
| `frigate-init` | One-shot init: seeds `config.yml` into `./data/config/` (`cp -n`) |
| `frigate`      | NVR with AI object detection, RTSP restreaming, and WebRTC        |

### Hardware Acceleration

The compose file includes commented-out `devices:` directives for Intel QuickSync (`/dev/dri`) and Google Coral TPU (`/dev/bus/usb`). Uncomment the appropriate section for your hardware.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/frigate` in TrueNAS
2. Deploy the stack — no TrueNAS service account needed (runs as root)
3. (Optional) Uncomment the `devices:` section in `compose.yaml` for GPU or Coral TPU hardware acceleration
4. Configure cameras in the Frigate web UI
5. Add the Frigate integration to Home Assistant

## Upgrade Notes

Review the [Frigate release notes](https://github.com/blakeblackshear/frigate/releases) before major version upgrades — config schema changes are common. The init container uses `cp -n`, so config updates from the repo are only applied on first deploy. Subsequent config changes should be made through the Frigate UI.
