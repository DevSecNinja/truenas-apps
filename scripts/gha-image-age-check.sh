#!/bin/bash
# Called by .github/workflows/stale-images.yml (image-age-check job).
# Reads all image: references from services/*/compose.yaml, determines when each
# tag was last pushed to its registry, opens a GitHub issue for each image
# that has not been updated in more than THRESHOLD_DAYS days, then exits 1
# if any stale images were found.
#
# Timestamp sources (in priority order):
#   docker.io  — Docker Hub REST API `tag_last_pushed` (registry-side, always
#                updated on push regardless of OCI `created` field)
#   all others — OCI config `created` via crane (GHCR, LSCR, etc. set this
#                accurately on every release)
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
    # Strip @sha256:... to get the name:tag for display (keep the version)
    bare="${full_image%%@*}"
    echo "Checking ${bare}..."

    # Determine the "last pushed" timestamp for this image.
    #
    # The OCI config `created` field is a compile-time value baked into the
    # image layers by the build system.  Some maintainers (notably official
    # Docker Library images such as busybox) do NOT update it when rebuilding
    # and re-pushing an existing tag for a security patch, so the field can
    # report an age of years even for an actively maintained image.
    #
    # Strategy:
    #   docker.io  — Docker Hub REST API exposes `tag_last_pushed`, a
    #                registry-side timestamp that is always updated on push.
    #   all others — GHCR, LSCR, etc. set OCI `created` accurately on every
    #                release, so the crane config fallback remains reliable.
    last_pushed=""
    source_label="created"
    case "${bare}" in
    docker.io/*)
        remainder="${bare#docker.io/}"
        ns_repo="${remainder%%:*}"
        tag_part="${remainder#*:}"
        dh_url="https://hub.docker.com/v2/repositories/${ns_repo}/tags/${tag_part}"
        if dh_out=$(curl -fsSL --max-time 10 "${dh_url}" 2>/dev/null); then
            last_pushed=$(echo "${dh_out}" | jq -r '.tag_last_pushed // empty')
            source_label="last_pushed"
        fi
        ;;
    *) ;;
    esac

    if [ -z "${last_pushed}" ]; then
        if ! crane_out=$(crane config "${bare}" 2>/dev/null); then
            echo "  WARN: crane could not fetch config for ${bare}, skipping"
            continue
        fi
        last_pushed=$(echo "${crane_out}" | jq -r '.created // empty')
    fi

    if [ -z "${last_pushed}" ]; then
        echo "  WARN: could not determine push date for ${bare}, skipping"
        continue
    fi

    # Skip zero-time / reproducible-build placeholder timestamps
    case "${last_pushed}" in
    "0001-01-01"* | "1970-01-01"*)
        echo "  SKIP: ${bare} has a zero-time placeholder timestamp (reproducible build image)"
        continue
        ;;
    *) ;;
    esac

    pushed_ts=$(date -d "${last_pushed}" +%s)
    age_days=$((($(date +%s) - pushed_ts) / 86400))

    if [ "${pushed_ts}" -lt "${THRESHOLD}" ]; then
        echo "  STALE: ${bare} (${source_label}: ${last_pushed}, ${age_days} days ago)"
        STALE+=("${full_image}")
    else
        echo "  OK:    ${bare} (${source_label}: ${last_pushed}, ${age_days} days ago)"
    fi
done < <(
    grep -rh 'image:' services/*/compose.yaml |
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
    # Strip digest for the issue title so it stays readable
    title_image="${image%%@*}"
    title="[${title_image}] Stale image detected"
    existing=$(gh issue list \
        --label stale-dependency \
        --state open \
        --json title \
        --jq '.[].title' |
        grep -F "${title}" || true)

    if [ -z "${existing}" ]; then
        # Find compose files that reference this image by name:tag
        # SC2312: pipefail is active; grep returning no matches exits 1 which
        # we handle explicitly with || true.
        # shellcheck disable=SC2312
        sources=$(grep -rl "${title_image}" services/*/compose.yaml 2>/dev/null |
            sort | tr '\n' '\n' | sed 's|^|  - |' || true)
        [ -z "${sources}" ] && sources="  - (not found via grep)"
        gh issue create \
            --title "${title}" \
            --label stale-dependency \
            --body "The pinned digest for \`${image}\` was built over ${THRESHOLD_DAYS} days ago.

**Found in:**
${sources}

Please update the image digest to a more recent version to reduce exposure to known security vulnerabilities. If Renovate is not auto-updating this image, check whether the registry exposes reliable timestamp metadata."
        echo "Created issue: ${title}"
    else
        echo "Issue already exists, skipping: ${title}"
    fi
done
