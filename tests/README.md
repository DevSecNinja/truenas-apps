# Test Framework

This repository uses [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System)
to test the `scripts/dccd.sh` continuous deployment script. The suite contains **133 tests** across
three categories — unit, integration, and end-to-end.

## Directory Structure

```text
tests/
├── setup_libs.sh              # Downloads BATS helper libraries (version-pinned, Renovate-managed)
├── libs/                      # Downloaded BATS libraries (gitignored)
│   ├── bats-support/          # Output formatting and common assertions
│   ├── bats-assert/           # Value and status assertions
│   └── bats-file/             # File existence and content assertions
└── dccd/
    ├── helpers/
    │   ├── common.bash        # Shared setup/teardown, sources dccd.sh with DCCD_TESTING=1
    │   └── mocks.bash         # Mock generators for external commands
    ├── unit/                  # Fast, isolated function tests (73 tests)
    ├── integration/           # Multi-function workflow tests (56 tests)
    └── e2e/                   # Real Docker container tests (4 tests)
```

## Setup

BATS and [go-task](https://taskfile.dev) are managed by mise. Install all tools and libraries:

```sh
task install
```

Or install just the BATS helper libraries:

```sh
task install:bats-libs
```

This runs `tests/setup_libs.sh`, which downloads bats-support, bats-assert, and bats-file into
`tests/libs/` (gitignored). The helper versions are pinned in the script and updated automatically
by Renovate.

<!-- dprint-ignore -->
!!! note
    The `common.bash` helper auto-detects missing libraries and runs `setup_libs.sh`
    automatically, so tests will still work without a manual install step — but the first run
    will be slower.

## Running Tests

### With go-task (preferred)

| Command                               | What it runs                                        |
| ------------------------------------- | --------------------------------------------------- |
| `task test`                           | All tests (unit + integration; E2E skipped locally) |
| `task test:unit`                      | Unit tests only                                     |
| `task test:integration`               | Integration tests only                              |
| `task test:e2e`                       | E2E tests (sets `DCCD_E2E=1` automatically)         |
| `task test:file -- path/to/test.bats` | A single test file                                  |
| `task test:ci`                        | CI mode with JUnit XML output                       |

### With mise

```sh
mise exec -- bats tests/ --recursive
mise exec -- bats tests/dccd/unit/
mise exec -- bats tests/dccd/integration/
DCCD_E2E=1 mise exec -- bats tests/dccd/e2e/
```

### Direct bats command

If BATS is on your `PATH`:

```sh
bats tests/ --recursive
bats tests/dccd/unit/log_message.bats
```

## Test Categories

### Unit tests (`tests/dccd/unit/`)

Unit tests exercise individual functions from `dccd.sh` in complete isolation. Every external
command (docker, git, sops, curl, etc.) is mocked. These tests are fast and deterministic.

Each file tests a single function:

| File                             | Function under test           |
| -------------------------------- | ----------------------------- |
| `log_message.bats`               | `log_message()`               |
| `ensure_sops.bats`               | `ensure_sops()`               |
| `decrypt_sops_files.bats`        | `decrypt_sops_files()`        |
| `parse_server_apps.bats`         | `parse_server_apps()`         |
| `get_project_image_info.bats`    | `get_project_image_info()`    |
| `log_image_changes.bats`         | `log_image_changes()`         |
| `remove_compose_project.bats`    | `remove_compose_project()`    |
| `cleanup_orphaned_projects.bats` | `cleanup_orphaned_projects()` |
| `flush_output_buffer.bats`       | `flush_output_buffer()`       |
| `report_cd_status_to_gatus.bats` | `report_cd_status_to_gatus()` |

### Integration tests (`tests/dccd/integration/`)

Integration tests exercise multiple functions working together or test the script's control flow.
External commands are still mocked, but tests verify end-to-end behaviour of larger workflows
like option parsing, deploy orchestration, and cleanup.

| File                    | Workflow under test                |
| ----------------------- | ---------------------------------- |
| `option_parsing.bats`   | `getopts` argument parsing         |
| `deploy_standard.bats`  | Standard (non-TrueNAS) deploy flow |
| `deploy_truenas.bats`   | TrueNAS-mode deploy flow           |
| `deploy_server.bats`    | Multi-server deploy (`-S` flag)    |
| `decrypt_only.bats`     | Decrypt-only mode (`-D` flag)      |
| `remove_mode.bats`      | App removal (`-R` flag)            |
| `orphan_cleanup.bats`   | Orphaned project auto-cleanup      |
| `traefik_ordering.bats` | Traefik deploy-last ordering       |
| `quiet_mode.bats`       | Quiet/buffered output mode         |
| `root_guard.bats`       | Root-user rejection guard          |
| `edge_cases.bats`       | Edge cases and error handling      |

### E2E tests (`tests/dccd/e2e/`)

End-to-end tests use **real Docker containers** — no mocks. They create temporary compose stacks,
run actual `docker compose` commands, and verify container state.

| File                       | Scenario                              |
| -------------------------- | ------------------------------------- |
| `deploy_real.bats`         | Real deploy with health check waiting |
| `remove_real.bats`         | Real app teardown                     |
| `orphan_cleanup_real.bats` | Real orphan detection and cleanup     |

E2E tests are **skipped by default** in local development. To run them:

```sh
task test:e2e
```

Or manually:

```sh
DCCD_E2E=1 mise exec -- bats tests/dccd/e2e/
```

In CI, E2E tests run in a separate workflow job with Docker available.

## Writing New Tests

### Test file template

```bash
#!/usr/bin/env bats
# Unit tests for my_function()

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup
}

teardown() {
    common_teardown
}

@test "my_function: describes expected behaviour" {
    run my_function "arg1" "arg2"
    assert_success
    assert_output --partial "expected output"
}
```

### Conventions

- **One function per unit test file** — name the file after the function (`my_function.bats`).
- **Descriptive test names** — use the format `"function_name: describes what is being tested"`.
- **Always call `common_setup` in `setup()`** — this creates isolated temp directories, prepends
  the mock `bin/` to `PATH`, and sources `dccd.sh` with the testing guard.
- **Always call `common_teardown` in `teardown()`** — cleans up temp directories.
- **Load `mocks` for unit tests** — integration tests may also use mocks, but E2E tests should not.

### Helper reference

**`common.bash`** provides:

- `common_setup` — creates `MOCK_BIN`, `MOCK_LOG`, and `BASE_DIR` temp directories, sources
  `dccd.sh` with `DCCD_TESTING=1`, and resets all mutable globals.
- `common_teardown` — removes all temp directories.
- `REPO_ROOT`, `MOCK_BIN`, `MOCK_LOG`, `BASE_DIR` — directory variables available in every test.

**`mocks.bash`** provides:

| Function                                        | Purpose                                                  |
| ----------------------------------------------- | -------------------------------------------------------- |
| `create_mock <cmd> [exit_code] [stdout]`        | Create a stub that logs calls and returns fixed output   |
| `create_sequential_mock <cmd> <exit1:out1> ...` | Stub that returns different output on each call          |
| `create_default_mocks`                          | Creates stubs for docker, git, curl, dig, sops, sudo, yq |
| `assert_mock_called <cmd>`                      | Assert a mock was called at least once                   |
| `assert_mock_not_called <cmd>`                  | Assert a mock was never called                           |
| `assert_mock_called_with <cmd> <substring>`     | Assert a mock was called with specific arguments         |
| `get_mock_call_count <cmd>`                     | Return the number of times a mock was called             |
| `get_mock_call_args <cmd>`                      | Return all recorded call arguments                       |

### The source guard (`DCCD_TESTING=1`)

The `dccd.sh` script contains a source guard near the end of its function definitions:

```bash
if [[ "${DCCD_TESTING:-}" == "1" ]]; then
    return 0 2>/dev/null || true
fi
```

When `common_setup` sources `dccd.sh` with `DCCD_TESTING=1`, the script loads all function
definitions but exits before the main execution flow (option parsing, root guard, deploy logic).
This lets tests call individual functions in isolation.

### PATH-based mocking

Tests use a PATH-prepend strategy to intercept external commands:

1. `common_setup` creates a temporary `MOCK_BIN` directory and prepends it to `PATH`.
2. Mock scripts are created as executable files in `MOCK_BIN` (e.g., `${MOCK_BIN}/docker`).
3. When `dccd.sh` functions call `docker`, the shell finds the mock in `MOCK_BIN` first.
4. Each mock logs its arguments to `${MOCK_LOG}/<cmd>.calls` for later assertion.

This avoids modifying `dccd.sh` for testability — the same script runs in production and tests.

## CI Integration

Tests run automatically on pull requests and pushes to `main` when files in `scripts/` or `tests/`
change.

| Workflow            | File                             | What it runs             |
| ------------------- | -------------------------------- | ------------------------ |
| Tests               | `.github/workflows/test.yml`     | Caller workflow          |
| BATS (reusable)     | `.github/workflows/bats.yml`     | Unit + integration tests |
| BATS E2E (reusable) | `.github/workflows/bats-e2e.yml` | E2E tests with Docker    |

The test caller workflow (`.github/workflows/test.yml`) invokes both reusable workflows. Unit and
integration tests run in a standard runner. E2E tests run in a runner with Docker available.

Tests also run as a lefthook pre-commit hook (`mise exec -- bats tests/`), catching regressions
before they reach CI.
