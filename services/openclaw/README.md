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
- **State**: `./data` is mounted at `/home/node/.openclaw`. The gateway config (`./data/openclaw.json`) is seeded from the git-tracked `./config/openclaw.json` template by the init container on first deploy
- **Init image**: `docker.io/library/busybox:1.37.0`

### Services

| Container       | Role                                                                                                                                                               |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `openclaw-init` | One-shot init: chowns `./data` to `3127:3127` and seeds `./data/openclaw.json` from the template on first deploy                                                   |
| `openclaw`      | OpenClaw gateway process with persistent state under `/home/node/.openclaw`. Bundles the full CLI at `node dist/index.js` for ad-hoc use via `docker compose exec` |

### Volumes

| Host path  | Container path         | Purpose                                                                 |
| ---------- | ---------------------- | ----------------------------------------------------------------------- |
| `./data`   | `/home/node/.openclaw` | OpenClaw gateway config, conversation history, and workspace data       |
| `./config` | `/templates` (`:ro`)   | Init-container templates: `init.sh` and the `openclaw.json` seed config |

## Configuration Seeding

The git-tracked template at `./config/openclaw.json` holds the static gateway settings — `gateway.controlUi.allowedOrigins`, `gateway.mode` (set to `local`), and `agents.defaults.workspace`. `${DOMAINNAME}` is substituted from the container env at deploy time so the Control UI accepts the Traefik-fronted origin (`https://openclaw.${DOMAINNAME}`).

`openclaw-init` runs `sh /templates/init.sh`, which:

1. Chowns `./data` to `3127:3127`
2. **On first deploy only** (when `./data/openclaw.json` does not yet exist), substitutes `${VAR}` placeholders from the container env and writes the result to `./data/openclaw.json`

Subsequent deploys leave the live file alone — OpenClaw owns it from then on (hot-reload, Control UI edits, automatic `meta.lastTouchedAt` / `meta.lastTouchedVersion` updates). Those dynamic `meta` fields are deliberately omitted from the template so OpenClaw can populate them on first start.

To apply a template change after first deploy, snapshot the dataset, delete `./data/openclaw.json` on the host, and redeploy. The init container will re-seed from the updated template.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

| Variable                 | Purpose                                                              |
| ------------------------ | -------------------------------------------------------------------- |
| `DOMAINNAME`             | Base domain for Traefik routing                                      |
| `OPENCLAW_GATEWAY_TOKEN` | OpenClaw gateway shared secret (`openssl rand -base64 32`)           |
| `AZURE_OPENAI_API_KEY`   | Azure OpenAI / Foundry API key, referenced from `openclaw.json`      |
| `AZURE_OPENAI_ENDPOINT`  | Azure OpenAI / Foundry endpoint URL, referenced from `openclaw.json` |

## First-Run Setup

Onboarding is handled by the init container — no browser-based wizard is required because the seed config plus SOPS-decrypted secrets cover everything.

1. Create the dataset `vm-pool/apps/services/openclaw` in TrueNAS
2. Create the `svc-app-openclaw` group and user with UID/GID `3127`
3. Generate `OPENCLAW_GATEWAY_TOKEN` (`openssl rand -base64 32`) and populate the Azure OpenAI / Foundry credentials in `secret.sops.env`
4. Deploy the stack — `openclaw-init` chowns `./data` and seeds `./data/openclaw.json` from the template before the gateway starts
5. Open `https://openclaw.${DOMAINNAME}` and paste the gateway token from `.env` into Settings
6. (Optional) Add a `models.providers.azure-openai` entry referencing `${AZURE_OPENAI_API_KEY}` / `${AZURE_OPENAI_ENDPOINT}` in `./data/openclaw.json` (or do it via the Control UI)

## Non-Interactive Onboarding

Two paths are supported depending on operator preference:

- **Pre-seeded config (this stack's default)** — no onboarding step is required. The seed file at `./config/openclaw.json` plus env-var-backed secrets fully configure the gateway before it starts.
- **Manual CLI flow** — for operators who want to inspect runtime state or apply config patches programmatically. The OpenClaw image bundles the full CLI, so commands run inside the running gateway container via `docker compose exec`:

  ```sh
  # Inspect current config
  docker compose exec openclaw node dist/index.js config get

  # Apply a batched config patch (example — set bind mode + gateway mode)
  docker compose exec openclaw node dist/index.js config set --batch-json \
    '[{"path":"gateway.bind","value":"lan"},
      {"path":"gateway.mode","value":"local"}]'

  # Authenticated deep health snapshot
  docker compose exec openclaw node dist/index.js health \
    --token "$OPENCLAW_GATEWAY_TOKEN"

  # Print the dashboard URL
  docker compose exec openclaw node dist/index.js dashboard --no-open
  ```

The upstream `onboard` command must run _before_ the gateway is up and uses a different invocation per [upstream docs](https://docs.openclaw.ai/install/docker):

```sh
docker compose run --rm --no-deps --entrypoint node openclaw \
  dist/index.js onboard --mode local --no-install-daemon
```

Because this stack pre-seeds the config, that step is normally not required.

## Image Scope and Skill Binaries

This stack uses the prebuilt `ghcr.io/openclaw/openclaw` image, which ships only the gateway and Node runtime.

Per the upstream [Docker VM Runtime guide](https://docs.openclaw.ai/install/docker-vm-runtime), skill binaries that depend on host-side CLI tools (e.g. Gmail via `gog` / `gogcli`, Google Places via `goplaces`, WhatsApp via `wacli`) **must be baked into the image at build time** because runtime installs are wiped on container restart.

For this homelab the supported scope is the **gateway only** with Azure OpenAI / Azure AI Foundry as the cloud provider, plus local providers (Ollama / LM Studio) reachable over `host.docker.internal`. Channels and skills that require additional baked-in binaries are out of scope and would require switching to a custom-built image.

## Upgrade Notes

OpenClaw application state is stored under `./data`. Image updates are managed by Renovate; review upstream release notes before deploying major changes and keep a dataset snapshot before upgrades.

Template changes to `./config/openclaw.json` only take effect on first deploy. To re-seed after editing the template, snapshot the dataset, delete `./data/openclaw.json` on the host, and redeploy.
