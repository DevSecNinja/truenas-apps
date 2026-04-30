#!/usr/bin/env bash
# Generates symlinks in docs/services/ pointing to each service's README.md.
# This allows MkDocs to serve per-service documentation natively while keeping
# the source files next to their compose.yaml for GitHub browsing.
#
# Run from the repository root:
#   bash scripts/generate-docs-symlinks.sh
#
# When to re-run:
#   - After adding a new service with a README.md
#   - After retiring a service (its symlink will be cleaned up automatically)
#
# The generated symlinks are committed to Git. Git stores symlinks as text files
# containing the relative target path, so they work across clones.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${0}")/.." && pwd)"
# shellcheck source=lib/log.sh disable=SC1091
. "${REPO_ROOT}/scripts/lib/log.sh"
# shellcheck disable=SC2034
LOG_TAG="generate-docs-symlinks"

DOCS_SERVICES="${REPO_ROOT}/docs/services"
SERVICES_DIR="${REPO_ROOT}/services"

mkdir -p "${DOCS_SERVICES}"

# Remove stale symlinks (service was retired or README removed)
find "${DOCS_SERVICES}" -maxdepth 1 -type l | while read -r link; do
    if [[ ! -e "${link}" ]]; then
        log_state "Removing stale symlink: ${link}"
        rm "${link}"
    fi
done

# Create symlinks for every service that has a README.md
created=0
for readme in "${SERVICES_DIR}"/*/README.md; do
    [[ -f "${readme}" ]] || continue

    service_name="$(basename "$(dirname "${readme}")")"

    # Skip special directories
    if [[ "${service_name}" == "shared" || "${service_name}" == "_bootstrap" ]]; then
        continue
    fi

    symlink="${DOCS_SERVICES}/${service_name}.md"
    # Relative path from docs/services/ to services/<app>/README.md
    target="../../services/${service_name}/README.md"

    if [[ -L "${symlink}" ]]; then
        # Symlink exists — verify it points to the correct target
        current_target="$(readlink "${symlink}")"
        if [[ "${current_target}" == "${target}" ]]; then
            continue
        fi
        rm "${symlink}"
    fi

    ln -s "${target}" "${symlink}"
    log_state "Created symlink: docs/services/${service_name}.md → ${target}"
    ((created++)) || true
done

log_result "${created} symlink(s) created."
