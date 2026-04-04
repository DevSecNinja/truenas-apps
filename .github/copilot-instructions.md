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
  ARCHITECTURE.md        # Compose conventions, security rules, UID/GID allocation
  DATABASE-UPGRADES.md   # PostgreSQL upgrade procedures (pgautoupgrade)
  DISASTER-RECOVERY.md   # Full rebuild procedures

.github/
  workflows/
    lint.yml             # PR/push CI: dprint, yamlfmt, compose config, checkov,
                         #   actionlint, gitleaks, shellcheck, shfmt, trivy, zizmor
    image-security.yml   # Weekly: stale image detection + Trivy image scans
    todo-to-issue.yml    # Converts TODO comments to GitHub issues on push to main
    labeler.yml          # Auto-labels PRs based on changed paths
    label-sync.yml       # Syncs repo labels from .github/labels.yaml
  prompts/
    new-docker-app.prompt.md  # Reusable prompt for adding a new app
```

## Compose File Conventions (MUST follow)

Read `docs/ARCHITECTURE.md` before editing any compose file. Key rules:

- **Images**: Always include explicit registry prefix (`docker.io/library/...`, `ghcr.io/...`). Always digest-pinned (`@sha256:...`). Bare names like `busybox` are forbidden.
- **Security**: Every container must have `read_only: true`, `no-new-privileges`, `cap_drop: ALL`, `mem_limit`, `pids_limit: 100`. Add `cap_add` only when provably required with a comment explaining why.
- **Health checks**: Mandatory on every service (required for `--wait` deploys).
- **Init containers**: Required when a service uses `user: "UID:GID"` with writable volumes. Use the busybox init pattern from ARCHITECTURE.md. Must chown `./config` dirs with `775`/`664` permissions.
- **Networks**: Each app gets its own `<app>-frontend` network. Must be added to `services/traefik/compose.yaml`.
- **Volumes**: Mount `:ro` wherever the container only reads.
- **Shared env**: All stacks reference `../shared/env/tz.env` for timezone.

## Adding a New App

Use the prompt at `.github/prompts/new-docker-app.prompt.md` as a checklist. Key steps:

1. Create `services/<app>/compose.yaml` following ARCHITECTURE.md patterns
2. Create `services/<app>/secret.sops.env` listing required secret variables
3. Add the app's frontend network to `services/traefik/compose.yaml`
4. Add DNS records to `services/adguard/config/unbound/a-records.conf`
5. Update `README.md` (apps table + dataset list)
6. Update `docs/ARCHITECTURE.md` (UID/GID table, init container table)
7. Validate: `docker compose -f services/<app>/compose.yaml config --quiet`

## Key Gotchas

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
