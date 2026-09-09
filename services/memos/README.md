# Memos

[Memos](https://usememos.com/) is a private, self-hosted note-taking and knowledge service.

## Why

Memos provides a lightweight place to capture and organize notes while keeping the database and uploaded assets on the TrueNAS host.

## Compose Files

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/memos/compose.yaml)
- [secret.sops.env](https://github.com/DevSecNinja/truenas-apps/blob/main/services/memos/secret.sops.env)

## Access

| URL                           | Auth                                 | Description |
| ----------------------------- | ------------------------------------ | ----------- |
| `https://memos.${DOMAINNAME}` | Traefik Forward Auth + Memos account | Web UI      |

Traefik applies `chain-auth@file` before requests reach Memos, which then uses its own account authentication.

## Architecture

- **Image**: `docker.io/neosmemo/memos:0.30.0`
- **User/Group**: `3129:3129` (`svc-app-memos`)
- **Network**: `memos-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **Storage**: `./data` is mounted at `/var/opt/memos`
- **Init image**: `docker.io/library/busybox:1.38.0`

### Services

| Container    | Role                                          |
| ------------ | --------------------------------------------- |
| `memos-init` | One-shot init: chowns `./data` to `3129:3129` |
| `memos`      | Non-root Memos application using SQLite       |

### Volumes

| Host path | Container path   | Purpose                                     |
| --------- | ---------------- | ------------------------------------------- |
| `./data`  | `/var/opt/memos` | SQLite database and locally uploaded assets |

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

| Variable     | Purpose                                                           |
| ------------ | ----------------------------------------------------------------- |
| `DOMAINNAME` | Existing user-supplied deployment domain used for Traefik routing |

Memos does not require any application-generated random secrets for this deployment.

## First-Run Setup

1. After the changes are merged and pulled into the TrueNAS checkout, run the
   host preparation helper from the repository root:

   ```sh
   sudo bash scripts/truenas-prep-app.sh memos
   ```

   The idempotent helper creates or verifies the manifest-declared Memos group
   and user, creates the child ZFS dataset without discarding the existing
   checkout, and sets the app directory ownership and mode. The Memos manifest
   entry does not request administrative auxiliary group membership.
2. Deploy the stack and confirm `memos-init` completes successfully.
3. Open `https://memos.${DOMAINNAME}` and create the first Memos account.
4. Configure registration and access policy in the Memos admin settings as
   desired.

## Upgrade Notes

Image updates are managed by Renovate; the initial tag-only adoption will receive
a digest pin automatically. Before major upgrades, snapshot `./data` and review
the [upstream release notes](https://github.com/usememos/memos/releases).
