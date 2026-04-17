# Matter Server

Python Matter Server is a WebSocket-based bridge between Home Assistant's Matter integration and Matter/Thread smart home devices.

## Why

Matter is the emerging open standard for smart home device interoperability. The Python Matter Server handles the low-level Matter protocol (device commissioning, fabric management, Thread border router communication) and exposes a WebSocket API that Home Assistant connects to. Running it as a dedicated container keeps the Matter stack isolated and independently updatable, while `network_mode: host` ensures reliable mDNS device discovery and IPv6 Thread communication.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/matter-server/compose.yaml)

## Access

| Endpoint                 | Protocol  | Description                                        |
| ------------------------ | --------- | -------------------------------------------------- |
| `ws://localhost:5580/ws` | WebSocket | Home Assistant connects via the Matter integration |

Matter Server has no web UI. Home Assistant connects to it via WebSocket on port 5580. Configure the URL in HA's Matter integration settings.

## Architecture

- **Image**: [home-assistant-libs/python-matter-server](https://github.com/home-assistant-libs/python-matter-server)
- **User/Group**: `3124:3124` (`svc-app-matter`)
- **Network mode**: `host` — required for mDNS device discovery (multicast DNS) and IPv6 Thread border router communication. Bridge networking isolates the container from both multicast and IPv6 link-local traffic, preventing device pairing and communication.
- **Reverse proxy**: None — no web UI

### Security

- `read_only: true` with tmpfs for `/tmp`
- `user: "3124:3124"` — runs as non-root
- `cap_add: NET_RAW` — required for mDNS multicast on the host network

### Init Container

`matter-server-init` chowns `./data` to UID `3124:3124` so the non-root container can write fabric and device data.

### Services

| Container            | Role                                              |
| -------------------- | ------------------------------------------------- |
| `matter-server-init` | One-shot init: chowns `./data` to `3124:3124`     |
| `matter-server`      | Matter/Thread bridge — WebSocket API on port 5580 |

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain (used for consistency; not required by Matter Server itself)

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/matter-server` in TrueNAS
2. Create TrueNAS service account `svc-app-matter` (UID/GID 3124)
3. Deploy the stack
4. In Home Assistant, add the Matter integration and point it to `ws://localhost:5580/ws`
5. Commission Matter devices through the Home Assistant UI

## Upgrade Notes

Review the [python-matter-server changelog](https://github.com/home-assistant-libs/python-matter-server/releases) before upgrading. Major version bumps may require re-commissioning devices or updating the Matter integration in HA.
