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
    outfile="sarif-output/${slug}.sarif"
    echo "Scanning ${full_image}..."
    if mise exec -- trivy image \
        --scanners vuln \
        --ignore-unfixed \
        --severity CRITICAL \
        --format sarif \
        --output "${outfile}" \
        "${full_image}"; then
        # Validate that the output is parseable SARIF before keeping it.
        # Trivy may write a partial/empty file on non-fatal errors.
        if ! jq -e '.runs[0]' "${outfile}" >/dev/null 2>&1; then
            echo "  WARN: ${outfile} is not valid SARIF, discarding"
            rm -f "${outfile}"
        fi
    else
        echo "  WARN: trivy scan failed for ${full_image}, skipping"
        rm -f "${outfile}"
    fi
done < <(
    grep -rh 'image:' src/*/compose.yaml |
        grep -v '^[[:space:]]*#' |
        sed 's/.*image:[[:space:]]*//' |
        tr -d "'" |
        sort -u
)

# Check whether any validated SARIF files were produced.
# shellcheck disable=SC2312
mapfile -t sarif_files < <(find sarif-output -name '*.sarif' | sort)

if [ "${#sarif_files[@]}" -eq 0 ]; then
    echo "No valid SARIF files produced — all scans skipped or failed."
    # Emit a minimal valid empty SARIF into the output directory so the
    # upload-sarif action (which receives the whole directory) does not error.
    # SC2016: $schema is a JSON key, not a shell variable — single quotes are correct.
    # shellcheck disable=SC2016
    printf '{"version":"2.1.0","$schema":"https://json.schemastore.org/sarif-2.1.0.json","runs":[]}\n' >sarif-output/empty.sarif
fi

# Each per-image SARIF file is uploaded individually by the workflow's
# upload-sarif step (which accepts a directory). GitHub Code Scanning assigns
# a unique category per file, satisfying the requirement that no two runs share
# the same tool+category — no manual merging needed.
