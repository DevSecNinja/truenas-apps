# Devcontainer

Devcontainer is a personal remote development container for hosting the user's GitHub repositories directly on the NAS. It runs the user's own [dotfiles devcontainer image](https://github.com/DevSecNinja/dotfiles) so the full shell and tooling environment (chezmoi + mise + Homebrew) is available on the server.

## Why

Cloning and building repositories on the NAS keeps source code, toolchains, and build artefacts on fast local NVMe storage instead of a laptop. Using the personal dotfiles image means the remote environment is identical to the local one — same shell, same `mise`-managed languages, same Homebrew packages. The container is **highly locked down** to lower container-escape risk, so it is safe to leave running and attach to on demand.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/devcontainer/compose.yaml)

## Access

There is **no web UI, no Traefik route, and no DNS record** — no ports are published. Connect to the running container instead:

| Method                                                    | Description                                             |
| --------------------------------------------------------- | ------------------------------------------------------- |
| VS Code → **Dev Containers: Attach to Running Container** | Over a Docker context (SSH to the host + `docker exec`) |
| `docker exec -it devcontainer fish`                       | Interactive shell directly on the host                  |

GitHub authentication is done **inside** the container — interactive `gh auth login` or an SSH agent. Optionally set a `GITHUB_TOKEN` secret in `secret.sops.env` for non-interactive private-repo access.

## Architecture

- **Image**: [ghcr.io/devsecninja/dotfiles-devcontainer](https://github.com/DevSecNinja/dotfiles) (built from `mcr.microsoft.com/devcontainers/base:debian-12`)
- **User/Group**: `1000:1000` (image-internal `vscode` user — the dotfiles, `mise`, and Homebrew toolchains are baked under `/home/vscode` at that UID)
- **Networks**: `devcontainer` (project-local bridge, outbound internet only — not Traefik-facing)
- **No reverse proxy, no published ports, no Docker socket** — docker-in-docker is intentionally omitted to minimise the escape surface

### User/Group Exception

The `dotfiles-devcontainer` image runs as the image-internal `vscode` user (UID/GID 1000) so the baked-in dotfiles and toolchains resolve. UID/GID `3128` (`svc-app-devcontainer`) is reserved on the host **only as a GID reservation** to keep the allocation unambiguous — the container never runs as 3128. This mirrors the Outline pattern (which reserves 3120 but runs as node UID 1000).

### Services

| Container           | Role                                                                                          |
| ------------------- | --------------------------------------------------------------------------------------------- |
| `devcontainer-init` | One-shot init: chowns `./data` to `1000:1000` so cloned repos can be written to `/workspaces` |
| `devcontainer`      | Long-running dev environment (`sleep infinity`); attach to it to work                         |

### Storage

- Cloned repositories live at `/workspaces`, bind-mounted from `./data/workspaces` on the NVMe apps pool (`vm-pool`) — the server's SSD storage — so they are visible on the host for backup and inspection.
- The home directory `/home/vscode` is a named Docker volume (`devcontainer-home`), seeded from the image on first creation and persisted across restarts. A bind mount would mask the image-baked dotfiles and toolchains, so a named volume is used instead.

### Security Hardening

The headline feature of this service is its locked-down posture:

- `read_only: true` root filesystem
- `security_opt: no-new-privileges=true` — runtime `sudo`/`apt` is intentionally disabled; install tools via `mise`/Homebrew in userspace
- `cap_drop: ALL` with **no** `cap_add` on the main container
- `mem_limit` 4096m, `pids_limit` 512
- `tmpfs` for `/tmp`, `/var/tmp`, `/run`
- **No** Docker socket mounted (docker-in-docker intentionally omitted)
- **No** ports published

<!-- dprint-ignore -->
!!! warning "Runtime package installs are disabled"
    `no-new-privileges=true` blocks `sudo`/`apt` at runtime by design. Install additional tooling through `mise` or Homebrew in userspace, or rebuild the [dotfiles image](https://github.com/DevSecNinja/dotfiles) with the package baked in.

### Health Check

The image has no listening service, so the health check verifies the core tooling with `git --version`.

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

| Secret         | Description                                                                                       |
| -------------- | ------------------------------------------------------------------------------------------------- |
| `GITHUB_TOKEN` | Optional Personal Access Token for non-interactive GitHub auth; leave empty to auth interactively |

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/devcontainer` in TrueNAS
2. Create a `svc-app-devcontainer` group (GID 3128) and user (UID 3128) on the TrueNAS host — this is a **GID reservation only**; the container runs as the image-internal `vscode` UID 1000
3. (Optional) Set `GITHUB_TOKEN` in `secret.sops.env` for non-interactive private-repo access
4. Deploy — the `devcontainer-init` container chowns `./data` to `1000:1000`, then the main container starts and idles
5. Attach with VS Code (**Dev Containers: Attach to Running Container**) or `docker exec -it devcontainer fish`, then run `gh auth login` and clone repositories into `/workspaces`

## Upgrade Notes

Image updates are managed by Renovate. Cloned repositories under `/workspaces` and the `devcontainer-home` named volume persist across image bumps. Because runtime `sudo`/`apt` is disabled, add new system packages by rebuilding the [dotfiles image](https://github.com/DevSecNinja/dotfiles) rather than installing them inside a running container.
