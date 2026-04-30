#!/bin/bash
# Post-create script for the devcontainer.
# Called by devcontainer.json postCreateCommand after the container is built.

set -euo pipefail

########################################
# Chezmoi — dotfiles manager
########################################
chezmoi_installer=$(curl -fsLS https://get.chezmoi.io) || true
sh -c "${chezmoi_installer}" -- init --apply DevSecNinja

########################################
# Mise — tool version manager
########################################
curl https://mise.run | sh
# shellcheck disable=SC2016 # Intentionally single-quoted to defer expansion to .bashrc
echo 'eval "$(~/.local/bin/mise activate bash)"' >>~/.bashrc
~/.local/bin/mise install

# Set global defaults for tools whose shims are invoked by VS Code extensions
# from a cwd outside the workspace (e.g. shellcheck/dprint/shfmt/sops -V at
# startup). Without a global default, the shim aborts with
# "No version is set for shim", which surfaces as an error toast in the editor.
# Versions are resolved from the workspace .mise.toml via `mise current` so
# they stay in sync with the workspace pins.
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for tool in shellcheck shfmt dprint sops; do
    version="$(cd "${WORKSPACE_DIR}" && ~/.local/bin/mise current "${tool}")"
    if [[ -n "${version}" ]]; then
        ~/.local/bin/mise use -g "${tool}@${version}"
    fi
done

########################################
# Shell aliases
########################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo ". ${SCRIPT_DIR}/scripts/aliases.sh" >>~/.bashrc

########################################
# Lefthook — git hooks
########################################
~/.local/bin/mise exec -- lefthook install
