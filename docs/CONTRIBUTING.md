# Contributing

This page covers the development workflow for maintaining this repository: dependency management, commit conventions, and the release process.

## Renovate

Dependency updates are managed by Renovate. The configuration lives in `renovate.json5` (root) and split files under `.renovate/`:

| File                              | Purpose                                                              |
| --------------------------------- | -------------------------------------------------------------------- |
| `renovate.json5`                  | Root config — global settings and `extends` index                    |
| `.renovate/autoMerge.json5`       | Auto-merge policy for GitHub Actions                                 |
| `.renovate/customManagers.json5`  | Regex managers for SOPS version, mise min_version, workflow versions |
| `.renovate/groups.json5`          | Grouped updates (postgres, mise)                                     |
| `.renovate/labels.json5`          | PR labels by update type and datasource                              |
| `.renovate/packageRules.json5`    | Release age gates, stale-dependency flag, linuxserver versioning     |
| `.renovate/semanticCommits.json5` | Scoped commit messages with version arrows                           |

### Update timing policy

All updates must meet a minimum release age before Renovate opens a PR, giving time for bad releases to be retracted:

| Update type            | Manager / datasource       | Minimum age           |
| ---------------------- | -------------------------- | --------------------- |
| minor / patch          | `actions/*` GitHub Actions | 3 days, auto-merged   |
| digest                 | All GitHub Actions         | 14 days, auto-merged  |
| minor / patch          | All other GitHub Actions   | 14 days, manual merge |
| major                  | Everything                 | 14 days, manual merge |
| minor / patch / digest | Docker images              | 14 days, manual merge |
| minor / patch / digest | GitHub Releases            | 14 days, manual merge |
| minor / patch / digest | `mise` tools               | 14 days, manual merge |

Auto-merges use `automergeType: "branch"` (direct push, no PR) and require CI to pass. Major updates always require a manual merge regardless of datasource.

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
