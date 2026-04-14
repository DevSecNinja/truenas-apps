---
name: retire-docker-app
description: >
    Retire a Docker Compose app from the TrueNAS Apps repository following all
    repo conventions. Use when removing a service, decommissioning an app,
    tearing down a stack, or cleaning up a retired application.
argument-hint: 'Name the app to retire and the reason for retirement'
---

# Retire a Docker Compose App

## When to Use

- Removing a service that is no longer needed
- Decommissioning an app and cleaning up all integration points
- Replacing an app with an alternative (retire the old one)

## Procedure

Before starting, identify the app's current integration footprint by searching for its name across the entire repo (compose files, Traefik config, DNS records, README, ARCHITECTURE docs, servers.yaml, Gatus config, etc.).

### Step 1 — Pre-retirement (on each server the app runs on)

- Run `dccd.sh -R <app>` (server-aware teardown) on each server, **or** let the auto-cleanup in `dccd.sh` handle it on the next deploy after merge.
- If the app was active in TrueNAS, remove its entry after containers are stopped.

### Step 2 — Delete the service directory

Remove `services/<app>/` — including `compose.yaml`, `secret.sops.env`, `README.md`, and any `config/` directory.

### Step 3 — Remove Traefik integration

1. **Traefik compose** (`services/traefik/compose.yaml`) — remove the app's frontend network from the traefik service's `networks:` list and the corresponding external network definition at the bottom of the file.
2. **Traefik compose overrides** — if the app appears in any `services/traefik/compose.<server>.yaml` override, remove it there too.
3. **Traefik middlewares** (`services/traefik/config/rules/middlewares.yml`) — remove any app-specific middleware definitions (e.g. custom secure-headers).
4. **Traefik middleware chains** (`services/traefik/config/rules/middlewares-chains.yml`) — remove any app-specific chain definitions.

### Step 4 — Remove DNS records

Remove the app's subdomain entry from `services/adguard/config/unbound/conf.d/a-records.conf`.

### Step 5 — Remove Gatus monitoring

Remove any health-check endpoints for the app from `services/gatus/config/config.yaml`.

### Step 6 — Update documentation

Remove the app from these files (keep remaining tables alphabetically sorted):

| File                     | What to remove                                                             |
| ------------------------ | -------------------------------------------------------------------------- |
| `README.md`              | Apps table row, dataset list entry                                         |
| `docs/index.md`          | Keep in sync with README.md                                                |
| `docs/ARCHITECTURE.md`   | Init container table entries, shared env references, app-specific sections |
| `docs/INFRASTRUCTURE.md` | UID/GID table entries, media/storage references, app-specific sections     |

### Step 7 — Add to retired services log

Add a row to `docs/RETIRED-SERVICES.md` with:

- Service name
- Retirement date
- Reason for retirement
- Last active commit hash (the commit just before this retirement)
- PR/issue link (if applicable)

### Step 8 — Remove per-service documentation

1. Remove the symlink at `docs/services/<app>.md`
2. Remove the entry from the `Services:` section in `mkdocs.yml`

### Step 9 — Update server mappings (if applicable)

If the app is listed in `servers.yaml`:

1. Remove it from the server's app list
2. Re-run `scripts/generate-sops-rules.sh` to update `.sops.yaml`
3. Re-encrypt secrets with `sops-rekey` if creation rules changed

### Step 10 — Validate

1. Verify Traefik compose is still valid:

   ```sh
   docker compose -f services/traefik/compose.yaml config --quiet
   ```

2. Run the full lint suite:

   ```sh
   mise exec -- lefthook run pre-commit
   ```

3. Grep for the app name across the repo — only historical references in `CHANGELOG.md` and `docs/RETIRED-SERVICES.md` should remain.

### Step 11 — Post-merge manual steps (on the TrueNAS host)

These steps are destructive and require manual confirmation:

- **Destroy the TrueNAS dataset**: `vm-pool/apps/services/<app>` (ensure backups are current first)
- **Remove the TrueNAS service account** (user + group) if one was created for this app
- **Remove stale Docker networks**: `docker network prune` if the app's frontend network persists

## Checklist

Use this as a final review before committing:

- [ ] `services/<app>/` directory is deleted
- [ ] Traefik compose and overrides are cleaned up
- [ ] Traefik middlewares/chains are removed (if any existed)
- [ ] DNS A-record is removed
- [ ] Gatus monitoring is removed (if any existed)
- [ ] README.md, docs/index.md, ARCHITECTURE.md, INFRASTRUCTURE.md are updated
- [ ] docs/RETIRED-SERVICES.md has the new entry
- [ ] Per-service docs symlink and mkdocs.yml entry are removed
- [ ] servers.yaml and SOPS rules are updated (if applicable)
- [ ] `docker compose config --quiet` passes for Traefik
- [ ] Grep for app name shows only historical references
