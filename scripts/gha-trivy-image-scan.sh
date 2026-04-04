#!/bin/bash
# Called by .github/workflows/image-security.yml (trivy-image-scan job).
# Reads all image: references from services/*/compose.yaml, runs a Trivy
# vulnerability scan against each image, and writes per-image SARIF files to
# sarif-output/. Each SARIF run is stamped with a unique runAutomationDetails.id
# so the github/codeql-action/upload-sarif action can upload the whole directory
# without triggering the "multiple runs with the same category" rejection.
#
# See: https://docs.github.com/en/code-security/reference/code-scanning/sarif-files/sarif-support-for-code-scanning#uploading-more-than-one-sarif-file-for-a-commit

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
        else
            # Stamp each run with a unique runAutomationDetails.id so that when
            # the upload-sarif action uploads the whole sarif-output/ directory,
            # every run has a distinct category — GitHub rejects uploads where
            # multiple runs share the same category.
            jq --arg id "trivy-images/${slug}/" \
                '.runs[0].automationDetails = {"id": $id}' \
                "${outfile}" >"${outfile}.tmp" && mv "${outfile}.tmp" "${outfile}"
        fi
    else
        echo "  WARN: trivy scan failed for ${full_image}, skipping"
        rm -f "${outfile}"
    fi
done < <(
    grep -rh 'image:' services/*/compose.yaml |
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
    # Emit a minimal valid empty SARIF so the upload-sarif action does not error.
    # SC2016: $schema is a JSON key, not a shell variable — single quotes are correct.
    # shellcheck disable=SC2016
    printf '{"version":"2.1.0","$schema":"https://json.schemastore.org/sarif-2.1.0.json","runs":[{"tool":{"driver":{"name":"Trivy"}},"results":[]}]}\n' >sarif-output/trivy-images.sarif
fi
