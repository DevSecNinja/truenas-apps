# Contributing

## Prerequisites

- [Mise](https://mise.jdx.dev/) for tool management
- [Docker](https://docs.docker.com/get-docker/) with the Compose plugin
- [VS Code](https://code.visualstudio.com/) (recommended)

## Setup

1. Clone the repo
2. Install tools:

   ```sh
   mise install
   ```

   This installs all linters and utilities defined in `.mise.toml`.

## Running Checks Locally

All CI checks can be run locally with the same commands used in GitHub Actions.

### YAML Lint

```sh
yamllint .
```

### ShellCheck

```sh
shopt -s globstar
shellcheck **/*.sh
```

### Markdown Lint

```sh
markdownlint-cli2 "**/*.md"
```

### Docker Compose Validation

Each compose file requires a decrypted `.env` to validate. If you have the Age key, decrypt first with SOPS; otherwise create a placeholder `.env` in each app directory:

```sh
for dir in src/*/; do
  if [ -f "${dir}compose.yaml" ]; then
    (cd "$dir" && docker compose config --quiet)
  fi
done
```

### Traefik Schema Validation

```sh
check-jsonschema \
  --schemafile "https://json.schemastore.org/traefik-v3.json" \
  src/traefik/config/traefik.yml
```

### Best Practices

```sh
bash scripts/check-best-practices.sh
```

## CI Checks

All checks run automatically on pull requests and pushes to `main` via GitHub Actions. See [`.github/workflows/ci.yml`](.github/workflows/ci.yml) for the full configuration.

| Check | What it does |
|-------|-------------|
| **YAML Lint** | Validates syntax and consistency of all YAML files |
| **ShellCheck** | Static analysis of all shell scripts |
| **Markdown Lint** | Enforces consistent Markdown style |
| **Docker Compose Validation** | Runs `docker compose config --quiet` on every compose file |
| **Traefik Schema Validation** | Validates Traefik static config against the official schema |
| **Best Practices** | Checks compose files against the project blueprint |

## Adding a New App

1. Create the dataset `vm-pool/Apps/src/<app-name>` on TrueNAS
2. Add `src/<app-name>/compose.yaml` following [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
3. Ensure all CI checks pass before merging

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for compose standards, networking patterns, secret management, and directory conventions.
