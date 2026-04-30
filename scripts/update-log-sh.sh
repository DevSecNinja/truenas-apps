#!/usr/bin/env bash
# Re-download the vendored copy of log.sh from the pinned upstream release.
#
# The two URLs below contain the literal version string (e.g. v0.1.2) so the
# shared Renovate `Update DevSecNinja/dotfiles log.sh release pin` custom
# manager bumps both lines together. After Renovate opens the PR, run this
# script to re-fetch the file and refresh log.sh.sha256, then commit the diff.
#
# Usage:
#     bash scripts/update-log-sh.sh

set -euo pipefail

LOG_SH_URL="https://github.com/DevSecNinja/dotfiles/releases/download/v0.1.2/log.sh"
LOG_SH_SHA_URL="https://github.com/DevSecNinja/dotfiles/releases/download/v0.1.2/log.sh.sha256"

DEST_DIR="$(cd "$(dirname "$0")" && pwd)/lib"
mkdir -p "${DEST_DIR}"

echo "Fetching ${LOG_SH_URL}"
curl -fsSL -o "${DEST_DIR}/log.sh" "${LOG_SH_URL}"
curl -fsSL -o "${DEST_DIR}/log.sh.sha256" "${LOG_SH_SHA_URL}"

echo "Verifying checksum..."
(cd "${DEST_DIR}" && sha256sum -c log.sh.sha256)

echo "log.sh installed at ${DEST_DIR}/log.sh"
