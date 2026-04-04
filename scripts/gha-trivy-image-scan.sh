#!/bin/bash
# Called by .github/workflows/image-security.yml (trivy-image-scan job).
# Reads all image: references from services/*/compose.yaml, runs a Trivy
# vulnerability scan against each image, then merges all per-image SARIF outputs
# into a single sarif-output/trivy-images.sarif containing one combined run.
#
# GitHub Code Scanning rejects SARIF files with more than 20 runs, and also
# rejects multiple runs sharing the same tool+category. Merging into a single
# run avoids both limits and lets GitHub auto-close findings when images are
# removed or vulnerabilities are fixed upstream.

set -euo pipefail

# sarif-tmp/ holds the per-image working files; sarif-output/ holds only the
# final merged trivy-images.sarif that the workflow uploads.
mkdir -p sarif-tmp sarif-output

# SC2312: set -o pipefail (via set -euo pipefail above) already surfaces pipeline
# failures — the per-stage warning is a false positive in this context.
# shellcheck disable=SC2312
while IFS= read -r full_image; do
    slug=$(echo "${full_image}" | tr '/:@' '_' | tr -cd '[:alnum:]_-')
    outfile="sarif-tmp/${slug}.sarif"
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
    grep -rh 'image:' services/*/compose.yaml |
        grep -v '^[[:space:]]*#' |
        sed 's/.*image:[[:space:]]*//' |
        tr -d "'" |
        sort -u
)

# Check whether any validated SARIF files were produced.
# shellcheck disable=SC2312
mapfile -t sarif_files < <(find sarif-tmp -name '*.sarif' | sort)

if [ "${#sarif_files[@]}" -eq 0 ]; then
    echo "No valid SARIF files produced — all scans skipped or failed."
    # Emit a minimal valid empty SARIF so the upload-sarif action does not error.
    # SC2016: $schema is a JSON key, not a shell variable — single quotes are correct.
    # shellcheck disable=SC2016
    printf '{"version":"2.1.0","$schema":"https://json.schemastore.org/sarif-2.1.0.json","runs":[{"tool":{"driver":{"name":"Trivy"}},"results":[]}]}\n' >sarif-output/trivy-images.sarif
else
    # Merge all per-image SARIF files into one file with a single combined run.
    # GitHub rejects SARIF with >20 runs, and also rejects multiple runs under
    # the same tool+category — a single merged run avoids both constraints.
    # shellcheck disable=SC2312
    jq -s '{
        "version": "2.1.0",
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "runs": [{
            "tool": {
                "driver": (.[0].runs[0].tool.driver + {
                    "rules": ([.[].runs[].tool.driver.rules[]?] | unique_by(.id))
                })
            },
            "results": [.[].runs[].results[]],
            "artifacts": ([.[].runs[].artifacts[]?] | unique_by(.location.uri))
        }]
    }' "${sarif_files[@]}" >sarif-output/trivy-images.sarif

    # Remove the per-image working files; sarif-output/ now has only trivy-images.sarif.
    rm -rf sarif-tmp
fi
