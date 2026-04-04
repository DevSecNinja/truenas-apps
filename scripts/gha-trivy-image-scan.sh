#!/bin/bash
# Called by .github/workflows/stale-images.yml (trivy-image-scan job).
# Reads all image: references from src/*/compose.yaml, runs a Trivy
# vulnerability scan against each image, and merges the per-image SARIF
# outputs into a single trivy-images.sarif file.
#
# A single SARIF upload with a fixed category lets GitHub auto-close findings
# when images are removed from compose files or vulnerabilities are fixed upstream.

set -euo pipefail

mkdir -p sarif-output

# SC2312: set -o pipefail (via set -euo pipefail above) already surfaces pipeline
# failures — the per-stage warning is a false positive in this context.
# shellcheck disable=SC2312
while IFS= read -r full_image; do
    slug=$(echo "${full_image}" | tr '/:@' '_' | tr -cd '[:alnum:]_-')
    echo "Scanning ${full_image}..."
    mise exec -- trivy image \
        --scanners vuln \
        --ignore-unfixed \
        --severity CRITICAL \
        --format sarif \
        --output "sarif-output/${slug}.sarif" \
        "${full_image}" || echo "  WARN: trivy scan failed for ${full_image}, skipping"
done < <(
    grep -rh 'image:' src/*/compose.yaml |
        grep -v '^[[:space:]]*#' |
        sed 's/.*image:[[:space:]]*//' |
        tr -d "'" |
        sort -u
)

jq -s '{
  version: .[0].version,
  "$schema": .[0]["$schema"],
  runs: [.[].runs[]]
}' sarif-output/*.sarif >trivy-images.sarif
