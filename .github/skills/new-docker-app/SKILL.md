---
name: new-docker-app
description: >
    Add a new Docker Compose app to the TrueNAS Apps repository following all
    repo conventions. Use when adding a new service, onboarding a new app,
    creating a compose stack, or migrating an app to this repository.
argument-hint: 'Paste the existing compose YAML or describe the app to add'
---

# Add a New Docker Compose App

## When to Use

- Adding a brand-new service to the repository
- Migrating an existing Docker Compose stack into this repo's conventions
- Onboarding an app that was previously managed outside this GitOps workflow

## Prerequisites

Read these docs before starting — they define the patterns every compose file must follow:

- [ARCHITECTURE.md](../../../docs/ARCHITECTURE.md) — compose patterns, container security, networking, directory conventions
- [INFRASTRUCTURE.md](../../../docs/INFRASTRUCTURE.md) — UID/GID allocation, storage layout, multi-server deployment

Use the closest existing app in `services/` as a template. When in doubt, model after a simple single-container app like `echo-server` or a multi-container app like `immich`.

## Procedure

Work through each step in order. Skip any that don't apply.

### Step 1 — Create the compose stack

Create `services/<app>/compose.yaml` following all compose conventions:

- **Image**: Explicit registry prefix (`docker.io/library/...`, `ghcr.io/...`), digest-pinned (`@sha256:...`). No bare image names.
- **Security**: `read_only: true`, `security_opt: [no-new-privileges:true]`, `cap_drop: [ALL]`, `mem_limit`, `pids_limit: 100`. Add `cap_add` only when provably required — include a comment explaining why.
- **Health check**: Mandatory on every service (required for `--wait` deploys).
- **Init container**: Required when a service uses `user: "UID:GID"` with writable volumes. Use the busybox init pattern from ARCHITECTURE.md. Must only `chown ./data` paths — never `./config` directories.
- **Config volumes**: `./config` directories mounted `:ro`. If runtime writes are needed, copy to `./data` in an init container.
- **Networks**: Create an `<app>-frontend` network. Define it as `external: true` in the compose file.
- **Volumes**: Mount `:ro` wherever the container only reads.
- **Shared env**: Reference `../shared/env/tz.env` for timezone.
- **Traefik labels**: Use the appropriate middleware chain (`chain-auth@file`, `chain-no-auth@file`, etc.). Add a no-auth router only when the app cannot support OAuth/SSO (e.g. mobile-only apps). Do **not** add Gatus bypass routers — Gatus uses its own monitoring configuration.

Determine the correct PUID/PGID model for this app (media consumer, media producer, photos, or general — see INFRASTRUCTURE.md). If a new shared PGID group is needed, create the corresponding env file in `services/shared/env/`.

### Step 2 — Create the secrets template

Create `services/<app>/secret.sops.env` listing every secret variable the app requires. Then encrypt it in-place:

```sh
sops -e -i services/<app>/secret.sops.env
```

Output a summary table of all secrets/variables that need to be populated.

### Step 3 — Register the network in Traefik

Add the app's `<app>-frontend` network to `services/traefik/compose.yaml`:

- Add it to the `traefik` service's `networks:` list
- Add the external network definition at the bottom of the file

### Step 4 — Add DNS records

Add the app's subdomain(s) to `services/adguard/config/unbound/conf.d/a-records.conf`, pointing to the correct `${IP_*}` variable for the server it runs on (e.g. `${IP_SVLNAS}` for NAS-hosted apps). Keep entries alphabetically sorted within the Internal or External section.

If unsure what host the app should run on, ask the user.

### Step 5 — Configure Gatus health monitoring

Add Gatus sidecar labels to the main application container in `compose.yaml`.
See `.github/skills/gatus-monitoring/SKILL.md` for the full pattern reference.

**Standard decision tree:**

- Does the service use `chain-auth@file` middleware? → Add `gatus.client={"ignore-redirect": true}`
- Does the service have a dedicated `/ping`, `/health`, or `/api/health` endpoint? → Use that path in `gatus.url`
- Is this a background helper (init, DB, backup, sidecar)? → Add `gatus.enabled=false`

**Minimum labels for a standard Traefik-routed service (`chain-no-auth@file`):**

```yaml
## Gatus
- "gatus.url=http://172.30.100.6:8444"
- "gatus.headers.Host=<subdomain>.${DOMAINNAME}"
- 'gatus.conditions=["[STATUS] == 200", "[RESPONSE_TIME] < 1000"]'
- 'gatus.alerts=[{"type": "email"}, {"type": "custom"}]'
```

### Step 6 — Update documentation

Update these files (keep tables alphabetically sorted by app name):

| File                     | What to update                                                         |
| ------------------------ | ---------------------------------------------------------------------- |
| `README.md`              | Apps table row, dataset list entry                                     |
| `docs/index.md`          | Keep in sync with README.md (plain Markdown only, no HTML)             |
| `docs/ARCHITECTURE.md`   | Init container table entries, shared env entries, access model section |
| `docs/INFRASTRUCTURE.md` | UID/GID table entries, shared purpose group entries, storage section   |

### Step 7 — Create per-service documentation

Create `services/<app>/README.md` with standard sections:

- Title, description, why this app
- Compose file links
- Access information (URL, auth method)
- Architecture (services, networks, volumes)
- Secrets table
- First-run setup
- Upgrade notes (if applicable)

Then generate the docs symlink and register the page:

```sh
bash scripts/generate-docs-symlinks.sh
```

Add the entry to the `Services:` section in `mkdocs.yml` in alphabetical order by display name.

### Step 8 — Multi-server setup (if applicable)

If the app will run on a non-TrueNAS server:

1. Add it to the appropriate server in `servers.yaml`
2. If the server also has Traefik, add the frontend network to `services/traefik/compose.<server>.yaml`
3. Re-run `scripts/generate-sops-rules.sh` to update `.sops.yaml` creation rules

### Step 9 — Validate

```sh
docker compose -f services/<app>/compose.yaml config --quiet
```

Warnings about unset env vars (e.g. `DOMAINNAME`) are expected — secrets are decrypted at deploy time. Warnings are fine; errors are not.

### Step 10 — Document manual host steps

Output a summary of any manual steps required on the TrueNAS host:

- Creating groups and users
- Dataset creation and ACLs
- Any other host-level configuration

## Checklist

Use this as a final review before committing:

- [ ] `compose.yaml` follows all security conventions (read_only, no-new-privileges, cap_drop, mem_limit, pids_limit)
- [ ] Every container has a health check
- [ ] Init container uses busybox pattern and only chowns `./data`
- [ ] `./config` volumes are mounted `:ro`
- [ ] Image is digest-pinned with explicit registry prefix
- [ ] `secret.sops.env` is encrypted
- [ ] Traefik network and labels are configured
- [ ] Gatus sidecar labels are configured on the main container (or `gatus.enabled=false` for helpers)
- [ ] DNS A-record is added
- [ ] README.md, docs/index.md, ARCHITECTURE.md, INFRASTRUCTURE.md are updated
- [ ] Per-service README.md is created with docs symlink
- [ ] mkdocs.yml nav is updated
- [ ] `docker compose config --quiet` passes
