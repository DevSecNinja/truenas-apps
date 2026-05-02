# OpenClaw

OpenClaw is a self-hosted personal AI assistant and gateway for local and cloud model providers.

## Why

OpenClaw provides a private gateway for AI assistant workflows while keeping state in a TrueNAS-hosted dataset. It can connect to local model providers such as Ollama or LM Studio via `host.docker.internal`, and cloud providers are configured during onboarding. No GPU passthrough is configured for this stack.

## Compose Files

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/openclaw/compose.yaml)
- [secret.sops.env](https://github.com/DevSecNinja/truenas-apps/blob/main/services/openclaw/secret.sops.env)

## Access

| URL                              | Description                                             |
| -------------------------------- | ------------------------------------------------------- |
| `https://openclaw.${DOMAINNAME}` | Web UI / gateway (Traefik forward-auth + gateway token) |

## Architecture

- **Image**: [openclaw/openclaw](https://github.com/openclaw/openclaw)
- **User/Group**: `3127:3127` (`svc-app-openclaw`)
- **Networks**: `openclaw-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **State**: `./data` is mounted at `/home/node/.openclaw`
- **Init image**: `docker.io/library/busybox:1.37.0`

### Services

| Container        | Role                                                                        |
| ---------------- | --------------------------------------------------------------------------- |
| `openclaw-init`  | One-shot init: chowns `./data` to `3127:3127` before startup                |
| `openclaw`       | OpenClaw gateway process with persistent state under `/home/node/.openclaw` |

### Volumes

| Host path | Container path        | Purpose                                             |
| --------- | --------------------- | --------------------------------------------------- |
| `./data`  | `/home/node/.openclaw` | OpenClaw gateway config, conversation history, and workspace data |

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

| Variable                            | Purpose                                             |
| ----------------------------------- | --------------------------------------------------- |
| `DOMAINNAME`                        | Base domain for Traefik routing                     |
| `OPENCLAW_GATEWAY_TOKEN`            | OpenClaw gateway access token                       |
| `OPENCLAW_ALLOW_INSECURE_PRIVATE_WS` | Allows private WebSocket connections when required |
| `CLAUDE_AI_SESSION_KEY`             | Claude AI session key used by OpenClaw              |
| `CLAUDE_WEB_SESSION_KEY`            | Claude web session key used by OpenClaw             |
| `CLAUDE_WEB_COOKIE`                 | Claude web cookie used by OpenClaw                  |

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/openclaw` in TrueNAS
2. Create the `svc-app-openclaw` group and user with UID/GID `3127`
3. Populate `OPENCLAW_GATEWAY_TOKEN` and any provider session secrets in `secret.sops.env`
4. Deploy the stack and confirm the `openclaw-init` container completes successfully
5. Open `https://openclaw.${DOMAINNAME}` and complete OpenClaw onboarding for local or cloud providers

## Upgrade Notes

OpenClaw application state is stored under `./data`. Image updates are managed by Renovate; review upstream release notes before deploying major changes and keep a dataset snapshot before upgrades.
