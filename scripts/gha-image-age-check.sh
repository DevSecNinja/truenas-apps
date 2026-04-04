#!/bin/bash
# Called by .github/workflows/stale-images.yml (image-age-check job).
# Reads all image: references from src/*/compose.yaml, checks the OCI creation
# timestamp via crane, opens a GitHub issue for each image that is older than
# THRESHOLD_DAYS, then exits 1 if any stale images were found.
#
# Required environment variables:
#   GH_TOKEN        GitHub token with issues: write permission
#   THRESHOLD_DAYS  Number of days before an image is considered stale

set -euo pipefail

THRESHOLD=$(date -d "${THRESHOLD_DAYS} days ago" +%s)
STALE=()

# SC2312: set -o pipefail (via set -euo pipefail above) already surfaces pipeline
# failures — the per-stage warning is a false positive in this context.
# shellcheck disable=SC2312
while IFS= read -r full_image; do
    bare="${full_image%%:*}"
    echo "Checking ${bare}..."
    created=$(crane config "${full_image}" 2>/dev/null | jq -r '.created // empty')

    if [ -z "${created}" ]; then
        echo "  WARN: could not get creation date for ${full_image}, skipping"
        continue
    fi

    # Skip zero-time / reproducible-build placeholder timestamps
    case "${created}" in
    "0001-01-01"* | "1970-01-01"*)
        echo "  SKIP: ${bare} has a zero-time placeholder timestamp (reproducible build image)"
        continue
        ;;
    *) ;;
    esac

    created_ts=$(date -d "${created}" +%s)
    age_days=$((($(date +%s) - created_ts) / 86400))

    if [ "${created_ts}" -lt "${THRESHOLD}" ]; then
        echo "  STALE: ${bare} (created: ${created}, ${age_days} days ago)"
        STALE+=("${bare}")
    else
        echo "  OK:    ${bare} (created: ${created}, ${age_days} days ago)"
    fi
done < <(
    grep -rh 'image:' src/*/compose.yaml |
        grep -v '^[[:space:]]*#' |
        sed 's/.*image:[[:space:]]*//' |
        tr -d "'" |
        sort -u
)

if [ "${#STALE[@]}" -eq 0 ]; then
    echo "All images are within the ${THRESHOLD_DAYS}-day threshold."
    exit 0
fi

printf '\nStale images detected: %d\n' "${#STALE[@]}"
for image in "${STALE[@]}"; do
    echo "  - ${image}"
done
echo ""

for image in "${STALE[@]}"; do
    title="[${image}] Stale image detected"
    existing=$(gh issue list \
        --label stale-dependency \
        --state open \
        --json title \
        --jq '.[].title' |
        grep -F "${title}" || true)

    if [ -z "${existing}" ]; then
        gh issue create \
            --title "${title}" \
            --label stale-dependency \
            --body "The image \`${image}\` appears to be over ${THRESHOLD_DAYS} days old based on its OCI creation timestamp. Please update to a more recent version to reduce exposure to known security vulnerabilities."
        echo "Created issue: ${title}"
    else
        echo "Issue already exists, skipping: ${title}"
    fi
done

exit 1
