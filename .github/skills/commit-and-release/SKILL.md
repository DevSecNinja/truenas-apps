---
name: commit-and-release
description: >
    Guide for writing Conventional Commit messages, committing changes, and
    creating releases in this repository. Use when asked to commit, write a
    commit message, stage files, or create/cut a release.
---

## Commit message format

All commits follow [Conventional Commits](https://www.conventionalcommits.org):

```
<type>(<scope>): <description>
```

**Types:**

| Type       | When to use                                            |
| ---------- | ------------------------------------------------------ |
| `feat`     | New service, new feature, new config capability        |
| `fix`      | Correcting a bug, misconfiguration, or broken behavior |
| `chore`    | Tooling, dependencies, version bumps                   |
| `ci`       | Changes to GitHub Actions workflows or lefthook config |
| `docs`     | Documentation only                                     |
| `refactor` | Code/config restructure without behavior change        |

**Scope** is the service folder name or tool involved (e.g. `immich`, `traefik`, `renovate`, `mise`, `cog`). Multi-service changes may omit the scope.

**Breaking changes** are indicated in one of two ways (or both):

- `!` immediately before the colon: `feat(traefik)!: remove legacy middleware`
- A `BREAKING CHANGE:` footer in the commit body (MUST be uppercase):

  ```
  feat(traefik): remove legacy middleware

  BREAKING CHANGE: chain-auth middleware has been renamed to chain-oauth
  ```

| Commit type       | Version bump |
| ----------------- | ------------ |
| `fix`             | PATCH        |
| `feat`            | MINOR        |
| `BREAKING CHANGE` | MAJOR        |

### Examples

```
feat(radarr): add compose stack with Traefik labels
fix(immich): correct OAuth roleClaim field name
ci: add zizmor workflow security scan
chore(mise): bump git-cliff to 2.12.0
docs(architecture): document init container pattern
```

### Verify before committing

Use `cog verify` to check a message before committing:

```sh
mise exec -- cog verify "feat(immich): add hardware transcoding"
```

Exit code 0 = valid. The `commit-msg` lefthook runs this automatically on every `git commit`.

---

## Making a commit

1. Stage the relevant files — prefer explicit paths over `git add .`:

   ```sh
   git add services/immich/compose.yaml docs/ARCHITECTURE.md
   ```

2. Commit with a Conventional Commit message:

   ```sh
   git commit -m "feat(immich): add hardware transcoding support"
   ```

   The pre-commit hook runs all linters (yamlfmt, shellcheck, checkov, trivy, etc.) automatically. The commit-msg hook validates the message with `cog verify`. Both must pass.

3. For multi-paragraph commit bodies, write the subject line first, leave a blank line, then add detail:

   ```sh
   git commit -m "feat(immich): add hardware transcoding support

   - Mount /dev/dri for VAAPI access
   - Add cap_add: SYS_RAWIO with justification comment
   - Update ARCHITECTURE.md init container table"
   ```

---

## Creating a release

**Prerequisites:** working tree must be clean (all changes committed).

### Dry-run first

Always preview before releasing:

```sh
mise exec -- cog bump --minor --dry-run   # shows next version, e.g. v0.12.0
mise exec -- cog bump --patch --dry-run
```

### Cut the release

```sh
mise exec -- cog bump --minor   # or --patch for bug-fix releases
```

`cog bump` executes this pipeline automatically:

1. Calculates the next semver version from conventional commits since the previous tag
2. Runs `git-cliff` to regenerate `CHANGELOG.md` (range configured in `cog.toml`)
3. Runs `dprint fmt CHANGELOG.md` to ensure it passes CI
4. Stages `CHANGELOG.md` and creates a `chore(version): <version>` commit
5. Creates the `v<version>` git tag
6. Pushes the commit and tag to `origin`

The tag push triggers `.github/workflows/release.yml`, which generates release-scoped notes with `git-cliff --latest --strip all` and auto-creates the GitHub Release — no manual steps on GitHub.com needed.
