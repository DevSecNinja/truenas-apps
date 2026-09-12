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
- [truenas-apps.yaml](../../../truenas-apps.yaml) — add a schema-valid `apps.<name>` entry for each supported TrueNAS-hosted app
- [truenas-apps.schema.json](../../../truenas-apps.schema.json) — required registry fields, account constraints, and validation rules
- [truenas-prep-app.sh](../../../scripts/truenas-prep-app.sh) — idempotent host provisioning driven by the manifest

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

### Step 3 — Register the network in Traefik

Add the app's `<app>-frontend` network to `services/traefik/compose.yaml`:

- Add it to the `traefik` service's `networks:` list
- Add the external network definition at the bottom of the file

### Step 4 — Add DNS records

Add the app's subdomain(s) to `services/adguard/config/unbound/conf.d/a-records.conf`, pointing to the correct `${IP_*}` variable for the server it runs on (e.g. `${IP_SVLNAS}` for NAS-hosted apps). Keep entries alphabetically sorted within the Internal or External section.

If unsure what host the app should run on, ask the user.

### Step 5 — Update documentation

Update these files (keep tables alphabetically sorted by app name):

| File                     | What to update                                                         |
| ------------------------ | ---------------------------------------------------------------------- |
| `README.md`              | Apps table row, dataset list entry                                     |
| `docs/index.md`          | Keep in sync with README.md (plain Markdown only, no HTML)             |
| `docs/ARCHITECTURE.md`   | Init container table entries, shared env entries, access model section |
| `docs/INFRASTRUCTURE.md` | UID/GID table entries, shared purpose group entries, storage section   |

### Step 6 — Create per-service documentation

Create `services/<app>/README.md` with standard sections:

- Title, description, why this app
- Compose file links
- Access information (URL, auth method)
- Architecture (services, networks, volumes)
- Secrets table
- First-run setup
- Upgrade notes (if applicable)

For a TrueNAS-hosted app declared in `truenas-apps.yaml`, the first-run setup must document the complete post-merge rollout in Step 10. Use the helper command instead of manual group, user, or dataset instructions:

```sh
sudo bash scripts/truenas-prep-app.sh <app>
```

Then generate the docs symlink and register the page:

```sh
bash scripts/generate-docs-symlinks.sh
```

Add the entry to the `Services:` section in `mkdocs.yml` in alphabetical order by display name.

### Step 7 — Multi-server setup (if applicable)

If the app will run on a non-TrueNAS server:

1. Add it to the appropriate server in `servers.yaml`
2. If the server also has Traefik, add the frontend network to `services/traefik/compose.<server>.yaml`
3. Re-run `scripts/generate-sops-rules.sh` to update `.sops.yaml` creation rules

### Step 8 — Configure TrueNAS host provisioning

For a TrueNAS-hosted app, add a schema-valid `apps.<app>` entry to
`truenas-apps.yaml`. Each entry must set:

- `account_name`: the dedicated `svc-app-<app>` user and group
- `account_id`: the unique shared UID/GID in the `3100–3199` per-app range
- `admin_group_member`: whether the TrueNAS administrator needs auxiliary
  membership in the app group

Set `admin_group_member: true` only when the TrueNAS administrator needs access
to app-owned runtime paths. Use `false` for simple apps without that
requirement. The helper reads the entry dynamically, and its supported-app
usage output is generated from the manifest keys; do not maintain a separate
supported-app list.

Do not add manifest entries for apps deployed to non-TrueNAS hosts. If a
TrueNAS-hosted app cannot safely use the helper, document the justified
exception and specify the precise manual account, dataset, ownership,
permission, and other host steps required.

The JSON schema, CI, and Lefthook validate the manifest and its service
directory references. Add or update relevant registry and provisioning coverage
under `tests/truenas-prep-app/`, then run the repository's normal test workflow:

```sh
mise exec -- check-jsonschema --schemafile truenas-apps.schema.json truenas-apps.yaml
task test
```

If the helper itself changes, also validate its shell syntax and lint:

```sh
bash -n scripts/truenas-prep-app.sh
mise exec -- shellcheck scripts/truenas-prep-app.sh
```

### Step 9 — Validate

```sh
docker compose -f services/<app>/compose.yaml config --quiet
```

Warnings about unset env vars (e.g. `DOMAINNAME`) are expected — secrets are decrypted at deploy time. Warnings are fine; errors are not.

### Step 10 — Document post-merge host steps

For an app declared in `truenas-apps.yaml`, document this complete rollout for
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
2. From the updated TrueNAS checkout, provision the manifest-declared account,
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
one to the app's actual manifest key in the delivered response, including in
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
supported. Non-TrueNAS apps must not be added to the manifest or given this
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
- [ ] Traefik network and labels are configured
- [ ] DNS A-record is added
- [ ] README.md, docs/index.md, ARCHITECTURE.md, INFRASTRUCTURE.md are updated
- [ ] Per-service README.md is created with docs symlink
- [ ] mkdocs.yml nav is updated
- [ ] TrueNAS-hosted app has a schema-valid `truenas-apps.yaml` entry, or an unsupported exception is explicitly justified with precise manual host steps
- [ ] Post-merge rollout starts with `dccd-app <app>` and documents the expected missing TrueNAS config skip
- [ ] Post-merge rollout runs `truenas-prep-app.sh <app>` from the updated TrueNAS checkout
- [ ] Post-merge rollout creates the named TrueNAS Custom App with the absolute compose include
- [ ] Post-merge rollout finishes with `dccd-all` before application-specific setup
- [ ] Final response ends with the complete, command-oriented TrueNAS operator handoff
- [ ] Final handoff resolves every placeholder to the actual app name in commands, paths, the separately identified Custom App name, and YAML
- [ ] Final handoff provides standalone, copy-paste-ready Custom App YAML rather than the full service Compose file
- [ ] Final handoff states concrete app-specific first-run actions after `dccd-all`
- [ ] Manifest key, generated helper usage, first-run documentation, and the reported post-merge sequence agree
- [ ] Manifest schema and service directory validation pass
- [ ] Relevant registry and provisioning tests are updated and pass
- [ ] Helper syntax and shell lint pass when the helper changes
- [ ] `docker compose config --quiet` passes
