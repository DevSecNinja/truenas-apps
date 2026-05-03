# OpenClaw

OpenClaw is a self-hosted personal AI assistant and gateway for local and cloud model providers.

## Why

OpenClaw provides a private gateway for AI assistant workflows while keeping state in a TrueNAS-hosted dataset. The intended cloud provider for this deployment is **Azure OpenAI / Azure AI Foundry**, configured as a custom provider in `openclaw.json` (`models.providers.azure-openai`) with `${AZURE_OPENAI_API_KEY}` / `${AZURE_OPENAI_ENDPOINT}` substitution. Local model providers such as Ollama or LM Studio remain reachable via `host.docker.internal`. No GPU passthrough is configured for this stack.

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

| Container       | Role                                                                        |
| --------------- | --------------------------------------------------------------------------- |
| `openclaw-init` | One-shot init: chowns `./data` to `3127:3127` before startup                |
| `openclaw`      | OpenClaw gateway process with persistent state under `/home/node/.openclaw` |

### Volumes

| Host path | Container path         | Purpose                                                           |
| --------- | ---------------------- | ----------------------------------------------------------------- |
| `./data`  | `/home/node/.openclaw` | OpenClaw gateway config, conversation history, and workspace data |

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

| Variable                 | Purpose                                                              |
| ------------------------ | -------------------------------------------------------------------- |
| `DOMAINNAME`             | Base domain for Traefik routing                                      |
| `OPENCLAW_GATEWAY_TOKEN` | OpenClaw gateway shared secret (`openssl rand -base64 32`)           |
| `AZURE_OPENAI_API_KEY`   | Azure OpenAI / Foundry API key, referenced from `openclaw.json`      |
| `AZURE_OPENAI_ENDPOINT`  | Azure OpenAI / Foundry endpoint URL, referenced from `openclaw.json` |

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/openclaw` in TrueNAS
2. Create the `svc-app-openclaw` group and user with UID/GID `3127`
3. Generate `OPENCLAW_GATEWAY_TOKEN` (`openssl rand -base64 32`) and populate the Azure OpenAI / Foundry credentials in `secret.sops.env`
4. Deploy the stack and confirm the `openclaw-init` container completes successfully
5. Open `https://openclaw.${DOMAINNAME}` and complete OpenClaw onboarding; for Azure OpenAI / Foundry, add a `models.providers.azure-openai` entry referencing `${AZURE_OPENAI_API_KEY}` and `${AZURE_OPENAI_ENDPOINT}` in `./data/openclaw.json`

## Upgrade Notes

OpenClaw application state is stored under `./data`. Image updates are managed by Renovate; review upstream release notes before deploying major changes and keep a dataset snapshot before upgrades.
