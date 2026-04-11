---
agent: 'agent'
description: 'Retire a Docker Compose app from the TrueNAS Apps repository following repo conventions.'
argument-hint: 'Name the app to retire and the reason for retirement'
---

Remove the specified app from this repository, cleaning up all integration points.

Before starting, identify the app's current integration footprint by searching for its name across the entire repo (compose files, Traefik config, DNS records, README, ARCHITECTURE docs, servers.yaml, Gatus config, etc.).

## Pre-Retirement (on each server the app runs on)

- Run `dccd-down <app>` (server-aware teardown via `dccd.sh -R <app>`) on each server, **or** let the auto-cleanup in `dccd.sh` handle it on the next deploy after merge.
- If the app was active in TrueNAS, remove its entry after containers are stopped.

## Repository Changes

Work through each item; skip any that don't apply to this app:

1. **Delete `services/<app>/`** — remove `compose.yaml`, `secret.sops.env`, and any `config/` directory.
2. **Traefik compose** (`services/traefik/compose.yaml`) — remove the app's frontend network from the traefik service's `networks:` list and the corresponding external network definition at the bottom of the file.
3. **Traefik compose overrides** — if the app appears in any `services/traefik/compose.<server>.yaml` override, remove it there too.
4. **Traefik middlewares** (`services/traefik/config/rules/middlewares.yml`) — remove any app-specific middleware definitions (e.g. custom secure-headers).
5. **Traefik middleware chains** (`services/traefik/config/rules/middlewares-chains.yml`) — remove any app-specific chain definitions.
6. **DNS A-records** (`services/adguard/config/unbound/conf.d/a-records.conf`) — remove the app's subdomain entry.
7. **Gatus monitoring** (`services/gatus/config/config.yaml`) — remove any health-check endpoints for the app.
8. **README.md** — remove the app from the Apps table and the dataset list.
9. **docs/ARCHITECTURE.md** — remove UID/GID table entries, init container table entries, shared env references, and any app-specific sections.
10. **servers.yaml** — if the app is explicitly listed under any server, remove it. Then re-run `scripts/generate-sops-rules.sh` and `sops-rekey` to update `.sops.yaml` and re-encrypt secrets.
11. **docs/RETIRED-SERVICES.md** — add a row to the retired services table with: service name, date, reason, last active commit hash (the commit just before this retirement), and PR/issue link.

## Validation

1. Run `docker compose -f services/traefik/compose.yaml config --quiet` to verify the Traefik compose file is still valid.
2. Run `mise exec -- lefthook run pre-commit` for the full lint suite.
3. Grep for the app name across the repo — only historical references in `CHANGELOG.md` should remain.

## Post-Merge Manual Steps (on the TrueNAS host)

These steps are destructive and require manual confirmation:

- **Destroy the TrueNAS dataset**: `vm-pool/apps/services/<app>` (ensure backups are current first).
- **Remove the TrueNAS service account** (user + group) if one was created for this app.
- **Remove stale Docker networks**: `docker network prune` if the app's frontend network persists.
