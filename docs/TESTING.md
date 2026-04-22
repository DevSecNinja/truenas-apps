# Testing `scripts/dccd.sh`

The continuous-deployment script `scripts/dccd.sh` is covered by a layered
[BATS](https://github.com/bats-core/bats-core) test suite that runs both
locally and in GitHub Actions.

## Layers

| Tier          | Location                      | What it covers                                                   | Externals                         |
|---------------|-------------------------------|------------------------------------------------------------------|-----------------------------------|
| Unit          | `tests/dccd/unit/`            | Individual functions, mocked externals, fully offline            | PATH-based mocks                  |
| Integration   | `tests/dccd/integration/`     | Option parsing, root guard, quiet mode — invokes the real script | PATH-based mocks                  |
| E2E           | `tests/dccd/e2e/`             | Real `docker compose up/down` against minimal stacks             | Real Docker (skipped by default)  |

## Running tests locally

Tests work identically on a developer laptop and in CI — there is no hard
dependency on GitHub Actions variables. Use either the wrapper script or
the mise tasks:

```bash
# Unit + integration (default — fast, no Docker)
scripts/run-bats-tests.sh
# or:
mise run test

# Individual tiers
scripts/run-bats-tests.sh --unit
scripts/run-bats-tests.sh --integration
scripts/run-bats-tests.sh --e2e
mise run test:unit
mise run test:integration
mise run test:e2e

# Everything
scripts/run-bats-tests.sh --all
mise run test:all

# Run a single file or pass extra args to bats
scripts/run-bats-tests.sh -- tests/dccd/unit/log_message.bats
scripts/run-bats-tests.sh -- --filter "parse_server_apps" tests/dccd/unit/
```

The runner auto-downloads `bats-support`, `bats-assert`, and `bats-file`
into `tests/libs/` on first use (gitignored). Re-bootstrap at any time with
`mise run test:bootstrap` or `tests/bootstrap.sh --force`.

### E2E opt-in

E2E tests are **skipped by default when run outside CI**. They bring up a
real `busybox` container via `docker compose` and pull images. To run them:

```bash
# Opt in explicitly
RUN_E2E=1 scripts/run-bats-tests.sh --e2e
# or use the task (which sets RUN_E2E=1 automatically):
mise run test:e2e
```

## Writing tests

Every test file sources the shared helpers, which handle the source guard,
mock PATH, state reset, and default stubs:

```bash
#!/usr/bin/env bats

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup()      { common_setup; }
teardown()   { common_teardown; }

@test "my_function: does the thing" {
    # Stub an external command: args are logged to ${MOCK_LOG}/<cmd>.calls.
    create_mock docker 0 "some output"

    run my_function
    assert_success
    assert_output --partial "expected"

    run mock_last_call docker
    assert_output --partial "ps -aq"
}
```

Key conventions:

- `BASE_DIR`, `SOPS_INSTALL_DIR`, and friends are pre-set to per-test temp
  dirs. `SUDO=""` so mocks run directly without re-exec.
- `run` captures exit status into `$status` and stdout into `$output`.
- `assert_success` / `assert_failure` / `assert_output --partial "…"` give
  clear diagnostic output on failure via `bats-assert`.
- Never rely on ordering between tests — `common_setup` resets all mutable
  globals (`_DEPLOY_*`, `SERVER_APPS`, `QUIET`, `_QUIET_BUF`, …).
- Use `create_mock` (fixed exit/stdout), `create_mock_script` (arbitrary
  shell body), or `create_mock_passthrough` (run the real binary but log
  the call).

## CI

The reusable workflows `.github/workflows/bats.yml` (unit + integration)
and `.github/workflows/bats-e2e.yml` (Docker-backed E2E) are invoked by
`.github/workflows/tests.yml`. Both publish JUnit XML as a GitHub check
and upload the report as a workflow artefact. They follow the
`DevSecNinja/.github` reusable-workflow conventions so they can be
extracted later without changes.

## Prod-script source guard

`scripts/dccd.sh` supports being sourced by tests via `DCCD_TESTING=1`:

```bash
DCCD_TESTING=1 source scripts/dccd.sh
# function definitions are now available, but no option parsing or
# deployment logic has run; the root guard is also skipped.
```

This is the only testability-related change to the production script.
