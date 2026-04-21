# Cloudflared

Cloudflared is a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) agent that exposes services to the internet via Cloudflare's edge network — without opening inbound ports on the host.

## Why

Traditional reverse proxy setups (Traefik with published ports) require inbound firewall rules and expose the host directly to the internet. Cloudflare Tunnel eliminates this by establishing an outbound-only connection from the cloudflared agent to Cloudflare's edge. External requests are routed through Cloudflare's network to the local service, keeping the host completely off the public internet. This is the preferred method for exposing services that need to be publicly reachable without authentication (e.g., public APIs).

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/cloudflared/compose.yaml)

## Access

Cloudflared itself has no web UI. Tunnel routing rules are managed in the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com/).

### Currently Tunnelled Services

| Public URL                   | Backend target               | Service        |
| ---------------------------- | ---------------------------- | -------------- |
| `https://api.hadiscover.com` | `http://hadiscover-api:8000` | hadiscover API |

## Architecture

- **Image**: [cloudflare/cloudflared](https://github.com/cloudflare/cloudflared) (official)
- **Networks**: `hadiscover-frontend` (shared with hadiscover-api — created by the hadiscover compose stack)
- **No dedicated UID/GID**: The official image runs as the built-in `nonroot` user (UID 65532). No writable volumes are mounted, so there is no file ownership to manage.
- **No init container**: No writable volumes means no chown is needed.
- **Tunnel mode**: Token-based (`TUNNEL_TOKEN`). Routing rules (which hostname maps to which backend) are configured in the Cloudflare Zero Trust dashboard, not in local config files.
- **Metrics**: Exposes a metrics endpoint on port 2000 (container-internal only, not published) for the health check.

### Services

| Container     | Role                                                        |
| ------------- | ----------------------------------------------------------- |
| `cloudflared` | Cloudflare Tunnel agent — maintains outbound tunnel to edge |

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `TUNNEL_TOKEN` — Cloudflare Tunnel authentication token (generated in Zero Trust dashboard)

## First-Run Setup

1. Create a Cloudflare Tunnel in the [Zero Trust dashboard](https://dash.cloudflare.com/one/) under Networks -> Connectors
   1. Make sure to select Cloudflared as the tunnel type
   2. Provide a name for the tunnel, e.g. the hostname of the machine
   3. On the 'Install and run connectors' step, copy the token hidden in the install command and click next.
   4. You will now get to the 'Route tunnel' step. Configure tunnel routing rules (e.g., `api.hadiscover.com` → `http://hadiscover-api:8000`) and hit the Setup button.
   5. Now the tunnel should be created. Set `TUNNEL_TOKEN` in `secret.sops.env` based on the tunnel token gathered at step 1.3
2. Deploy — cloudflared establishes the tunnel and begins proxying traffic

No TrueNAS dataset, service account, or init container is needed — this service is entirely stateless.

## Upgrade Notes

No special upgrade procedures. Image updates are managed by Renovate.
