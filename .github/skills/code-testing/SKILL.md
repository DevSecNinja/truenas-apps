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

#### Container Runtime Smoke Testing

Static `compose config` validation catches interpolation and schema errors, but
it is **not a runtime test**. Use this procedure when a Compose or container
change needs execution-level evidence.

##### 1. Select a Usable Runtime

Check the daemon and Compose provider, in this order. CLI presence alone is not
enough:

```sh
RUNTIME=""

if mise exec -- docker info >/dev/null 2>&1 &&
    mise exec -- docker compose version >/dev/null 2>&1; then
    RUNTIME="docker"
elif mise exec -- podman info >/dev/null 2>&1 &&
    mise exec -- podman compose version >/dev/null 2>&1; then
    RUNTIME="podman"
fi

if [ -z "${RUNTIME}" ]; then
    printf '%s\n' "BLOCKED: no usable Docker or Podman engine with Compose support"
    printf '%s\n' "Static compose config validation is not a runtime test."
    exit 1
fi

runtime() {
    mise exec -- "${RUNTIME}" "$@"
}

compose() {
    mise exec -- "${RUNTIME}" compose "$@"
}

runtime info
compose version
```

If neither engine is usable, stop runtime testing and report it as blocked.
Suggest installing or starting Docker or Podman, but **never install software
without the user's approval**.

On Windows, recommend the official Podman package with a rootless WSL2 Podman
machine. With user approval, the user can install and initialize it explicitly:

```powershell
winget install --id RedHat.Podman --exact
podman machine init --now
podman machine list
podman info
podman compose version
```

`podman compose` delegates to an external Compose provider. If none is
available, install or select the repository-pinned provider and set
`PODMAN_COMPOSE_PROVIDER` explicitly before testing:

```powershell
$env:PODMAN_COMPOSE_PROVIDER = "<path-to-repository-pinned-provider>"
podman compose version
```

Verify the provider in the environment where Compose commands will run. A
successful `podman compose version` on Windows does not prove that the provider
is installed inside the Podman machine. Docker with a WSL2 backend is an
alternative; after the user installs and starts it, verify `docker info` and
`docker compose version`.

Confirm that the selected engine endpoint is the intended disposable test
environment before creating anything. Inspect `docker context show` for Docker
or `podman system connection list` for Podman, plus the existing containers in
the next section. If the endpoint is shared with production workloads, stop
unless the user explicitly approves testing there; prefer a clean disposable VM
or Podman machine.

On Windows, keep the disposable checkout on the Podman machine or native WSL
ext4 filesystem. A Windows-host path is suitable for transferring a tar
archive, but not for testing Linux ownership, modes, permission-sensitive bind
mounts, or init containers.

Podman provides strong Linux runtime coverage. Docker/TrueNAS CI or host
validation is still required for Docker-specific behavior and for TrueNAS ZFS,
ACL, and host-network behavior.

##### 2. Create an Isolated Test Deployment

Use a disposable copy of the exact source under test, a unique project name, and
synthetic non-production secrets. The following also includes tracked staged and
unstaged changes instead of silently testing only `HEAD`. It stops if untracked
files exist because they require explicit review before inclusion:

```sh
REPO_ROOT="$(git rev-parse --show-toplevel)"
COMMIT="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/truenas-apps-smoke.XXXXXX")"
PROJECT="smoke-$(printf '%.12s' "${COMMIT}")-$$"

if [ -n "$(git -C "${REPO_ROOT}" ls-files --others --exclude-standard)" ]; then
    printf '%s\n' "BLOCKED: review and include required untracked files before testing"
    git -C "${REPO_ROOT}" ls-files --others --exclude-standard
    exit 1
fi

git -C "${REPO_ROOT}" archive "${COMMIT}" | tar -x -C "${TEST_ROOT}"
git -C "${TEST_ROOT}" init --quiet
if ! git -C "${REPO_ROOT}" diff --quiet "${COMMIT}" --; then
    WORKTREE_ID="$(
        git -C "${REPO_ROOT}" diff --binary "${COMMIT}" -- |
            git hash-object --stdin
    )"
    if ! git -C "${REPO_ROOT}" diff --binary "${COMMIT}" -- |
        git -C "${TEST_ROOT}" apply --binary; then
        printf '%s\n' "ERROR: failed to apply tracked worktree changes to disposable source" >&2
        exit 1
    fi
    SOURCE="${COMMIT}+worktree-${WORKTREE_ID}"
else
    SOURCE="${COMMIT}"
fi
cd "${TEST_ROOT}"
```

If an untracked file is required, first inspect it for secrets and generated or
runtime data, then copy only that reviewed file into the disposable tree and
include its checksum in the reported source identity. Never bulk-copy ignored
paths from a service directory.

Before rendering or starting the stack:

1. Create only the `.env` files needed by the target stack, with synthetic
   credentials and non-production hostnames.
2. Never decrypt, copy, or reuse production secrets.
3. Review every rendered bind mount. Never mount a production dataset, socket,
   backup directory, or other host path.
4. Inspect existing containers and networks:

   ```sh
   runtime ps -a --format '{{.Names}}'
   runtime network ls
   ```

5. Stop and ask before touching any name or network conflict. A Compose project
   name does not isolate explicit `container_name:` or `name:` values used by
   this repository. Prefer a clean disposable VM or Podman machine when those
   names would collide.
6. Track any external network created for the test. Give it a test-specific
   label when the stack permits this, and never reuse a production network.

##### 3. Render and Pull the Exact Images

Set `COMPOSE_FILE` to the compose file in the disposable copy:

```sh
COMPOSE_FILE="services/${APP:?Set APP to the service directory}/compose.yaml"

compose -p "${PROJECT}" -f "${COMPOSE_FILE}" config
compose -p "${PROJECT}" -f "${COMPOSE_FILE}" config --images
compose -p "${PROJECT}" -f "${COMPOSE_FILE}" pull
```

Every rendered image must contain an `@sha256:` digest. Inspect the pulled
images and record their repository digests:

```sh
for image in $(compose -p "${PROJECT}" -f "${COMPOSE_FILE}" config --images); do
    runtime image inspect "${image}" --format '{{json .RepoDigests}}'
done
```

Do not substitute newer tags or locally rebuilt images. Runtime evidence must
cover the exact digest-pinned images in the source snapshot.

##### 4. Start and Exercise the Stack

Start a dependency or service subset first when that isolates the change, then
run the full stack. Use Compose's wait behavior so unhealthy services fail the
test:

```sh
compose -p "${PROJECT}" -f "${COMPOSE_FILE}" up -d --wait <service>
compose -p "${PROJECT}" -f "${COMPOSE_FILE}" ps
compose -p "${PROJECT}" -f "${COMPOSE_FILE}" up -d --wait
compose -p "${PROJECT}" -f "${COMPOSE_FILE}" ps
```

If the selected Podman Compose provider does not support `--wait`, use a
bounded status/health polling loop and report that substitution. Never report a
successful `up -d` alone as a passed health test.

Validate all applicable behavior:

- **Health and status:** every long-running service reaches its expected
  running/healthy state. Do not accept an image healthcheck that only prints a
  version when readiness depends on generated configuration or dependencies;
  add a relevant readiness probe.
- **One-shot lifecycle:** after `compose up --wait`, poll each one-shot container
  with a bounded timeout until it exits and require exit code `0`; `--wait` can
  return while a backup job is still briefly running. For backup jobs, count
  actual backup-start events and output files, and require the expected count. A
  supervisor/command combination can otherwise duplicate or loop a documented
  one-shot job.
- **Application probes:** exercise health and representative application
  endpoints from the intended client network. Confirm expected status, body,
  TLS, routing, and authentication behavior.
- **Reverse proxy:** when routing, labels, or middleware changed, run a
  disposable proxy using the same Traefik major/version. Assert allowed and
  denied routes, methods, headers, and authentication boundaries through the
  proxy; direct application probes do not validate Traefik configuration.
- **Database and cache:** use application-native or database-native probes over
  the Compose network. Verify authenticated connectivity without printing
  credentials.
- **Init idempotence:** run each init service at least twice against synthetic
  data. Confirm both runs succeed and inspect resulting ownership and modes in
  the Linux test filesystem.
- **Runtime identity and hardening:** verify the effective UID/GID and
  capabilities, `no-new-privileges`, read-only root filesystems, writable
  mounts/tmpfs, memory limits, and PID limits against the rendered Compose
  model. Attempt a write to an unmounted root path and require it to fail; also
  prove that each intended writable path succeeds.
- **Mount portability:** require the selected engine to create every mount.
  Rootless Podman rejects Docker-style `uid=`, `gid=`, and `mode=` options in
  short tmpfs syntax. Prefer a plain `/tmp` when mode `1777` is sufficient, or
  test the chosen long-syntax alternative on both Docker and Podman.
- **Network isolation:** confirm internal networks are internal and backend-only
  services have no published host ports. Probe both allowed and denied paths.
- **Backup and restore:** where applicable, create a backup containing
  synthetic data, restore it into a fresh disposable database, and verify
  representative records. File creation, checksums, and decryption alone are
  insufficient. Reject even a newer maintained major version when its restore
  test fails; prefer a maintained compatibility release with a proven restore
  path and document the reason.
- **Persistence:** create synthetic state, restart the service, then recreate
  it and confirm the state remains. Do not use production data as a fixture.

When feasible and explicitly approved by the user, expose a short-lived,
LAN-only synthetic endpoint for a physical mobile-client test. Use disposable
credentials, bind one specific high port, confirm firewall and network scope,
and ensure login or registration is not exposed accidentally. Inspect
application logs for successful paths and statuses, then immediately remove the
relay/proxy and credentials. Never use production secrets. Mobile logs can
refine an explicit route allowlist, but sanitize query strings because tracker
API keys may appear in URLs.

Use runtime inspection as supporting evidence. If a Podman field differs from
Docker's inspect schema, inspect the full JSON and identify the equivalent:

```sh
runtime inspect <container> --format 'user={{json .Config.User}} readonly={{json .HostConfig.ReadonlyRootfs}} cap_drop={{json .HostConfig.CapDrop}} cap_add={{json .HostConfig.CapAdd}} memory={{json .HostConfig.Memory}} pids={{json .HostConfig.PidsLimit}} ports={{json .NetworkSettings.Ports}}'
runtime top <container> -eo user,group,pid,args
runtime network inspect <network>
runtime port <backend-only-container>
```

Use an in-container `id` and `/proc/1/status` check when the image provides the
required tools; otherwise use runtime/host process inspection and record that
the image is shell-less. The final command must return no mappings for a
backend-only container. Compare intentionally published ports with the Compose
definition rather than assuming all services publish none.

Rootless Podman maps container identities to large subordinate host UID/GID
values. Inspect bind-mount ownership in Podman's user namespace; raw host values
are not failures when the mapped container identity is correct:

```sh
podman unshare stat <exact-disposable-path>
podman unshare find <exact-disposable-path> -maxdepth 2 -printf '%u:%g %m %p\n'
```

For init idempotence and persistence, use only named services in the disposable
project:

```sh
compose -p "${PROJECT}" -f "${COMPOSE_FILE}" up --no-deps --force-recreate <init-service>
compose -p "${PROJECT}" -f "${COMPOSE_FILE}" up --no-deps --force-recreate <init-service>
compose -p "${PROJECT}" -f "${COMPOSE_FILE}" restart <stateful-service>
compose -p "${PROJECT}" -f "${COMPOSE_FILE}" up -d --wait --force-recreate <stateful-service>
```

##### 5. Diagnose and Report

On failure, collect logs before cleanup:

```sh
compose -p "${PROJECT}" -f "${COMPOSE_FILE}" ps -a
compose -p "${PROJECT}" -f "${COMPOSE_FILE}" logs --no-color --timestamps
```

Preserve logs and the disposable project long enough to identify the failure.
Redact synthetic credentials if they appear; never include secret values in the
report.

Report concise evidence:

| Evidence  | Report                                                                            |
| --------- | --------------------------------------------------------------------------------- |
| Runtime   | Engine, engine version, and Compose provider/version                              |
| Source    | Commit/worktree identity tested and disposable environment used                   |
| Images    | Digest-pinned image references actually pulled                                    |
| Startup   | Selective/full startup result and health/status summary                           |
| Behavior  | Endpoint, database/cache, init, persistence, and backup/restore results           |
| Hardening | UID/GID, capabilities, read-only root, limits, ports, and network assertions      |
| Failure   | Failing command/probe and relevant redacted log excerpt                           |
| Cleanup   | Test resources removed or intentionally retained for diagnosis or by user request |

When no engine is usable, report **runtime testing blocked**, include the failed
engine/provider checks, and state which static checks passed. Explicitly say
that `compose config` did not provide runtime coverage.

##### 6. Clean Up Safely

Clean up only the project and resources created by this test. If the user or a
parent process asks to retain an active test environment, do not run cleanup;
report that it was intentionally retained:

```sh
compose -p "${PROJECT}" -f "${COMPOSE_FILE}" down --volumes --remove-orphans
```

Remove tracked temporary files/directories and test-created external networks
only after confirming their identity and test label. If a failure is still
being diagnosed, retain the logs before removal. Never use broad cleanup
commands such as `system prune`, `container prune`, or `network prune`, and
never remove an object merely because its name resembles the test project.
Rootless mapped files may require
`podman unshare rm -rf <exact-disposable-path>`; verify the path before removal.
Confirm that test containers, networks, listeners, temporary configuration,
synthetic secrets, and native test directories are gone. Keep the Podman
machine installed unless the user explicitly requests its removal.

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

## Completion Checklist

- [ ] Relevant unit, integration, and static validation checks passed.
- [ ] Engine availability was checked with both engine info and Compose version
      checks; CLI presence alone was not accepted.
- [ ] Runtime smoke testing covered the exact digest-pinned images when an
      engine was available.
- [ ] Health, probes, dependencies, init idempotence, hardening, isolation,
      and persistence checks were run where applicable.
- [ ] Every one-shot job exited with code `0`, and job-start/output counts proved
      that it did not duplicate or loop.
- [ ] Each applicable backup was restored into a fresh disposable database and
      representative records were verified.
- [ ] A real disposable proxy passed allowed and denied route, method, header,
      and authentication tests when routing changed.
- [ ] Physical-client evidence was recorded and sanitized when an approved
      mobile-client test was performed.
- [ ] Runtime evidence is concise, redacted, and tied to the tested commit.
- [ ] Only test-created resources were removed; failure logs were retained long
      enough to diagnose.
- [ ] If no engine was usable, the result explicitly says runtime testing was
      blocked and does not present static `compose config` as runtime coverage.
