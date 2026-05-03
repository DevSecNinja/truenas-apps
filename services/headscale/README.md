# Headscale

Headscale is an open-source, self-hosted coordination server for Tailscale. It allows you to create and manage your own Tailscale network without relying on Tailscale's cloud infrastructure, giving you complete control over user management, device registration, and network policies.

## Why

Tailscale is an excellent zero-trust networking tool, but it requires a Tailscale account and uses Tailscale's cloud coordination server. Headscale lets you run your own coordination server, keeping all network state and user data under your control. This stack is deployed on `svlazext` (the Azure external VM) to serve as a central coordination point for Tailscale clients across your home lab, Azure infrastructure, and remote devices — all with end-to-end encryption managed by Tailscale/WireGuard.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/headscale/compose.yaml) — primary stack definition

## Access

| URL                               | Description                                            |
| --------------------------------- | ------------------------------------------------------ |
| `https://headscale.${DOMAINNAME}` | Coordination API (Traefik no-auth, headscale frontend) |

## Architecture

- **Image**: [docker.io/headscale/headscale](https://github.com/juanfont/headscale) (v0.28.0)
- **User/Group**: `3127:3127` (`svc-app-headscale`) — the headscale container runs under this identity
- **Network**: `headscale-frontend` (bridge) — Traefik-facing network for the coordination API
- **Port**: `8080` (HTTP, reverse-proxied via Traefik on HTTPS)
- **Storage**: `./data/config` (generated config, mounted `:ro`), `./data/lib` (SQLite database, Noise keys, read-write)
- **Reverse proxy**: Traefik with `chain-no-auth@file` middleware (public API access)

### Services

| Container        | Role                                                                                          |
| ---------------- | --------------------------------------------------------------------------------------------- |
| `headscale-init` | One-shot init: substitutes `${VAR}` placeholders in config template, chowns `./data` to `3127:3127` |
| `headscale`      | Coordination server — listens on port 8080 and serves Tailscale protocol endpoints                  |

### Startup Order

```text
headscale-init (completed) ──→ headscale
```

### Init Container

**`headscale-init`** runs the config template substitution script and chowns runtime directories:

- **Image**: `docker.io/library/busybox:1.37.0`
- **Capabilities**: `CHOWN` (transfer ownership)
- **Volumes chown'd**: `./data` (config, SQLite database, Noise keys)

The init container runs `./config/envsubst.sh` to substitute `${DOMAINNAME}` placeholders in `./config/config.yaml` and writes the processed output to `./data/config/config.yaml`. The main headscale container then mounts this processed file read-only. This pattern keeps secrets out of Git (the template only contains placeholder names) while processed config lives in gitignored `./data/`.

### Config Template Substitution

The `config.yaml` file contains `${VAR}` placeholders for environment-specific values:

| Variable    | Source           | Usage                                              |
| ----------- | ---------------- | -------------------------------------------------- |
| `DOMAINNAME` | `secret.sops.env` | Headscale server hostname for the web UI and API |

The `envsubst.sh` script verifies no unresolved placeholders remain after substitution — missing variables cause the init container to fail loudly rather than starting Headscale with incomplete config.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Headscale API endpoints (e.g., `headscale.example.com`)

## First-Run Setup

1. Create `/opt/apps/services/headscale` on `svlazext` (or the dataset `vm-pool/apps/services/headscale` when running on TrueNAS)
2. Create a `svc-app-headscale` group (GID 3127) and user (UID 3127) on the target host — see [Infrastructure](../INFRASTRUCTURE.md#app-service-accounts) for the full procedure
3. Set `DOMAINNAME` in `secret.sops.env` to the base domain used by Traefik
4. Encrypt the secrets file: `sops -e -i services/headscale/secret.sops.env`
5. Deploy: the CD script decrypts secrets, runs the init container to process the template, and brings the stack up
6. Verify the health check: `docker logs headscale` should show the server listening on port 8080
7. Point clients at `https://headscale.${DOMAINNAME}` (Traefik handles TLS and routing from `svlazext`)

## Upgrade Notes

No special upgrade procedures are required for this stack. Headscale handles schema and data migrations automatically on startup. Image updates are managed by Renovate via digest-pinning PRs. The SQLite database in `./data/lib/` persists across restarts — do not delete it.
