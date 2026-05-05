# Tinyauth

Lightweight, self-hosted authentication layer for services exposed through Traefik. Tinyauth
acts as a [ForwardAuth](https://doc.traefik.io/traefik/middlewares/http/forwardauth/) provider —
any service configured with Traefik's `forwardauth` middleware redirects unauthenticated requests
to Tinyauth's login page.

## Why

This service is an **experimental** alternative to
[Traefik Forward Auth](../traefik-forward-auth/README.md). Where `traefik-forward-auth` requires
an external identity provider (Microsoft Entra ID / Azure AD), Tinyauth provides a self-contained
login page backed by a local SQLite database with optional OAuth (Google, GitHub, OIDC) and
TOTP (2FA) support. This makes it useful for isolated environments or services that cannot
integrate with the primary OIDC provider.

### Tinyauth vs Pocket ID

[Pocket ID](https://pocket-id.org/) is a self-hosted OIDC provider focused on
passwordless/passkey login. It is a stronger fit when downstream apps can integrate with OIDC and
passkeys are desired.

Tinyauth is primarily a reverse-proxy / Traefik ForwardAuth guard. It is useful for protecting apps
that do not speak OIDC, and is a stronger fit for this experiment because it can protect arbitrary
Traefik-routed apps with forward-auth and minimal per-app integration.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/tinyauth/compose.yaml)

## Access

| URL                              | Description                                                                            |
| -------------------------------- | -------------------------------------------------------------------------------------- |
| `https://tinyauth.${DOMAINNAME}` | Login page and admin UI (uses `chain-no-auth@file` — the auth service protects itself) |

## Architecture

- **Image**: [ghcr.io/steveiliop56/tinyauth](https://github.com/steveiliop56/tinyauth)
- **User/Group**: `3125:3125` (`svc-app-tinyauth`)
- **Networks**: `tinyauth-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-no-auth@file` — the authentication service cannot
  protect itself
- **Init container**: `tinyauth-init` chowns `./data` to `3125:3125`

### Services

| Container       | Role                                                                          |
| --------------- | ----------------------------------------------------------------------------- |
| `tinyauth-init` | One-shot init: chowns `./data` to `3125:3125`, then exits                     |
| `tinyauth`      | Authentication service — serves login UI and the `/api/auth/traefik` endpoint |

### Volumes

| Host path | Container path | Mode | Purpose                               |
| --------- | -------------- | ---- | ------------------------------------- |
| `./data`  | `/data`        | rw   | SQLite database, OIDC keys, resources |

### Forward Auth Integration

To protect a service with Tinyauth, configure Traefik's `forwardauth` middleware to point at
`http://tinyauth:3000/api/auth/traefik`. Example label on a protected service:

```yaml
labels:
  - "traefik.http.middlewares.tinyauth-forwardauth.forwardauth.address=http://tinyauth:3000/api/auth/traefik"
  - "traefik.http.middlewares.tinyauth-forwardauth.forwardauth.trustForwardHeader=true"
  - "traefik.http.routers.<app>-rtr.middlewares=tinyauth-forwardauth"
```

Both the protected service and tinyauth must share a Docker network for the forwardauth call
to reach Tinyauth's API.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

| Variable              | Description                                                                                |
| --------------------- | ------------------------------------------------------------------------------------------ |
| `DOMAINNAME`          | Base domain for Traefik routing and the app URL                                            |
| `TINYAUTH_AUTH_USERS` | Comma-separated list of `username:bcrypt_hash` pairs for local login (see First-Run Setup) |

## First-Run Setup

### 1. Create the host service account

```sh
# On the TrueNAS host (as root or truenas_admin)
pw groupadd -n svc-app-tinyauth -g 3125
pw useradd -n svc-app-tinyauth -u 3125 -g 3125 -s /usr/sbin/nologin -d /nonexistent
```

### 2. Create the dataset

Create `vm-pool/apps/services/tinyauth` in the TrueNAS UI (or via CLI). Set compression to
`lz4` and disable atime.

### 3. Generate an initial user

Generate a bcrypt-hashed password for the first user:

```sh
# Using htpasswd (Apache utils)
htpasswd -nB -C 12 myusername
# Output: myusername:$2y$12$...
```

Or using Python:

```sh
python3 -c "import bcrypt; print('myusername:' + bcrypt.hashpw(b'mypassword', bcrypt.gensalt(rounds=12)).decode())"
```

Set the output as `TINYAUTH_AUTH_USERS` in `secret.sops.env` and encrypt:

```sh
sops -e -i services/tinyauth/secret.sops.env
```

### 4. Deploy

```sh
docker compose -f services/tinyauth/compose.yaml up -d --wait
```

Visit `https://tinyauth.${DOMAINNAME}` to confirm the login page loads.

### 5. (Optional) Add OAuth providers

Configure OAuth in the `.env` / `secret.sops.env` using the `TINYAUTH_OAUTH_PROVIDERS_*`
variables. See the [Tinyauth documentation](https://tinyauth.app/docs/) for the full list of
supported providers and options.

## Upgrade Notes

No special upgrade procedures. Image updates are managed by Renovate. The SQLite database in
`./data/tinyauth.db` and OIDC key files in `./data/` persist across container recreations.
