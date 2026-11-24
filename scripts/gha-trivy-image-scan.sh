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
#
# That auto-close also closes the alerts of an image whose scan failed, so any
# failed scan fails the script without writing the merged SARIF: the workflow
# then skips the upload and the existing alerts stay open. dhi.io images need
# a login (DOCKERHUB_USERNAME / DOCKERHUB_TOKEN, as for dccd.sh). Without
# those credentials they're reported as unscanned and skipped, not failed.
# Their results go to sarif-output/trivy-images-dhi.sarif (category
# trivy-images-dhi), so a run without credentials doesn't close their alerts.
#
# The merged run has no per-image field, so each result's message ends with an
# "Image: <reference>" line. The message isn't part of an alert's identity, so
# adding it doesn't reopen or duplicate alerts.

set -euo pipefail

_TRIVY_SCAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh disable=SC1091
. "${_TRIVY_SCAN_DIR}/lib/log.sh"
# shellcheck disable=SC2034
LOG_TAG="trivy-image-scan"

# sarif-tmp/ holds the per-image working files; sarif-output/ holds only the
# final merged trivy-images.sarif that the workflow uploads.
mkdir -p sarif-tmp sarif-output

# Large images (e.g. unifi) can exceed Trivy's default 5m analysis timeout, and
# a timeout now fails the whole scan.
export TRIVY_TIMEOUT="${TRIVY_TIMEOUT:-15m}"

have_dhi_credentials=false
if [ -n "${DOCKERHUB_USERNAME:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ]; then
    have_dhi_credentials=true
    if ! printf '%s' "${DOCKERHUB_TOKEN}" |
        docker login dhi.io --username "${DOCKERHUB_USERNAME}" --password-stdin >/dev/null; then
        echo "::error::docker login dhi.io failed; dhi.io images will fail to scan"
    fi
fi

failed=()
unscanned=()

# SC2312: set -o pipefail (via set -euo pipefail above) already surfaces pipeline
# failures — the per-stage warning is a false positive in this context.
# shellcheck disable=SC2312
while IFS= read -r full_image; do
    if [[ "${full_image}" == dhi.io/* && "${have_dhi_credentials}" == false ]]; then
        unscanned+=("${full_image}")
        continue
    fi
    slug=$(echo "${full_image}" | tr '/:@' '_' | tr -cd '[:alnum:]_-')
    outfile="sarif-tmp/${slug}.sarif"
    log_state "Scanning ${full_image}"
    if mise exec -- trivy image \
        --scanners vuln \
        --ignore-unfixed \
        --severity CRITICAL \
        --ignorefile .trivyignore.yaml \
        --format sarif \
        --output "${outfile}" \
        "${full_image}"; then
        # Validate that the output is parseable SARIF before keeping it, and
        # name the image in every result. Trivy may write a partial or empty
        # file on non-fatal errors.
        if jq -e --arg image "${full_image}" '
            if (.runs[0] | type) == "object"
            then .runs[].results[]?.message.text += "\nImage: " + $image
            else error("no SARIF run")
            end' "${outfile}" >"${outfile}.tmp" 2>/dev/null; then
            mv "${outfile}.tmp" "${outfile}"
        else
            echo "::error::${outfile} is not valid SARIF for ${full_image}"
            rm -f "${outfile}" "${outfile}.tmp"
            failed+=("${full_image}")
        fi
    else
        echo "::error::trivy scan failed for ${full_image}"
        rm -f "${outfile}"
        failed+=("${full_image}")
    fi
done < <(
    grep -rh 'image:' services/*/compose.yaml |
        grep -v '^[[:space:]]*#' |
        sed 's/.*image:[[:space:]]*//' |
        tr -d "'" |
        sort -u
)

if [ "${#unscanned[@]}" -gt 0 ]; then
    echo "::warning::Not scanned, no dhi.io credentials (set DOCKERHUB_USERNAME and DOCKERHUB_TOKEN): ${unscanned[*]}"
fi

if [ "${#failed[@]}" -gt 0 ]; then
    echo "::error::${#failed[@]} image scan(s) failed; not writing the merged SARIF, so no alert closes on a partial scan: ${failed[*]}"
    exit 1
fi

merge_sarif() {
    local output="$1"
    shift
    # Merge per-image SARIF files into one file with a single combined run.
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
    }' "$@" >"${output}"
    log_result "Merged $# SARIF file(s) into ${output}"
}

# dhi.io images (slug prefix dhiio_) get their own file and category,
# trivy-images-dhi, written only when they were scanned. Without dhi.io
# credentials that category gets no upload, so its alerts stay open instead
# of closing as fixed.
# shellcheck disable=SC2312
mapfile -t sarif_files < <(find sarif-tmp -name '*.sarif' ! -name 'dhiio_*' | sort)
# shellcheck disable=SC2312
mapfile -t dhi_files < <(find sarif-tmp -name 'dhiio_*.sarif' | sort)

if [ "${#sarif_files[@]}" -eq 0 ]; then
    log_warn "No valid SARIF files produced — all scans skipped or failed"
    # Emit a minimal valid empty SARIF so the upload-sarif action does not error.
    # SC2016: $schema is a JSON key, not a shell variable — single quotes are correct.
    # shellcheck disable=SC2016
    printf '{"version":"2.1.0","$schema":"https://json.schemastore.org/sarif-2.1.0.json","runs":[{"tool":{"driver":{"name":"Trivy"}},"results":[]}]}\n' >sarif-output/trivy-images.sarif
else
    merge_sarif sarif-output/trivy-images.sarif "${sarif_files[@]}"
fi
if [ "${#dhi_files[@]}" -gt 0 ]; then
    merge_sarif sarif-output/trivy-images-dhi.sarif "${dhi_files[@]}"
fi

# Remove the per-image working files; sarif-output/ now has only the merged files.
rm -rf sarif-tmp
