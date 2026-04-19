---
name: compose-security-audit
description: >
    Audit and fix Docker Compose service definitions for security compliance against
    this repository's hardening conventions. Use when asked to audit, review, or fix
    security issues in compose files, check container capabilities, or harden a service.
argument-hint: "Name a service to audit (e.g. 'immich') or 'all' to scan the entire repo"
---

# Audit Docker Compose Security Compliance

## When to Use

- Reviewing a compose file before merging a PR
- Hardening an existing service that was added without full compliance
- Doing a periodic security sweep of all services
- Checking whether a new service follows all conventions

## Prerequisites

Read `docs/ARCHITECTURE.md` before starting — it defines the security requirements and
every documented exception (s6-overlay, database images, socket-proxy).

## Security Requirements Reference

Every container must satisfy all items in this checklist unless a documented exception
applies (see ARCHITECTURE.md § Exceptions).

### Image hygiene

| Requirement | Rule |
| ----------- | ---- |
| Explicit registry prefix | `docker.io/library/…`, `ghcr.io/…`, `lscr.io/…` — no bare image names |
| Digest-pinned | `@sha256:…` suffix required — tag-only references are rejected by CI |
| Hardened variant preferred | Hardened > Alpine > slim > standard |

### Hardening fields (every non-exempt service)

| Field | Required |
| ----- | -------- |
| `read_only: true` | Yes |
| `security_opt: [no-new-privileges:true]` | Yes |
| `cap_drop: [ALL]` | Yes |
| `cap_add` | Only minimum; each entry needs an inline comment explaining why |
| `mem_limit` | Yes — prefer `${MEM_LIMIT:-<default>}` pattern |
| `pids_limit` | Yes — 100 for regular services, 50 for init containers |

### Health checks

Every service needs a `healthcheck:` block. Init containers (`restart: "no"`,
`network_mode: none`) are exempt. Scratch-based images that genuinely cannot have a
health check must have a comment block explaining why.

### Volume mounts

| Check | Rule |
| ----- | ---- |
| `./config` paths | Always `:ro` — config is git-tracked; containers must never write to it |
| Other read-only paths | Mount `:ro` wherever the container only reads |
| Init container chown | Only chown `./data` paths — never `./config` |

### Restart policy

Regular services: `deploy.restart_policy` with `condition: on-failure`,
`max_attempts: 3`, `window: 120s`.
Init containers: `restart: "no"`.

## Documented Exception Categories

The following categories are permitted deviations. Each must have a comment block in
the compose file explaining the relaxation:

| Exception | Relaxed controls |
| --------- | ---------------- |
| s6-overlay images (LinuxServer, tiredofit/db-backup) | Omit `user:` and `read_only:`. Add `CHOWN`, `SETUID`, `SETGID`, `SETPCAP` via `cap_add`. |
| LinuxServer socket-proxy | Omit `cap_drop: ALL`. Keep `no-new-privileges` and `read_only`. |
| Postgres / pgautoupgrade | Omit `cap_drop: ALL` (gosu privilege transition). |
| Images requiring writable root (esphome, frigate, home-assistant) | Omit `user:` and `read_only:`. Keep `cap_drop: ALL`. |

Comment block format (place immediately before the service definition):

```yaml
# <ImageName> uses <reason>. <relaxed-control> is therefore omitted.
# See: <upstream reference if applicable>
```

## Audit Procedure

### Step 1 — Read the file

Always read the full compose file before reporting anything:

```sh
cat services/<app>/compose.yaml
```

For a full repo audit, read each `services/*/compose.yaml` file.

### Step 2 — Check each container against the checklist

Work through every service in the file. For each container note:

- Which checks pass ✅
- Which are violations ❌ (missing required control, no documented exception)
- Which are warnings ⚠️ (convention drift: hardcoded mem_limit, missing comment on cap_add)

### Step 3 — Report findings before editing

Output a findings block per container before making any changes:

```text
Container: <name>
❌ VIOLATION  read_only missing
❌ VIOLATION  pids_limit not set
⚠️  WARNING   mem_limit is hardcoded — prefer ${MEM_LIMIT:-512m}
✅ OK         no-new-privileges present
✅ OK         image digest-pinned
```

### Step 4 — Fix violations

After reporting, fix every ❌ VIOLATION and ⚠️ WARNING. Make surgical edits — do not
reformat unrelated sections or change comments you are not correcting.

When adding an exception comment block, use the documented format exactly.

### Step 5 — Verify the fix

Re-read the edited file and confirm every violation is resolved. Optionally run:

```sh
docker compose -f services/<app>/compose.yaml config --quiet
```

Warnings about unset env vars are expected. Errors are not.

### Step 6 — Summary

After all edits, output:

- Number of containers audited
- Number of violations found and fixed
- Number of warnings addressed
- Exception blocks added (if any)

## Checklist

Use as a final review:

- [ ] Every image has an explicit registry prefix
- [ ] Every image is digest-pinned (`@sha256:…`)
- [ ] `read_only: true` on every non-exempt container
- [ ] `no-new-privileges` on every container (no exceptions)
- [ ] `cap_drop: [ALL]` on every non-exempt container
- [ ] `cap_add` entries have inline justification comments
- [ ] `mem_limit` set on every container
- [ ] `pids_limit` set on every container
- [ ] Health check present on every non-init, non-scratch container
- [ ] `./config` volumes mounted `:ro`
- [ ] Init containers only chown `./data` paths
- [ ] Exception deviations have comment blocks
- [ ] `docker compose config --quiet` passes
