# Karakeep

[Karakeep](https://karakeep.app/) is a self-hosted bookmark manager for links,
notes, and images, with full-text search and optional AI tagging.

## Why

Karakeep keeps saved content and its search index on locally managed storage.
The split web, worker, and search services isolate background crawling and
indexing from the user-facing application. Headless browser support remains
available only as an explicit opt-in reference.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/karakeep/compose.yaml)

## Access and Authentication

| URL                              | Authentication                                      |
| -------------------------------- | --------------------------------------------------- |
| `https://karakeep.${DOMAINNAME}` | Traefik Forward Auth, then Karakeep local user auth |

The Traefik router applies `chain-auth@file` to every request. Karakeep keeps
its own local account authentication as a second layer.

<!-- dprint-ignore -->
!!! warning "API and mobile client limitation"
    No API or mobile-client Forward Auth bypass is configured. Clients that
    cannot complete the interactive Forward Auth flow or reuse its browser
    session may not work with this deployment. Do not switch clients to an
    unprotected endpoint; add a narrowly scoped authenticated bypass only
    after reviewing the exposed API surface.

## Architecture

- **Active images**: `ghcr.io/karakeep-app/karakeep:0.33.2` and
  `docker.io/getmeili/meilisearch:v1.41.0`
- **Application user/group**: `3130:3130` (`svc-app-karakeep`) for the web,
  worker, and Meilisearch processes
- **Reverse proxy**: Traefik with `chain-auth@file`
- **Process model**: split web and worker processes with
  `USING_LEGACY_SEPARATE_CONTAINERS=true`

The upstream all-in-one image normally starts the web and workers under
s6-overlay as root. This stack launches each process directly under the
dedicated service account. The web process runs database migrations before
starting the server.

### Services

| Container              | Role                                                                  |
| ---------------------- | --------------------------------------------------------------------- |
| `karakeep-init`        | Validates required settings and assigns runtime directory ownership   |
| `karakeep`             | Web UI and API on the internal container port `3000`                  |
| `karakeep-workers`     | Background crawling, asset processing, indexing, and optional AI work |
| `karakeep-meilisearch` | Full-text search engine on the internal port `7700`                   |

### Optional Browser Crawling

`CRAWLER_HEADLESS_BROWSER=false` is the default, and the complete
`karakeep-chrome` Compose service remains commented out as an opt-in reference.
The browser container is not created and does not join either Karakeep network
during a normal deployment.

Without Chrome, links, notes, images and other assets, SQLite persistence,
Meilisearch full-text search, and optional AI tagging continue to work.
Browser-rendered crawling, screenshots, and full-page browser captures are
unavailable.

The optional image reference is
`ghcr.io/karakeep-app/karakeep-chrome:151.0.7922.47-r1`.

<!-- dprint-ignore -->
!!! warning "Explicit risk acceptance required"
    The browser processes attacker-controlled pages, and Karakeep's upstream
    Chrome image starts Chromium with `--no-sandbox`. Running it as non-root
    with a read-only root filesystem, dropped capabilities, no published
    ports, and resource limits reduces exposure but does not make that
    additional attack surface acceptable by default.

To opt in later:

1. Explicitly reassess and accept the browser risk.
2. Uncomment the complete `karakeep-chrome` service definition in
   `compose.yaml`.
3. Add `BROWSER_WEB_URL: http://karakeep-chrome:9222` to the shared Karakeep
   environment.
4. Restore the `karakeep` web service's `service_healthy` dependency on
   `karakeep-chrome`.

### Security Model

- `karakeep-init` chowns both runtime directories to `3130:3130`, then exits
  before the runtime services start.
- The web, worker, and Meilisearch containers run as `3130:3130`.
- Runtime containers use read-only root filesystems,
  `no-new-privileges=true`, dropped capabilities, PID limits, and memory
  limits.
- Only the web container is routed through Traefik. Meilisearch remains on the
  internal backend network.

## Volumes and Networks

### Volumes

| Host path            | Container path | Used by      | Purpose                          |
| -------------------- | -------------- | ------------ | -------------------------------- |
| `./data/karakeep`    | `/data`        | Web, workers | SQLite database and saved assets |
| `./data/meilisearch` | `/meili_data`  | Meilisearch  | Full-text search index           |

### Networks

| Network             | Members and purpose                                                          |
| ------------------- | ---------------------------------------------------------------------------- |
| `karakeep-frontend` | Web and workers; Traefik access plus outbound crawling and optional AI calls |
| `karakeep-backend`  | Internal communication between web, workers, and Meilisearch                 |

## Secrets

Store these values in `secret.sops.env`, committed only in SOPS-encrypted form
and decrypted to `.env` during deployment. Do not commit plaintext values.

| Variable                    | Classification  | Purpose                                                        |
| --------------------------- | --------------- | -------------------------------------------------------------- |
| `DOMAINNAME`                | Required config | Base domain for Traefik routing and NextAuth                   |
| `KARAKEEP_NEXTAUTH_SECRET`  | Required secret | Random secret used to protect Karakeep authentication sessions |
| `KARAKEEP_MEILI_MASTER_KEY` | Required secret | Random Meilisearch master key                                  |
| `KARAKEEP_OPENAI_API_KEY`   | Optional secret | User-supplied OpenAI API key for automatic AI tagging          |

`KARAKEEP_OPENAI_API_KEY` must be populated through SOPS to enable automatic AI
tagging. Leave it empty to keep automatic AI tagging disabled.

## First-Run Setup

1. From the repository root on TrueNAS, provision the Karakeep host
   prerequisites:

   ```sh
   sudo bash scripts/truenas-prep-app.sh karakeep
   ```

   The helper creates or verifies the `svc-app-karakeep` group with GID 3130,
   the `svc-app-karakeep` user with UID 3130 and that primary group, and the
   `vm-pool/apps/services/karakeep` child dataset. It does not add
   `truenas_admin` to the service group (`ADMIN_GROUP_MEMBER=false`). When
   creating the child dataset, it stages and restores the existing service
   directory. The command is safe to rerun and refuses account identity
   collisions or mismatches. See
   [Infrastructure](../INFRASTRUCTURE.md#karakeep-dataset) for storage details.
2. Generate independent random values for `KARAKEEP_NEXTAUTH_SECRET` and
   `KARAKEEP_MEILI_MASTER_KEY`, then populate and encrypt
   `services/karakeep/secret.sops.env` with SOPS.
3. Optionally populate `KARAKEEP_OPENAI_API_KEY` through SOPS to enable
   automatic AI tagging; otherwise leave it empty.
4. Deploy the stack and confirm `karakeep-init` completes successfully,
   Meilisearch, the web service, and the worker service become healthy, and the
   web process completes its database migrations.
5. Open `https://karakeep.${DOMAINNAME}` through Forward Auth and complete the
   Karakeep local account setup.

## Upgrade and Backup Notes

- Renovate manages image updates. Review the
  [Karakeep releases](https://github.com/karakeep-app/karakeep/releases) before
  major upgrades.
- The web container applies database migrations before startup and uses a
  stop-first update order so the replacement does not serve traffic before
  migrations finish.
- Snapshot the complete `vm-pool/apps/services/karakeep` dataset before an
  upgrade so the SQLite database, assets, and Meilisearch index remain
  coordinated.
- For file-level backup of the SQLite data, stop or otherwise quiesce the web
  and worker processes before copying `./data/karakeep`. Preserve the
  SOPS-encrypted secrets with the backup.
- The repository's ZFS snapshot, replication, and off-site strategy covers the
  child dataset; see [Backup Strategy](../BACKUP.md).
