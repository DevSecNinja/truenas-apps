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

The aliases must already be sourced from
`/mnt/vm-pool/apps/scripts/aliases.sh` on `svlnas`.

1. After the changes merge, pull them and decrypt the SOPS files with the
   app-scoped alias:

   ```sh
   dccd-app memos
   ```

   Because the `memos` TrueNAS Custom App does not exist yet, dccd will report
   that its TrueNAS app config directory is missing and skip deployment. This is
   expected for the first pass. Do not start with `dccd-all`: Traefik already
   references the frontend network that the new Custom App will create.
2. From the updated TrueNAS checkout, run the host preparation helper:

   ```sh
   cd /mnt/vm-pool/apps
   sudo bash scripts/truenas-prep-app.sh memos
   ```

   The idempotent helper creates or verifies the manifest-declared Memos group
   and user, creates the child ZFS dataset without discarding the existing
   checkout, and sets the app directory ownership and mode. The Memos manifest
   entry does not request administrative auxiliary group membership.
3. In the TrueNAS UI, create a Custom App named `memos` with:

   ```yaml
   include:
     - /mnt/vm-pool/apps/services/memos/compose.yaml
   services: {}
   ```

4. Run the canonical final deployment:

   ```sh
   dccd-all
   ```

   This deploys Memos and applies its dependent AdGuard and Traefik changes
   through the normal TrueNAS ordering, decrypts secrets, and runs the default
   backup freshness check. Confirm that `memos-init` completes and Memos is
   healthy.
5. Open `https://memos.${DOMAINNAME}`, create the first Memos account, configure
   the registration and access policy in the admin settings, and verify access.

## Upgrade Notes

Image updates are managed by Renovate; the initial tag-only adoption will receive
a digest pin automatically. Before major upgrades, snapshot `./data` and review
the [upstream release notes](https://github.com/usememos/memos/releases).
