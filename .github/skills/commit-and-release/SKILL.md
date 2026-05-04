---
name: commit-and-release
description: >
    Guide for writing Conventional Commit messages, committing changes, and
    creating releases in this repository. Use when asked to commit, write a
    commit message, stage files, push, or create/cut a release.
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

## Commit workflow (step-by-step procedure)

Follow these steps in order every time the user asks to commit, push, or "commit & push".

### Step 1 — Inspect what changed

```sh
git diff --stat HEAD
git status --short
```

Use this to understand the scope: which services, which file types, how many files.

### Step 2 — Stage the files

Prefer explicit paths over `git add .`:

```sh
git add services/immich/compose.yaml docs/ARCHITECTURE.md
```

If the user has already staged files, skip this step.

### Step 3 — Derive and validate the commit message

Draft a message following the Conventional Commits format below.
Then validate it with `cog verify` before asking the user:

```sh
mise exec -- cog verify "feat(immich): add hardware transcoding support"
```

Exit code 0 = valid. If it fails, fix the message and retry.

### Step 4 — Ask the user to confirm the commit message

**MANDATORY**: Before committing, use the `vscode_askQuestions` tool to present the proposed commit message and ask for confirmation. Provide the message as an option the user can click — do not just print it in chat.

Example question structure:

- Header: "Commit message"
- Question: "Does this commit message look right?"
- Options: the proposed message as a selectable option, plus "Let me edit it" as a free-form alternative
- Set `allowFreeformInput: true` so the user can type a corrected message

If the user selects the proposed message, proceed. If they provide a different message, use that one and re-run `cog verify` before continuing.

### Step 5 — Run the pre-commit hook

Run lefthook explicitly so linting errors are surfaced before the commit:

```sh
mise exec -- lefthook run pre-commit
```

If any check fails, **stop and report the errors**. Do not commit until all checks pass.

### Step 6 — Commit

```sh
git commit -m "<confirmed-message>"
```

The `commit-msg` hook will re-run `cog verify` automatically. Both hooks must pass.

### Step 7 — Push

```sh
git push
```

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

Releases are owned by Release Please through `.github/workflows/release-please.yml`. Do not run `cog bump` to cut releases, push tags, or regenerate `CHANGELOG.md` for normal releases.

### Release tooling ownership

| Tool/file                              | Owns                                                                                                                                                                                                                                                                 |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.github/workflows/release-please.yml` | Opens or updates draft release PRs on pushes to `main`, then creates the release tag and publishes the GitHub Release after the release PR is merged. Uses the reusable `DevSecNinja/.github` Release Please workflow and the DevSecNinja Release Please GitHub App. |
| `release-please-config.json`           | Release Please configuration: `release-type` `simple`, package `truenas-apps`, `CHANGELOG.md` changelog path, `include-v-in-tag: true`, `skip-github-release: false`, and `draft-pull-request: true`.                                                                |
| `.release-please-manifest.json`        | Release Please version manifest; tracks the current released version.                                                                                                                                                                                                |
| `cog` / `cog.toml`                     | Commit-message validation only via `cog verify`. Version bumping and CHANGELOG generation are owned by Release Please.                                                                                                                                               |

### Normal release flow

1. Land changes on `main` using Conventional Commits. Release Please derives the next SemVer version from commits on `main`:

    | Commit signal                          | Version bump |
    | -------------------------------------- | ------------ |
    | `fix`                                  | PATCH        |
    | `feat`                                 | MINOR        |
    | `BREAKING CHANGE` footer or `!` marker | MAJOR        |

2. On each push to `main`, Release Please opens or updates a draft `chore(main): release vX.Y.Z` PR.
3. Review the Release Please PR like any normal PR. It contains the generated `CHANGELOG.md` updates and `.release-please-manifest.json` version update.
4. Wait for required CI checks to pass.
5. Merge the Release Please PR when ready. The merge creates the `vX.Y.Z` tag and publishes the GitHub Release automatically because `skip-github-release` is `false`.

### Troubleshooting

Rerun the Release Please workflow manually only when troubleshooting a stalled or failed Release Please PR. Do not hand-edit `CHANGELOG.md` for normal releases.

---

## Release complete

After every successful release, end with a celebrative message. Be enthusiastic, reference the version number, and congratulate the team on shipping. Make it fun — this is a milestone worth celebrating! Example:

> "SHIP IT! v0.12.0 is now LIVE and sailing into production! The stacks are deployed, the changelog is fresh, and the CI is green. Take a beer — you've earned it!"
