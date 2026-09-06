# Contributing

This page covers the development workflow for maintaining this repository: dependency management, commit conventions, and the release process.

## Generating Random SOPS Secrets

For app-owned passwords, passphrases, and tokens, set the initial dotenv value to the literal `GENERATE` and encrypt the template. Keep user-supplied values such as OAuth or SMTP credentials out of the helper arguments, and reference existing shared secrets rather than generating duplicates.

The variables must already exist in `services/<app>/secret.sops.env`, and that dotenv file must already be SOPS-encrypted. With a usable age key configured, run:

```sh
bash scripts/generate-sops-secrets.sh services/<app>/secret.sops.env VARIABLE=BYTE_COUNT [VARIABLE=BYTE_COUNT ...]
```

The helper is generate-once bootstrap only. It generates a cryptographically secure hexadecimal value only when a requested variable exists and its decrypted value is exactly `GENERATE`. Every existing non-sentinel value is preserved. When nothing needs generation, it exits successfully without rewriting the file.

Do not run the helper concurrently against the same encrypted file. Rotate existing values manually:

```sh
sops edit services/<app>/secret.sops.env
```

Never commit `CHANGE_ME` placeholders for generated secrets.

### Recommended age key setup: 1Password CLI

Use SOPS-native `SOPS_AGE_KEY_CMD` so the private key remains in 1Password:

1. [Install the 1Password CLI (`op`)](https://developer.1password.com/docs/cli/get-started/) for the local platform.
2. In 1Password Desktop, enable **Settings > Developer > Integrate with 1Password CLI**.
3. Sign in to 1Password Desktop, unlock the app, and approve any CLI authorization prompt.
4. Configure the secret reference in the current shell:

   ```sh
   export SOPS_AGE_KEY_CMD='op read "op://<vault>/<item>/<field>"'
   ```

SOPS invokes this command internally when it needs the key. Never run `op read` directly, use it in command substitution, or print or log its output. Keep the 1Password item and field narrowly targeted to the required age key.

Alternatively, create a local `sops.op.env` file (the `*.op.env` pattern is gitignored) containing only an `SOPS_AGE_KEY=op://<vault>/<item>/<field>` reference, then inject it for one command:

```sh
op run --env-file sops.op.env -- bash scripts/generate-sops-secrets.sh services/<app>/secret.sops.env VARIABLE=BYTE_COUNT
```

If the key cannot be retrieved or used to decrypt the template, the helper stops with actionable guidance.

### Optional key-file fallback

Use `SOPS_AGE_KEY_FILE` only when 1Password CLI is unavailable. Without that variable, SOPS checks `%APPDATA%\sops\age\keys.txt` on Windows or `${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt` on Linux/WSL. Do not print, log, or read the private key through scripts.

For an already provisioned Windows fallback, restrict the key file ACL to the current user:

```powershell
$keyFile = if ($env:SOPS_AGE_KEY_FILE) {
    $env:SOPS_AGE_KEY_FILE
} else {
    Join-Path $env:APPDATA 'sops\age\keys.txt'
}
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$acl = New-Object System.Security.AccessControl.FileSecurity
$acl.SetAccessRuleProtection($true, $false)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'Allow')
$acl.AddAccessRule($rule)
Set-Acl -Path $keyFile -AclObject $acl
```

For an already provisioned Linux/WSL fallback, restrict the key file to mode `600`:

```sh
key_file="${SOPS_AGE_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt}"
chmod 600 "$key_file"
```

## Renovate

Dependency updates are managed by Renovate. Only `renovate.json5` lives in this repository — every other file below is a **remote preset** in [`DevSecNinja/.github`](https://github.com/DevSecNinja/.github), pulled in through the `extends` list. There is no `.renovate/` directory here.

| File                                                          | Purpose                                                                               |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `renovate.json5`                                              | Root config — global settings, `extends` index, repo-local digest exceptions          |
| `github>DevSecNinja/.github//.renovate/autoMerge.json5`       | Auto-merge policy (`pin`, `pinDigest`, `digest`, `minor`, `patch`)                    |
| `github>DevSecNinja/.github//.renovate/base.json5`            | Shared baseline settings common to all `DevSecNinja` repositories                     |
| `github>DevSecNinja/.github//.renovate/customManagers.json5`  | Regex managers for SOPS version, mise min_version, workflow versions                  |
| `github>DevSecNinja/.github//.renovate/groups.json5`          | Grouped updates (postgres, mise)                                                      |
| `github>DevSecNinja/.github//.renovate/labels.json5`          | PR labels by update type and datasource                                               |
| `github>DevSecNinja/.github//.renovate/packageRules.json5`    | Release age gates, non-Docker-Hub registry gating, stale flag, linuxserver versioning |
| `github>DevSecNinja/.github//.renovate/semanticCommits.json5` | Scoped commit messages with version arrows                                            |

### Update timing policy

All updates must meet a minimum release age before they can merge, giving time for bad releases to be retracted:

| Update type   | Manager / datasource                 | Minimum age | Merge        |
| ------------- | ------------------------------------ | ----------- | ------------ |
| minor / patch | `actions/*` GitHub Actions           | 3 days      | Auto-merged  |
| minor / patch | All other GitHub Actions             | 14 days     | Auto-merged  |
| minor / patch | Docker images                        | 14 days     | Auto-merged  |
| minor / patch | GitHub Releases                      | 14 days     | Auto-merged  |
| minor / patch | `mise` tools                         | 14 days     | Auto-merged  |
| digest        | Docker images pinned to `:latest`    | 14 days     | Auto-merged  |
| digest        | GitHub Actions refs pinned to `main` | 14 days     | Auto-merged  |
| major         | Everything                           | 14 days     | Manual merge |

Auto-merged PRs require CI to pass and carry the `[automerge]` commit-message suffix. Most rules use `automergeType: "pr"` with `platformAutomerge: true`, so GitHub merges the PR itself once every required check is green; the 3-day `actions/*` exception uses `automergeType: "branch"` (direct push, no PR). **Major** updates always require a manual merge, regardless of datasource.

Digest-only updates are **disabled by the shared preset** to reduce PR noise and to avoid auto-merging a hijacked mutable tag. This repository re-enables them in the two cases where the digest is the only thing that ever moves, both in `renovate.json5`: Docker images pinned to `:latest` (#628) and GitHub Actions / reusable-workflow refs pinned to `main` (#636).

### Enforcing the soak without a trusted timestamp

Renovate only derives a release timestamp for Docker images from Docker Hub — it reads `tag_last_pushed` from the `hub.docker.com` API, which is Hub-specific and not part of the OCI specification. The standard Registry V2 `/tags/list` endpoint every other registry serves returns tag names only, and Renovate will not fall back to the OCI `org.opencontainers.image.created` label because the publisher controls it and could forge it to skip the soak.

The 14-day soak is **still enforced** for those images — just by a different mechanism:

1. A rule in `packageRules.json5` matches Docker dependencies whose package name carries an explicit registry host other than Docker Hub (`/^[^/]*\./` combined with `!/^docker\.io\//`).
2. That rule sets `minimumReleaseAgeBehaviour: "timestamp-optional"` — so Renovate opens the PR immediately instead of blocking on a timestamp it cannot obtain — and stamps the branch via `additionalBranchPrefix: "docker-gated-"`.
3. `.github/workflows/renovate-pr-cooldown.yml` calls the shared reusable workflow, which posts the required `pr-cooldown` status check on those `renovate/docker-gated-*` branches. The check stays pending until the PR branch head commit is at least 14 days old; GitHub auto-merge then merges the PR.

Because the same rule sets both the behaviour and the branch prefix, and the workflow gates exactly that prefix, the Renovate config and the gate cannot drift apart.

Two consequences worth knowing:

- There is **no registry allowlist** (removed in `DevSecNinja/.github` PR #312). Any registry nobody has explicitly configured is gated by default, which is fail-safe. Under the previous allowlist a new registry silently got nothing — `dhi.io` was missing for roughly 3.5 months and those images received no updates at all, including security updates (#634).
- Bare Docker Hub names (e.g. `nginx`, `library/nginx`) keep the native soak and are not gated. This repository mandates an explicit registry prefix on every image, so bare names should not appear here anyway.

Background: ADR 0005 in `DevSecNinja/.github` (`docs/design-decisions/0005-pr-age-cooldown-for-untrusted-timestamps.md`), which classifies `pr-cooldown` as a load-bearing control. For why `docker.io` is preferred when the same image is available on several registries, see [Architecture § Image Selection: Registry Preference](ARCHITECTURE.md#image-selection-registry-preference).

### Silently skipped dependencies (`dhi.io`)

Docker Hardened Images prune entire minor lines. When the tag a compose file is pinned to stops existing, `getCurrentVersion` returns null (the shared preset uses `rangeStrategy: "pin"`) and Renovate marks the dependency `skipReason: invalid-value`. The dependency dashboard filters skipped dependencies out, so the image **disappears from the dashboard with no warning** and silently stops receiving updates. This is how four hardened images went roughly 3.5 months without any updates (#634).

<!-- dprint-ignore -->
!!! warning "Symptom"
    A `dhi.io` image that used to appear on the dependency dashboard and no longer does is not up to date — it is unparseable. Check the [catalog](https://hub.docker.com/hardened-images/catalog) and re-pin the compose file to a tag that still exists.

### Rule precedence note

`packageRules` are applied in the order they appear across all `extends` entries — **last matching rule wins** for each property. `autoMerge.json5` is loaded before `packageRules.json5`, so `packageRules.json5` must not contain a `matchManagers: ["github-actions"]` timing rule or it would override the 3-day exception for `actions/*`.

## Commit Message Convention

All commits follow the [Conventional Commits](https://www.conventionalcommits.org) specification:

```
<type>(<scope>): <description>
```

Common types: `feat`, `fix`, `chore`, `docs`, `refactor`, `ci`. The scope is typically the service folder name (e.g. `feat(immich):`, `fix(traefik):`). Compliance is enforced locally by a lefthook `commit-msg` hook using `cog verify`.

## Release Process

Releases are version-tagged on `main` and automatically published as GitHub Releases via a CI workflow.

### Creating a release

```sh
# Bump the minor version (updates CHANGELOG.md, commits, tags, and pushes)
cog bump --minor

# Or patch for bug-fix releases
cog bump --patch

# Dry-run to preview the next version without making changes
cog bump --minor --dry-run
```

`cog bump` orchestrates the full release:

1. Calculates the next semver version from conventional commits since the previous tag
2. Runs `git-cliff --tag <version> --output CHANGELOG.md` to regenerate the full changelog
3. Runs `dprint fmt CHANGELOG.md` to ensure the changelog passes CI formatting checks
4. Creates a `chore(release): bump version to <version>` commit containing the changelog update
5. Creates the `v<version>` git tag
6. Pushes the commit and tag to `origin`

The tag push triggers `.github/workflows/release.yml`, which runs `git-cliff --latest --strip all`
to produce release-scoped notes and creates the GitHub Release automatically.

### Tools

| Tool         | Role                                                             |
| ------------ | ---------------------------------------------------------------- |
| `cog`        | Version bump, bump commit, git tag, push orchestration           |
| `git-cliff`  | Changelog generation (`CHANGELOG.md` + GitHub Release notes)     |
| `cliff.toml` | Commit grouping, body template, GitHub commit link configuration |
| `cog.toml`   | Bump hooks, tag prefix, merge-commit filtering                   |

## Task Runner

[go-task](https://taskfile.dev) provides a unified interface for all repository tasks — testing,
linting, formatting, compose validation, deployment, and more. It is managed by mise alongside the
other tools.

Verify the installation:

```sh
task --version
```

List all available tasks:

```sh
task --list
```

Common workflows:

| Command                 | What it does                                                                     |
| ----------------------- | -------------------------------------------------------------------------------- |
| `task install`          | Install all dependencies (mise tools + BATS libraries)                           |
| `task test`             | Run the full test suite                                                          |
| `task lint`             | Run all linters (YAML, shell, actions, security)                                 |
| `task format`           | Auto-format all files (YAML, shell, Markdown)                                    |
| `task format:check`     | Check formatting without modifying files                                         |
| `task ci:local`         | Run the full CI pipeline locally (format check + lint + compose validate + test) |
| `task ci:quick`         | Quick checks — format and lint only, no tests                                    |
| `task compose:validate` | Validate all compose files                                                       |
| `task pre-commit`       | Run lefthook pre-commit hooks                                                    |
| `task docs:serve`       | Live-preview the MkDocs site locally                                             |

Run `task help` for detailed usage examples.

## Testing

The repository has a [BATS](https://github.com/bats-core/bats-core) suite for `scripts/dccd.sh` and
the SOPS random-secret helper, with 208 tests:

| Category    | Count | What it tests                                                        |
| ----------- | ----- | -------------------------------------------------------------------- |
| Unit        | 134   | DCCD functions and 13 mocked SOPS secret-helper tests                |
| Integration | 70    | DCCD workflows and one integration test using real Age and SOPS      |
| E2E         | 4     | Real Docker containers for DCCD — skipped locally and run separately |

### Running tests

```sh
task test
task test:unit
task test:integration
task test:e2e
task test:file -- tests/dccd/unit/log_message.bats
```

E2E tests require Docker and are skipped unless `DCCD_E2E=1` is set. The `task test:e2e` command
sets this automatically.

### Pre-commit hook

Lefthook runs both the DCCD and SOPS secret unit suites before every commit. CI and the Taskfile also
include both projects' unit and integration tests; DCCD E2E tests run separately with Docker.

### Writing tests

See [tests/README.md](https://github.com/DevSecNinja/truenas-apps/blob/main/tests/README.md) for
the full test writing guide — directory structure, helper reference, mock patterns, and conventions.

## Per-Service Documentation

Each service can have a `README.md` in its directory (e.g. `services/adguard/README.md`). These files are the source of truth for service-specific documentation — architecture, access URLs, init containers, secrets, first-run setup, and upgrade notes.

### MkDocs integration via symlinks

MkDocs can only serve files inside its `docs/` directory. To make service READMEs appear in the MkDocs site without duplicating content, the repo uses symlinks:

```text
docs/services/adguard.md → ../../services/adguard/README.md
docs/services/plex.md    → ../../services/plex/README.md
```

A script generates and maintains these symlinks:

```sh
bash scripts/generate-docs-symlinks.sh
```

**When to run it:**

- After adding a new service with a `README.md`
- After retiring a service (stale symlinks are cleaned up automatically)

The symlinks are committed to Git. Git stores them as text files containing the relative target path, so they work across clones on all platforms that support symlinks.

### Link paths in service READMEs

Because MkDocs resolves links relative to `docs/services/` (the symlink location), cross-references to other docs must use paths relative to that directory — **not** relative to `services/<app>/`. For example, use `[Infrastructure](../INFRASTRUCTURE.md)` (not `../../docs/INFRASTRUCTURE.md`). These links work in MkDocs strict mode; on GitHub the README content is still readable even though the relative link won't resolve from the `services/<app>/` path.

### Adding a new service to MkDocs

1. Create `services/<app>/README.md`
2. Run `bash scripts/generate-docs-symlinks.sh`
3. Add the entry to the `Services:` section in `mkdocs.yml` (alphabetical order by display name):

   ```yaml
   - Services:
       - AdGuard Home: services/adguard.md
       - New App: services/new-app.md
   ```

4. Commit the symlink and `mkdocs.yml` change together
