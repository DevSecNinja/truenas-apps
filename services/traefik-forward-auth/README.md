# Traefik Forward Auth

Traefik Forward Auth provides single sign-on (SSO) authentication for Traefik-proxied services using Microsoft Entra ID (Azure AD) as the identity provider.

## Why

Traefik Forward Auth adds a centralized authentication layer for self-hosted services at the reverse proxy level — services using the `chain-auth@file` middleware get SSO via your Microsoft Entra ID tenant. This remains in use after the [arr stack retirement](../RETIRED-SERVICES.md#arr-stack-retirement); retiring those apps does not retire the shared authentication service.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/traefik-forward-auth/compose.yaml)
- [compose.svlazext.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/traefik-forward-auth/compose.svlazext.yaml) — Azure external VM override

## Access

| URL                          | Description                                                                    |
| ---------------------------- | ------------------------------------------------------------------------------ |
| `https://auth.${DOMAINNAME}` | Auth callback endpoint (no forward-auth on itself — uses `chain-no-auth@file`) |

## Architecture

- **Image**: [italypaleale/traefik-forward-auth](https://github.com/ItalyPaleAle/traefik-forward-auth)
- **User/Group**: `3105:3105` (`svc-app-tfa`)
- **Networks**: `traefik-forward-auth-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-no-auth@file` middleware (the auth service itself must not require auth)

### Config Template Substitution

The config file (`config/config.yaml`) contains `${VAR}` placeholders for secrets. The `traefik-forward-auth-init` container runs `config/envsubst.sh` at deploy time to substitute values from `secret.sops.env` and writes the processed output to `data/config.yaml`. The main container mounts the processed file read-only.

Per-server overrides set different `AUTH_SUBDOMAIN` and `COOKIE_NAME_PREFIX` values so each deployment has its own cookie scope.

### Services

| Container                   | Role                                                                            |
| --------------------------- | ------------------------------------------------------------------------------- |
| `traefik-forward-auth-init` | One-shot init: chowns `./data` to `3105:3105`, runs envsubst on config template |
| `traefik-forward-auth`      | SSO authentication service — validates tokens and redirects to Entra ID login   |

### Multi-Server Deployment

Runs on all servers where Traefik is deployed. Each server uses a compose override to set a unique auth subdomain and cookie name prefix, preventing cookie collisions between instances.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for cookie scoping and redirect URLs
- Microsoft Entra ID credentials (client ID, client secret, tenant ID)
- Cookie and encryption secrets

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/traefik-forward-auth` in TrueNAS
2. Create a `svc-app-tfa` group (GID 3105) and user (UID 3105) on the TrueNAS host
3. Register an Azure AD application and configure redirect URIs
4. Populate the Entra ID credentials in `secret.sops.env`
5. Deploy — test by visiting any service that uses `chain-auth@file` middleware

## Upgrade Notes

No special upgrade procedures. Image updates are managed by Renovate.
