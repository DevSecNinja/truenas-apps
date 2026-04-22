---
name: code-testing
description: >
    Write BATS tests for shell scripts and run linting, formatting, security
    scanning, and validation checks on the repository. Use when asked to write
    tests, add test coverage, run checks, lint, validate, scan, or verify code
    before committing or in response to CI failures.
---

# Code Testing and Validation

## When to Use

- Writing BATS tests for shell scripts (unit, integration, or E2E)
- Running the full pre-commit validation suite before committing
- Diagnosing CI lint or security scan failures
- Validating a specific file type (YAML, Markdown, shell, compose, workflows)
- Checking for leaked secrets or security misconfigurations
- Verifying formatting compliance after edits

## Reference

See [GitHub Issue #208](https://github.com/DevSecNinja/truenas-apps/issues/208) for the full test framework plan, directory structure, priority matrix, patterns to adopt, and anti-patterns to avoid.

## Prerequisites

All tools are managed by **mise** (`.mise.toml`). If tools are not yet installed:

```sh
mise install
```

If lefthook is not installed in git hooks:

```sh
mise exec -- lefthook install
```

## Writing Tests — BATS Framework

### Directory Structure

```
tests/
  dccd/
    helpers/
      common.bash            # Shared setup: temp dirs, mock PATH, stub functions
      mocks.bash             # Stub generators for docker, git, sops, yq, curl, dig
    unit/                    # One .bats file per function, mocked externals
    integration/             # Mocked docker/git, multi-function flows
    e2e/                     # Real Docker in GitHub Actions
```

### Creating a New Test File

1. Read the function under test in `scripts/dccd.sh`
2. Determine the tier: **unit** (single function, all externals mocked), **integration** (multi-function flow, docker/git mocked), or **e2e** (real Docker)
3. Create `tests/dccd/<tier>/<function_name>.bats`
4. Load shared helpers at the top:

   ```bash
   setup() {
       load '../helpers/common'
       load '../helpers/mocks'
       common_setup  # creates temp dirs, sets MOCK_BIN/MOCK_LOG, prepends to PATH
   }

   teardown() {
       common_teardown  # rm -rf temp dirs
   }
   ```

5. Write tests with descriptive names prefixed by the function name:

   ```bash
   @test "parse_server_apps: exits when yq is missing" {
       rm -f "${MOCK_BIN}/yq"
       run parse_server_apps "myserver"
       assert_failure
       assert_output --partial "yq is required"
   }
   ```

6. Run the test:

   ```sh
   mise exec -- bats tests/dccd/<tier>/<file>.bats
   ```

### Test Conventions

- **Assertions**: Always use `bats-assert` helpers (`assert_success`, `assert_failure`, `assert_output --partial`, `assert_line`). Never use raw `[ "$status" -eq 0 ]`.
- **File assertions**: Use `bats-file` helpers (`assert_file_exists`, `assert_dir_exists`).
- **Temp dirs**: Use `mktemp -d "${BATS_TMPDIR}/dccd-test.XXXXXX"` — never hardcode `/tmp/` paths.
- **Isolation**: Every test is self-contained. `setup()` creates preconditions, `teardown()` cleans up. No inter-test state.
- **One-time setup**: Expensive operations go in `setup_file()` / `teardown_file()`, not per-test `setup()`.
- **Offline**: Unit and integration tests must not make network calls. Only E2E tests may use real Docker.
- **No skip-after-run**: Use `skip` at test start for precondition checks, never after `run`.

### Sourcing dccd.sh for Testing

`dccd.sh` uses a `DCCD_TESTING` guard. Source it in test helpers:

```bash
# helpers/common.bash
common_setup() {
    TEST_TMPDIR="$(mktemp -d "${BATS_TMPDIR}/dccd-test.XXXXXX")"
    MOCK_BIN="${TEST_TMPDIR}/bin"
    MOCK_LOG="${TEST_TMPDIR}/log"
    mkdir -p "${MOCK_BIN}" "${MOCK_LOG}"
    export PATH="${MOCK_BIN}:${PATH}"
    export DCCD_TESTING=1
    source "${BATS_TEST_DIRNAME}/../../../scripts/dccd.sh"
}
```

### PATH-Based Mocking

```bash
# helpers/mocks.bash
create_mock() {
    local cmd="$1" exit_code="${2:-0}" stdout="${3:-}"
    cat > "${MOCK_BIN}/${cmd}" <<MOCK
#!/bin/bash
echo "\$@" >> "${MOCK_LOG}/${cmd}.calls"
echo "${stdout}"
exit ${exit_code}
MOCK
    chmod +x "${MOCK_BIN}/${cmd}"
}
```

### Running Tests

```sh
# Run all tests
mise exec -- bats tests/

# Run a specific tier
mise exec -- bats tests/dccd/unit/
mise exec -- bats tests/dccd/integration/

# Run a single test file
mise exec -- bats tests/dccd/unit/parse_server_apps.bats

# Run with JUnit output for CI
mise exec -- bats --formatter tap --report-formatter junit tests/
```

## Running Checks — Linting and Validation

### Full Suite — Run All Checks

Run the complete pre-commit suite (fastest way to validate everything):

```sh
mise exec -- lefthook run pre-commit
```

This runs all checks in parallel. If it passes, the code is ready to commit.

### Targeted Checks — By File Type

Use these when you need to validate or fix a specific category of files.

#### Markdown

```sh
# Check formatting
mise exec -- dprint check

# Auto-fix formatting
mise exec -- dprint fmt <FILE>
```

#### YAML

```sh
# Check formatting (all YAML files)
find . \( -name '*.yaml' -o -name '*.yml' \) -not -path './site/*' -not -path './.git/*' -print0 | xargs -0 mise exec -- yamlfmt -lint

# Auto-fix formatting
mise exec -- yamlfmt <FILE>

# Lint for structural issues
mise exec -- yamllint <FILE>
```

#### Shell Scripts

```sh
# Lint
find . -name '*.sh' -print0 | xargs -0 mise exec -- shellcheck

# Check formatting
find . -name '*.sh' -print0 | xargs -0 mise exec -- shfmt --diff

# Auto-fix formatting
mise exec -- shfmt --write <FILE>
```

#### Docker Compose

```sh
# Validate a specific compose file
docker compose -f services/<app>/compose.yaml config --quiet

# Validate all compose files
for f in services/*/compose.yaml; do
    echo "Checking $f..."
    docker compose -f "$f" config --quiet
done
```

Warnings about unset env vars (e.g. `DOMAINNAME`) are expected — secrets are decrypted at deploy time. **Warnings are fine; errors are not.**

#### GitHub Actions Workflows

```sh
# Lint workflows
mise exec -- actionlint

# Security scan workflows
mise exec -- zizmor .github/workflows/*.yml
```

#### Environment Files

```sh
# Lint shared env files (x86_64 only — skipped on ARM)
mise exec -- dotenv-linter fix --no-backup services/shared/env/*.env
```

### Security and Secrets Scanning

#### Secret Detection

```sh
# Scan for leaked secrets (full repo)
mise exec -- gitleaks detect --redact

# Scan staged files only (pre-commit mode)
mise exec -- gitleaks protect --staged --redact
```

#### SOPS Encryption Check

Verify all `secret.sops.env` files are properly encrypted:

```sh
for f in services/*/secret.sops.env; do
    grep -q '^sops_mac=' "$f" || echo "ERROR: $f is not SOPS-encrypted"
done
```

#### Infrastructure Security Scan

```sh
# Checkov — IaC security
mise exec -- checkov --skip-download -d .

# Trivy — misconfig and secret scanning
mise exec -- trivy fs --scanners misconfig,secret .
```

### Schema and Cross-Reference Validation

#### servers.yaml Schema

```sh
mise exec -- check-jsonschema --schemafile servers.schema.json servers.yaml
```

#### servers.yaml App Directory Check

Verify every app listed in `servers.yaml` has a corresponding `services/` directory:

```sh
mise exec -- yq -r '.servers[].apps // [] | .[]' servers.yaml | sort -u | while IFS= read -r app; do
    [ -d "services/${app}" ] || echo "ERROR: App '${app}' in servers.yaml has no services/${app}/ directory"
done
```

#### MkDocs Build

```sh
mise exec -- mkdocs build --strict
```

This catches broken links, missing nav entries, and Markdown rendering issues.

## Interpreting Results

### Common False Positives

| Tool    | Warning                                  | Verdict |
| ------- | ---------------------------------------- | ------- |
| Compose | `WARN: DOMAINNAME is not set`            | Safe    |
| Compose | `WARN: variable is not set`              | Safe    |
| Checkov | Policy skip with `# checkov:skip=CKV_*:` | OK      |

### Severity Guide

| Result       | Action                                                   |
| ------------ | -------------------------------------------------------- |
| Format diff  | Auto-fix with the write variant of the tool              |
| Lint error   | Must fix — CI will block the PR                          |
| Security hit | Investigate — may need a code change or a justified skip |
| Secret leak  | **Critical** — remove immediately, rotate the secret     |

## Auto-Fix Workflow

When multiple formatting issues are found, fix them all at once:

```sh
# Fix Markdown
mise exec -- dprint fmt .

# Fix YAML
find . \( -name '*.yaml' -o -name '*.yml' \) -not -path './site/*' -not -path './.git/*' -print0 | xargs -0 mise exec -- yamlfmt

# Fix shell
find . -name '*.sh' -print0 | xargs -0 mise exec -- shfmt --write
```

Then re-run the full suite to confirm:

```sh
mise exec -- lefthook run pre-commit
```
