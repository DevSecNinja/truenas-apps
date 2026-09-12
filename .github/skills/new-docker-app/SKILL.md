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

Read these references before starting — they define the patterns every compose file must follow:

- [ARCHITECTURE.md](../../../docs/ARCHITECTURE.md) — compose patterns, container security, networking, directory conventions
- [INFRASTRUCTURE.md](../../../docs/INFRASTRUCTURE.md) — UID/GID allocation, storage layout, multi-server deployment
- [BACKUP.md](../../../docs/BACKUP.md) — persistent state classification, database backup sidecar patterns, and the `*-db-backup` freshness convention
- [truenas-apps.json](../../../truenas-apps.json) — add a schema-valid `apps.<name>` entry for each supported TrueNAS-hosted app
- [truenas-apps.schema.json](../../../truenas-apps.schema.json) — required registry fields, account constraints, and validation rules
- [truenas-prep-app.sh](../../../scripts/truenas-prep-app.sh) — idempotent host provisioning driven by the registry

Use the closest existing app in `services/` as a template. When in doubt, model after a simple single-container app like `echo-server` or a multi-container app like `immich`.

## Procedure

Work through each step in order. Skip any that don't apply.

### Step 1 — Create the compose stack

Create `services/<app>/compose.yaml` following all compose conventions:

- **Image**: Explicit registry prefix (`docker.io/library/...`, `ghcr.io/...`), digest-pinned (`@sha256:...`). No bare image names.
  - **Prefer Docker Hardened Images (DHI)** when available at `dhi.io/<image>` — check the catalog at <https://hub.docker.com/hardened-images/catalog>. DHI provides minimal, near-zero-CVE base images with signed SBOMs and SLSA Level 3 provenance. Confirm the DHI tag declares `LINUX/AMD64` **and** `LINUX/ARM64` on the catalog page before adopting it (svlnas is x86_64; svlazext is arm64).
  - **Initial commit: tag only, no digest.** Add the image with just the version tag (e.g. `dhi.io/redis:8.6.2-debian13`) and let Renovate add the `@sha256:...` pin in the next run. Renovate's HEAD request to dhi.io receives the multi-arch manifest-list digest only after the image has been republished as multi-arch; if you pin manually from a snapshot that was still single-platform, you'll lock the repo to amd64 and break arm64 hosts. Letting Renovate pin avoids this race.
- **Security**: `read_only: true`, `security_opt: [no-new-privileges:true]`, `cap_drop: [ALL]`, `mem_limit`, `pids_limit: 100`. Add `cap_add` only when provably required — include a comment explaining why.
- **Health check**: Mandatory on every service (required for `--wait` deploys).
- **Init container**: Required when a service uses `user: "UID:GID"` with writable volumes. Use the busybox init pattern from ARCHITECTURE.md. Must only `chown ./data` paths — never `./config` directories.
- **Config volumes**: `./config` directories mounted `:ro`. If runtime writes are needed, copy to `./data` in an init container.
- **Networks**: Create an `<app>-frontend` network. Define it as `external: true` in the compose file.
- **Volumes**: Mount `:ro` wherever the container only reads.
- **Shared env**: Reference `../shared/env/tz.env` for timezone.
- **Traefik labels**: Use the appropriate middleware chain (`chain-auth@file`, `chain-no-auth@file`, etc.). Add a no-auth router only when the app cannot support OAuth/SSO (e.g. mobile-only apps). Do **not** add Gatus bypass routers — Gatus uses its own monitoring configuration.
- **Persistent paths**: Identify every writable volume this service needs. Step 3 requires classifying each one (database, critical mutable file state, regeneratable cache, or external data) and adding backup coverage for any embedded database.

Determine the correct PUID/PGID model for this app (media consumer, media producer, photos, or general — see INFRASTRUCTURE.md). If a new shared PGID group is needed, create the corresponding env file in `services/shared/env/`.

### Step 2 — Create and populate the secrets template

Follow the dedicated [SOPS secrets skill](../sops-secrets/SKILL.md) for key preflight, safe editing, generation, and validation.

Classify every secret before creating the files:

- **Random values**: App-owned passwords, passphrases, and tokens that can be generated locally.
- **User-supplied values**: OAuth credentials, API keys, SMTP credentials, and other values issued or chosen outside this repository.
- **Shared values**: Existing values provided by `services/shared/`; reference the shared secret file instead of generating a duplicate.

Create `services/<app>/secret.sops.env` with every required variable. Set each random variable's initial value to the literal `GENERATE`, then encrypt the file in-place:

```sh
sops -e -i services/<app>/secret.sops.env
```

The encrypted dotenv file must exist before random values are generated. Prefer SOPS-native `SOPS_AGE_KEY_CMD` with 1Password CLI, configured as `export SOPS_AGE_KEY_CMD='op read "op://<vault>/<item>/<field>"'`. Require 1Password Desktop CLI integration to be enabled and the user to be signed in with the app unlocked; never run or print the `op read` result directly. `SOPS_AGE_KEY_FILE` and the standard SOPS key-file locations are optional fallbacks only. Stop and provide actionable setup guidance if SOPS cannot access a usable key or decrypt the template.

Run the bootstrap helper once as part of app creation, passing each random variable and its byte count directly. Do not include user-supplied or shared values:

```sh
bash scripts/generate-sops-secrets.sh services/<app>/secret.sops.env VARIABLE=BYTE_COUNT [VARIABLE=BYTE_COUNT ...]
```

The helper generates a cryptographically secure hexadecimal value only when a requested variable already exists and its decrypted value is exactly `GENERATE`. It preserves every existing non-sentinel value, along with comments, order, and unrelated values. If no sentinel values need generation, it exits successfully without rewriting the file.

This helper is only for generate-once bootstrap. Rotate existing values manually with `sops edit`; never use the helper for rotation or run it concurrently against the same file. Never commit `CHANGE_ME` placeholders for generated secrets. Populate user-supplied values separately through SOPS, and output a summary table that identifies each variable as random, user-supplied, or shared without revealing values.

### Step 3 — Classify persistent state and add a database backup sidecar

For every persistent volume declared in Step 1, classify each path as one of:

- **Database** — an embedded or external data store with its own consistency semantics (WAL, transactions). A raw filesystem snapshot mid-write carries non-zero corruption risk without engine cooperation.
- **Critical mutable file state** — hand-authored or generated files that are expensive or impossible to reconstruct (device pairings, credentials, UI-authored configuration) but are not a formal database engine.
- **Regeneratable cache** — safe to lose; rebuilt automatically or holds low-value history/log data.
- **External/media data** — large media/library content stored outside `./data` (typically on `archive-pool`), already covered by the archive-pool Cloud Sync tasks.

Record the classification for every persistent path in the service's README (Step 7) and, for any embedded database, in `docs/BACKUP.md`'s Persistent State Inventory (Step 6).

**Every stateful database needs an application-consistent backup sidecar** (`tiredofit/db-backup` v4, or the maintained `nfrastack/db-backup` 4.9.2 compatibility release) unless a reviewed exception explains why ZFS snapshots alone are sufficient. An exception must be written down — in the service's README and in `docs/BACKUP.md`'s Persistent State Inventory — never left implicit or silently skipped.

When a sidecar is required:

- Follow an existing sidecar pattern (e.g. `services/memos/compose.yaml`, `services/gatus/compose.yaml`) — `MODE=MANUAL`, `MANUAL_RUN_FOREVER=FALSE`, `DEFAULT_COMPRESSION=ZSTD`, `DEFAULT_CHECKSUM=SHA1`, `DEFAULT_ENCRYPT=TRUE`, `DEFAULT_ENCRYPT_PASSPHRASE=${DB_ENC_PASSPHRASE}`, `DEFAULT_CLEANUP_TIME=2880` (48-hour retention).
- Output encrypted dumps to `./backups/db-backup` — never `./data` or `./config` — so they are picked up by the dccd freshness check and the existing Cloud Sync layers.
- Name the container `<app>-db-backup`. `dccd.sh -B` (enabled by default via `dccd-all`) discovers sidecars by this `*-db-backup` naming convention and fails the deploy if one exits non-zero or its last successful run is stale (> 48 hours).
- Add `DB_ENC_PASSPHRASE` to `services/<app>/secret.sops.env` as a random, app-owned secret — never share a passphrase across apps.
- Add the new sidecar to the `Covered Databases` table in `docs/BACKUP.md` (Step 6), and add app-specific restore guidance to `docs/BACKUP.md`'s Restore a Database Dump section (extend an existing engine-specific subsection — e.g. SQLite, PostgreSQL, MongoDB — where the engine matches). Link to it from the service's README "Database Backup" section (Step 7).
- Exercise the backup and restore path with a representative synthetic test before merging: seed a throwaway record, run the sidecar once, decrypt/decompress the dump, and restore it into a scratch instance of the same engine. The weekly `backup-restore-test` CI job only proves the generic `tiredofit`/`nfrastack` workflow — it does not substitute for validating this app's specific schema/data on first adoption.
- End the final response for this app with an honest status report, not a claim of production deployment. Cover, in order: (1) the backup behavior actually implemented in the compose file (sidecar image, cadence, compression/checksum/encryption, retention, output path); (2) the synthetic backup/restore evidence actually obtained during this change — the seed/backup/decrypt/restore result from the bullet above, or an explicit statement that it has not yet been run; (3) the exact post-merge operator deployment/run steps required (e.g. `dccd-app <app>`, then `dccd-all`) so the sidecar executes at least once on the target host; and (4) a link to the documented restore path. Only describe the sidecar as "deployed" or "running successfully in production" when there is actual host evidence for that specific run (e.g. a real `docker compose`/`dccd.sh -B` log, exit code, or operator confirmation from the target host) obtained during this session — before that evidence exists, describe it as implemented and validated in a synthetic test, pending the operator's post-merge deployment.

#### SOPS/1Password prerequisite for the backup passphrase

`DB_ENC_PASSPHRASE` (and any other generated backup-encryption secret) must go through the same preflight as every other generated secret — never plaintext, never a placeholder:

1. Confirm the 1Password CLI integration is enabled and the vault is unlocked (e.g. `op whoami` succeeds), or confirm the equivalent for whatever identity is configured.
2. Configure `SOPS_AGE_KEY_CMD` (preferred) — e.g. `export SOPS_AGE_KEY_CMD='op read "op://<vault>/<item>/<field>"'` — or another valid SOPS identity (`SOPS_AGE_KEY_FILE` or a standard key-file location) if 1Password is not used.
3. Prove decryption works before editing anything, e.g. `sops -d services/<app>/secret.sops.env >/dev/null` (or decrypt an existing app's file as a smoke test) must succeed.
4. Set `DB_ENC_PASSPHRASE=GENERATE` in the encrypted file, then run `bash scripts/generate-sops-secrets.sh services/<app>/secret.sops.env DB_ENC_PASSPHRASE=<byte_count>` to fill it in. Never hand-type a passphrase or commit a `CHANGE_ME`/plaintext value.
5. **Stop and report the blocker** if SOPS cannot access a usable key or decrypt the template — do not fall back to an unencrypted secret, a hardcoded value, or skip encryption "temporarily."

### Step 4 — Register the network in Traefik

Add the app's `<app>-frontend` network to `services/traefik/compose.yaml`:

- Add it to the `traefik` service's `networks:` list
- Add the external network definition at the bottom of the file

### Step 5 — Add DNS records

Add the app's subdomain(s) to `services/adguard/config/unbound/conf.d/a-records.conf`, pointing to the correct `${IP_*}` variable for the server it runs on (e.g. `${IP_SVLNAS}` for NAS-hosted apps). Keep entries alphabetically sorted within the Internal or External section.

If unsure what host the app should run on, ask the user.

### Step 6 — Update documentation

Update these files (keep tables alphabetically sorted by app name):

| File                     | What to update                                                                                                                                   |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `README.md`              | Apps table row, dataset list entry                                                                                                               |
| `docs/index.md`          | Keep in sync with README.md (plain Markdown only, no HTML)                                                                                       |
| `docs/ARCHITECTURE.md`   | Init container table entries, shared env entries, access model section                                                                           |
| `docs/INFRASTRUCTURE.md` | UID/GID table entries, shared purpose group entries, storage section                                                                             |
| `docs/BACKUP.md`         | Covered Databases table (if a backup sidecar was added in Step 3), or the Persistent State Inventory (if a documented exception applies instead) |

### Step 7 — Create per-service documentation

Create `services/<app>/README.md` with standard sections:

- Title, description, why this app
- Compose file links
- Access information (URL, auth method)
- Architecture (services, networks, volumes)
- Secrets table
- First-run setup
- Upgrade notes (if applicable)
- A "Database Backup" section for any embedded database from Step 3 (cadence, compression, checksum, encryption, retention, output path, restore link) — see `services/memos/README.md` or `services/gatus/README.md` for the expected shape

For a TrueNAS-hosted app declared in `truenas-apps.json`, the first-run setup must document the complete post-merge rollout in Step 11. Use the helper command instead of manual group, user, or dataset instructions:

```sh
sudo bash scripts/truenas-prep-app.sh <app>
```

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

### Step 9 — Configure TrueNAS host provisioning

For a TrueNAS-hosted app, add a schema-valid `apps.<app>` entry to
`truenas-apps.json`. Each entry must set:

- `account_name`: the dedicated `svc-app-<app>` user and group
- `account_id`: the unique shared UID/GID in the `3100–3199` per-app range
- `admin_group_member`: whether the TrueNAS administrator needs auxiliary
  membership in the app group

Set `admin_group_member: true` only when the TrueNAS administrator needs access
to app-owned runtime paths. Use `false` for simple apps without that
requirement. The helper reads the entry dynamically, and its supported-app
usage output is generated from the registry keys; do not maintain a separate
supported-app list.

Do not add registry entries for apps deployed to non-TrueNAS hosts. If a
TrueNAS-hosted app cannot safely use the helper, document the justified
exception and specify the precise manual account, dataset, ownership,
permission, and other host steps required.

The JSON schema, CI, and Lefthook validate the registry and its service
directory references. Add or update relevant registry and provisioning coverage
under `tests/truenas-prep-app/`, then run the repository's normal test workflow:

```sh
mise exec -- check-jsonschema --schemafile truenas-apps.schema.json truenas-apps.json
task test
```

The host preparation helper requires `jq` on `PATH` to read the JSON
provisioning registry and construct TrueNAS API payloads.

Minimize dependencies in any host-side provisioning logic added for the app.
Before using another external command or library, verify it against the actual
TrueNAS baseline or a documented provisioning path.
Prefer shell built-ins and existing dependencies; reuse `jq` rather than adding
`yq` for this JSON registry. Python may be used when appropriate after
verifying its interpreter and required libraries against the host baseline,
but its standard library does not parse YAML. JSON plus the existing `jq`
dependency avoids adding PyYAML or another package for this helper. Do not
assume that `mise`-managed development or CI tools exist at TrueNAS runtime. An
unavoidable dependency needs an explicit availability check, a documented
installation or provisioning path, and host-level validation; otherwise,
redesign the implementation. Add coverage for the missing-command path when
the dependency is optional or not guaranteed. For this registry, retain the
test proving that it loads when `yq` is absent.

If the helper itself changes, also validate its shell syntax and lint:

```sh
bash -n scripts/truenas-prep-app.sh
mise exec -- shellcheck scripts/truenas-prep-app.sh
```

### Step 10 — Validate

```sh
docker compose -f services/<app>/compose.yaml config --quiet
```

Warnings about unset env vars (e.g. `DOMAINNAME`) are expected — secrets are decrypted at deploy time. Warnings are fine; errors are not.

### Step 11 — Document post-merge host steps

For an app declared in `truenas-apps.json`, document this complete rollout for
the operator on `svlnas`. The aliases must already be sourced from
`/mnt/vm-pool/apps/scripts/aliases.sh`.

1. Pull the merged changes and decrypt SOPS files while limiting the first pass
   to the new app:

   ```sh
   dccd-app <app>
   ```

   Because the TrueNAS Custom App does not exist yet, dccd will report that its
   TrueNAS app config directory is missing and skip deployment. This is expected
   during onboarding. Do not run `dccd-all` first: Traefik may already reference
   the new frontend network before its Custom App and network exist.
2. From the updated TrueNAS checkout, provision the registry-declared account,
   group, and child dataset:

   ```sh
   cd /mnt/vm-pool/apps
   sudo bash scripts/truenas-prep-app.sh <app>
   ```

   The helper preserves the checked-out files while creating the child dataset.
3. In the TrueNAS UI, create a Custom App named `<app>` with:

   ```yaml
   include:
     - /mnt/vm-pool/apps/services/<app>/compose.yaml
   services: {}
   ```

4. Run the canonical final deployment:

   ```sh
   dccd-all
   ```

   This force-deploys all TrueNAS apps in the normal order, includes the new app
   and dependent integrations such as AdGuard and Traefik, decrypts secrets, and
   runs the default backup freshness check.
5. Complete the application-specific first-run setup and verify health and
   access.

#### Final-response contract

After completing a new TrueNAS app implementation, always end the final user
response with this rollout as a concise, command-oriented operator handoff.
The `<app>` tokens in this skill are drafting placeholders only. Resolve every
one to the app's actual registry key in the delivered response, including in
headings, commands, the Custom App name, paths, and YAML. Do not leave `<app>`
or any other placeholder for the operator to edit.

The final handoff must contain, in order:

1. A standalone `sh` block containing `dccd-app <app>`.
2. A standalone `sh` block containing:

   ```sh
   cd /mnt/vm-pool/apps
   sudo bash scripts/truenas-prep-app.sh <app>
   ```

3. A separately labeled **TrueNAS Custom App name** set to `<app>`.
4. A standalone, copy-paste-ready `yaml` block containing:

   ```yaml
   include:
     - /mnt/vm-pool/apps/services/<app>/compose.yaml
   services: {}
   ```

   This block is the TrueNAS Custom App definition that includes the tracked
   Compose file. Do not output the service's full `compose.yaml`.
5. A standalone `sh` block containing `dccd-all`.
6. The concrete application-specific first-run actions, then health and access
   verification. Do not use a generic first-run placeholder. For Memos, for
   example, instruct the operator to create the first account and configure
   the access and registration policy.

The delivered blocks must already contain the actual app name and be safe to
paste without editing. Do not add raw `git pull` or raw `dccd.sh` commands
unless troubleshooting or explicitly requested.

Do not replace this sequence with raw `git pull`, raw `dccd.sh` invocations, or
an improvised series of targeted deployments unless troubleshooting or
explicitly requested. Do not attempt to run the helper from the development
worktree or duplicate its group, user, dataset, or directory setup as manual
instructions.

Only for a justified TrueNAS exception that cannot safely use the helper, output
the reason and precise manual host steps. Do not claim that an undeclared app is
supported. Non-TrueNAS apps must not be added to the registry or given this
TrueNAS rollout.

## Checklist

Use this as a final review before committing:

- [ ] `compose.yaml` follows all security conventions (read_only, no-new-privileges, cap_drop, mem_limit, pids_limit)
- [ ] Every container has a health check
- [ ] Init container uses busybox pattern and only chowns `./data`
- [ ] `./config` volumes are mounted `:ro`
- [ ] Image is digest-pinned with explicit registry prefix
- [ ] `secret.sops.env` is encrypted
- [ ] Random variables used encrypted literal `GENERATE` sentinels before the helper ran
- [ ] Random secrets were generated once; no generated value uses a `CHANGE_ME` placeholder
- [ ] User-supplied and shared values were excluded from helper arguments
- [ ] Existing secrets were not rotated by the helper
- [ ] Every persistent path is classified (database, critical mutable file state, regeneratable cache, or external data)
- [ ] Every embedded database has an application-consistent backup sidecar, or a documented, reviewed exception in the service README and `docs/BACKUP.md`
- [ ] Backup sidecar writes encrypted, ZSTD-compressed, SHA1-checksummed dumps to `./backups/db-backup` (never `./data`/`./config`) with 48-hour retention
- [ ] Backup sidecar container is named `<app>-db-backup` for the `dccd.sh -B` freshness check
- [ ] `DB_ENC_PASSPHRASE` (or equivalent) was generated via the SOPS/1Password preflight — 1Password CLI authenticated/unlocked, a valid SOPS identity confirmed, decryption proven before editing, `GENERATE` + `scripts/generate-sops-secrets.sh` used, never plaintext or a placeholder
- [ ] `docs/BACKUP.md` Covered Databases table and Restore a Database Dump section are updated (or the Persistent State Inventory records the reviewed exception)
- [ ] A representative synthetic backup/restore test was performed and confirmed before merge
- [ ] Final response reports the backup sidecar's implemented behavior, synthetic restore evidence, required post-merge deployment/run steps, and restore-doc link — without claiming production deployment or a successful run unless actual host evidence exists
- [ ] Traefik network and labels are configured
- [ ] DNS A-record is added
- [ ] README.md, docs/index.md, ARCHITECTURE.md, INFRASTRUCTURE.md, BACKUP.md are updated
- [ ] Per-service README.md is created with docs symlink, including a Database Backup section for any embedded database
- [ ] mkdocs.yml nav is updated
- [ ] TrueNAS-hosted app has a schema-valid `truenas-apps.json` entry, or an unsupported exception is explicitly justified with precise manual host steps
- [ ] Post-merge rollout starts with `dccd-app <app>` and documents the expected missing TrueNAS config skip
- [ ] Post-merge rollout runs `truenas-prep-app.sh <app>` from the updated TrueNAS checkout
- [ ] Post-merge rollout creates the named TrueNAS Custom App with the absolute compose include
- [ ] Post-merge rollout finishes with `dccd-all` before application-specific setup
- [ ] Final response ends with the complete, command-oriented TrueNAS operator handoff
- [ ] Final handoff resolves every placeholder to the actual app name in commands, paths, the separately identified Custom App name, and YAML
- [ ] Final handoff provides standalone, copy-paste-ready Custom App YAML rather than the full service Compose file
- [ ] Final handoff states concrete app-specific first-run actions after `dccd-all`
- [ ] Registry key, generated helper usage, first-run documentation, and the reported post-merge sequence agree
- [ ] Registry schema and service directory validation pass
- [ ] TrueNAS host-side dependencies are guaranteed or explicitly checked, provisioned, documented, and host-validated
- [ ] Tests cover absent optional or non-guaranteed host commands where relevant
- [ ] Relevant registry and provisioning tests are updated and pass
- [ ] Helper syntax and shell lint pass when the helper changes
- [ ] `docker compose config --quiet` passes
