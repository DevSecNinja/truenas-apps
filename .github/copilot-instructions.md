# Copilot Instructions — truenas-apps

## Repository Overview

This is a **Docker Compose GitOps repository** for a TrueNAS home-lab server. It contains no application source code — only Docker Compose stack definitions, configuration files, shell scripts, and GitHub Actions workflows. Each app under `services/` has a `compose.yaml`, a `secret.sops.env` (SOPS-encrypted secrets), and optional `config/` directories.

## Tool Chain

All linting/formatting tools are managed by **mise** (`.mise.toml`). Always run tools via `mise exec --`:

```sh
mise exec -- dprint check          # Markdown formatting
mise exec -- yamlfmt -lint FILE    # YAML formatting
mise exec -- shellcheck FILE       # Shell linting
mise exec -- shfmt --diff FILE     # Shell formatting
mise exec -- actionlint            # GitHub Actions linting
mise exec -- checkov -d .          # Infrastructure-as-code security
mise exec -- trivy fs --scanners misconfig,secret .
```

If mise tools are not yet installed, run `mise install` first.

## Validation — Always Run Before Committing

Run the full pre-commit suite: `mise exec -- lefthook run pre-commit`

If lefthook is not installed in git hooks, run `mise exec -- lefthook install` first.

### Individual Checks (CI runs all of these on PRs)

| Check              | Command                                                                                       | Scope                     |
| ------------------ | --------------------------------------------------------------------------------------------- | ------------------------- |
| Markdown format    | `mise exec -- dprint check`                                                                   | `**/*.md`                 |
| YAML format        | `find . \( -name '*.yaml' -o -name '*.yml' \) -print0 \| xargs -0 mise exec -- yamlfmt -lint` | `**/*.yaml`, `**/*.yml`   |
| YAML lint          | `mise exec -- yamllint FILE`                                                                  | `**/*.yaml`, `**/*.yml`   |
| Compose validation | `docker compose -f services/<app>/compose.yaml config --quiet`                                | each compose file         |
| Shell lint         | `find . -name '*.sh' -print0 \| xargs -0 mise exec -- shellcheck`                             | `**/*.sh`                 |
| Shell format       | `find . -name '*.sh' -print0 \| xargs -0 mise exec -- shfmt --diff`                           | `**/*.sh`                 |
| Actions lint       | `mise exec -- actionlint`                                                                     | `.github/workflows/*.yml` |
| Actions security   | `mise exec -- zizmor .github/workflows/*.yml`                                                 | `.github/workflows/*.yml` |
| Secrets scan       | `mise exec -- gitleaks detect --redact`                                                       | entire repo               |
| Security scan      | `mise exec -- checkov --skip-download -d .`                                                   | entire repo               |

To auto-fix formatting, replace `--diff` / `check` / `-lint` with the write variant:

- `mise exec -- dprint fmt FILE` (Markdown)
- `mise exec -- yamlfmt FILE` (YAML — also auto-stages)
- `mise exec -- shfmt --write FILE` (shell)

**Compose validation will emit warnings** about unset env vars (e.g. `DOMAINNAME`). This is expected — secrets are decrypted at deploy time, not in CI. Warnings are fine; errors are not.

## Repository Layout

```
.mise.toml              # Tool versions (dprint, yamlfmt, shellcheck, shfmt, trivy, etc.)
.lefthook.toml          # Pre-commit hooks — runs all linters/formatters
.yamlfmt.yaml           # YAML formatter config
.yamllint.yaml          # YAML linter config (comments/line-length disabled)
.markdownlint.yaml      # Markdown linter config
.shellcheckrc           # ShellCheck config (bash dialect, extra checks enabled)
.editorconfig           # Indent: 2 spaces (4 for .md and .sh), LF line endings
.sops.yaml              # SOPS encryption rule: age key for secret.sops.env files
.gitleaks.toml          # Gitleaks secret-scan allowlist
dprint.json             # dprint config (Markdown plugin only)
trivy.yaml              # Trivy config (skips age.key)
renovate.json           # Renovate config (digest-pinning, grouped Postgres updates)
cog.toml                # cocogitto config (bump hooks, tag prefix)
cliff.toml              # git-cliff config (changelog template and commit groups)

services/
  <app>/
    compose.yaml        # Docker Compose stack definition
    secret.sops.env     # SOPS-encrypted secrets (decrypted to .env at deploy time)
    config/             # App config files (git-tracked, mounted as volumes)
    data/               # Persistent data (gitignored)
    backups/            # Backup data (gitignored)
  shared/
    env/
      tz.env            # Shared timezone env file referenced by all stacks

scripts/
  dccd.sh               # Continuous deployment script (cron-driven on TrueNAS)
  gha-image-age-check.sh    # CI: flags stale container images
  gha-trivy-image-scan.sh   # CI: Trivy vulnerability scan of all images

docs/
  ARCHITECTURE.md        # Compose patterns, container security, networking, directory conventions
  CONTRIBUTING.md        # Development workflow: Renovate, commits, releases
  INFRASTRUCTURE.md      # Host setup: UID/GID allocation, storage, multi-server deployment
  DATABASE-UPGRADES.md   # PostgreSQL upgrade procedures (pgautoupgrade)
  DISASTER-RECOVERY.md   # Full rebuild procedures
  RETIRED-SERVICES.md    # Log of retired services with reasoning and last active commit

.github/
  workflows/
    lint.yml             # PR/push CI: dprint, yamlfmt, compose config, checkov,
                         #   actionlint, gitleaks, shellcheck, shfmt, trivy, zizmor
    image-security.yml   # Weekly: stale image detection + Trivy image scans
    todo-to-issue.yml    # Converts TODO comments to GitHub issues on push to main
    labeler.yml          # Auto-labels PRs based on changed paths
    label-sync.yml       # Syncs repo labels from .github/labels.yaml
    release.yml          # Triggered on v* tag push: generates changelog and creates GitHub Release
  skills/
    code-testing/SKILL.md         # Skill for linting, formatting, and security scanning
    new-docker-app/SKILL.md       # Skill for adding a new app
    retire-docker-app/SKILL.md    # Skill for retiring an app
    commit-and-release/SKILL.md   # Skill for commits and releases
    docs-writing/SKILL.md         # Skill for writing documentation
    sops-secrets/SKILL.md         # Skill for safe SOPS secret creation and review
```

## Compose File Conventions (MUST follow)

Read `docs/ARCHITECTURE.md` (compose patterns) and `docs/INFRASTRUCTURE.md` (UID/GID, storage, multi-server) before editing any compose file. Key rules:

- **Images**: Always include explicit registry prefix (`docker.io/library/...`, `ghcr.io/...`). Always digest-pinned (`@sha256:...`). Bare names like `busybox` are forbidden.
- **Security**: Every container must have `read_only: true`, `no-new-privileges`, `cap_drop: ALL`, `mem_limit`, `pids_limit: 100`. Add `cap_add` only when provably required with a comment explaining why.
- **Health checks**: Mandatory on every service (required for `--wait` deploys).
- **Init containers**: Required when a service uses `user: "UID:GID"` with writable volumes. Use the busybox init pattern from ARCHITECTURE.md. Must only chown `./data` (runtime) paths — **never** chown `./config` (git-tracked) directories.
- **Config volumes**: `./config` directories must always be mounted `:ro`. No container may write to git-tracked config at runtime. If runtime writes are needed, copy to `./data` in an init container.
- **Networks**: Each app gets its own `<app>-frontend` network. Must be added to `services/traefik/compose.yaml`.
- **Volumes**: Mount `:ro` wherever the container only reads.
- **Shared env**: All stacks reference `../shared/env/tz.env` for timezone.

## Adding a New App

Use the skill at `.github/skills/new-docker-app/SKILL.md` as a checklist. Key steps:

1. Create `services/<app>/compose.yaml` following ARCHITECTURE.md patterns
2. Create `services/<app>/secret.sops.env` listing required secret variables
3. Add the app's frontend network to `services/traefik/compose.yaml`
4. Add DNS records to `services/adguard/config/unbound/a-records.conf`
5. Update `README.md` (apps table + dataset list)
6. Update `docs/INFRASTRUCTURE.md` (UID/GID table) and `docs/ARCHITECTURE.md` (init container table)
7. Create `services/<app>/README.md` with per-service documentation, then run `bash scripts/generate-docs-symlinks.sh` and add the entry to the `Services:` section in `mkdocs.yml`
8. Validate: `docker compose -f services/<app>/compose.yaml config --quiet`
9. If the app will run on a non-TrueNAS server, add it to the appropriate server in `servers.yaml`
10. If the app runs on a server that also has Traefik, add its frontend network to the Traefik compose override for that server (e.g. `services/traefik/compose.svlazext.yaml`)

### Post-Merge TrueNAS App Rollout (Mandatory)

For a brand-new TrueNAS Custom App, operator handoffs must use the aliases from `/mnt/vm-pool/apps/scripts/aliases.sh`, which must already be sourced:

1. Run `dccd-app <app>` on `svlnas`. It pulls the merged changes and decrypts SOPS files while limiting deployment to the new app. The first run will report that the TrueNAS app config directory is missing and skip deployment because the Custom App does not exist yet; this is expected.
2. From `/mnt/vm-pool/apps`, run `sudo bash scripts/truenas-prep-app.sh <app>` to provision the manifest-declared account, group, and child dataset while preserving checked-out files.
3. In the TrueNAS UI, create a Custom App named `<app>` with:

   ```yaml
   include:
     - /mnt/vm-pool/apps/services/<app>/compose.yaml
   services: {}
   ```

4. Run `dccd-all`. This force-deploys all TrueNAS apps in the normal order, applies dependent AdGuard and Traefik changes, decrypts secrets, and runs the default backup freshness check.
5. Complete the app-specific first-run setup and verify health and access.

Do not use `dccd-all` for the first sync: Traefik may already reference the new frontend network before its Custom App and network exist. Do not replace this handoff with raw `git pull`, raw `dccd.sh` commands, or improvised targeted deployments unless troubleshooting or explicitly requested.

#### Final-response contract

After completing any new TrueNAS app implementation, the final response must
end with a concise, command-oriented operator handoff that follows the rollout
above. It must:

- Substitute the app's actual manifest key in every command, name, path, and
  YAML value. Never leave `<app>` or another placeholder in the delivered
  response.
- Provide `dccd-app` with the actual app name as the first command.
- Provide `cd /mnt/vm-pool/apps` followed by
  `sudo bash scripts/truenas-prep-app.sh` with the actual app name.
- Identify the **TrueNAS Custom App name** separately as the actual app name.
- Provide a standalone, copy-paste-ready YAML block containing only `include`
  with the absolute tracked Compose path and `services: {}`. This is the
  TrueNAS Custom App YAML, not the contents of the service's `compose.yaml`.
- Provide `dccd-all` as the final deployment command.
- State the concrete app-specific first-run actions after `dccd-all`, followed
  by health and access verification. Do not leave a generic first-run
  placeholder; for example, Memos requires creating the first account and
  configuring its access and registration policy.

Keep this handoff safe to paste. Do not add raw `git pull` or raw `dccd.sh`
commands unless the response is explicitly troubleshooting.

## Managing SOPS Secrets

Use the skill at `.github/skills/sops-secrets/SKILL.md` when creating, editing, generating, validating, or troubleshooting encrypted dotenv secrets.

## Retiring an App

Use the skill at `.github/skills/retire-docker-app/SKILL.md` as a checklist. Key mechanisms:

- `dccd.sh -R <app>` tears down a single app (server-aware, applies compose overrides)
- Auto-cleanup in `dccd.sh` detects removed service directories after `git pull` and tears down orphaned projects automatically
- Add an entry to `docs/RETIRED-SERVICES.md` with reason and last active commit
- Post-merge: destroy the TrueNAS dataset and remove the service account manually

## Multi-Server Deployment

- **`servers.yaml`**: Maps servers to their apps. Validated by `servers.schema.json`. TrueNAS (svlnas) is listed for SOPS key scoping but deployed via `-t` mode.
- **`-S <server>` flag**: Deploys only apps assigned to a server. Mutually exclusive with `-a` and `-t`. Requires `yq` on PATH.
- **Compose overrides**: `services/<app>/compose.<server>.yaml` files are auto-detected and applied as Docker Compose overrides. Use these for server-specific network lists, labels, or ports.
- **Per-server Age keys**: `.sops.yaml` creation_rules scope decryption access per server. Run `scripts/generate-sops-rules.sh` after changing server-app mappings.

## Key Gotchas

- **Commit messages**: Follow [Conventional Commits](https://www.conventionalcommits.org) — `type(scope): description` (e.g. `feat(immich): add hardware transcoding`, `fix(traefik): correct TLS options`). Enforced by a `commit-msg` lefthook via `cog verify`.
- **Releases**: Run `cog bump --minor` (or `--patch`) to create a release. It regenerates `CHANGELOG.md` via git-cliff, commits, tags, and pushes. The tag push triggers `release.yml` which auto-creates the GitHub Release. Preview with `cog bump --minor --dry-run`.
- **YAML document start**: All YAML files must begin with `---` (enforced by yamlfmt).
- **Indent**: 2 spaces for YAML; 4 spaces for Markdown and shell scripts (`.editorconfig`).
- **Line endings**: LF only, always end files with a newline.
- **Shell scripts**: Must pass `shellcheck` with the extra checks in `.shellcheckrc` (variable braces, avoid-nullary-conditions, etc.). Format with `shfmt` (4-space indent).
- **GitHub Actions**: All action refs must be pinned to full commit SHAs with a version comment. Must pass `actionlint` and `zizmor`.
- **checkov skips**: Use inline `# checkov:skip=CKV_xxx: reason` comments when a skip is justified.
- **Secrets**: Never commit plaintext secrets. The `.env` files are gitignored. Only `secret.sops.env` (encrypted) is committed.
- **`data/` and `backups/`**: These directories are gitignored — never try to read or create files there.

## Trust These Instructions

Follow the conventions above. Only search the codebase for additional context if these instructions are incomplete or produce errors. When in doubt, model new files after the closest existing app in `services/`.

## Agent Delegation

- **Documentation tasks** — Always delegate to the **Technical Writer** agent. This includes: writing or updating READMEs, ARCHITECTURE.md, INFRASTRUCTURE.md, CONTRIBUTING.md, docs/index.md, per-service READMEs, and any other Markdown documentation. The main agent should handle compose files, scripts, CI workflows, and all non-documentation code changes, then hand off the doc work to Technical Writer.
- **Code testing tasks** — Delegate to the **Code Tester** agent when writing BATS tests for shell scripts, running linting, formatting checks, security scans, or validation. This includes: writing unit/integration/e2e tests, pre-commit checks, diagnosing CI failures, running targeted lint/format tools, and auto-fixing formatting issues. Use the skill at `.github/skills/code-testing/SKILL.md` for the full procedure.
