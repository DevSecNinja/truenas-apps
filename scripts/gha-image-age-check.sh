#!/bin/bash
# Called by .github/workflows/image-security.yml (image-age-check job).
# Reads all image: references from services/*/compose.yaml, determines when each
# tag was last pushed to its registry, opens a GitHub issue for each image
# that has not been updated in more than THRESHOLD_DAYS days, and closes any
# previously-opened stale-dependency issues whose image has since been updated.
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

_IMG_AGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh disable=SC1091
. "${_IMG_AGE_DIR}/lib/log.sh"
# shellcheck disable=SC2034
LOG_TAG="image-age-check"

STALE=()

# get_age_days IMAGE
#
# Prints the age in whole days of IMAGE (name:tag, no digest suffix).
# Prints "skip" instead if the image carries a placeholder/zero timestamp
# (reproducible-build images that do not track real push dates).
# Returns 1 if the age cannot be determined (registry unreachable, etc.).
#
# Timestamp strategy:
#   docker.io  — Docker Hub REST API `tag_last_pushed` (always updated on push)
#   all others — OCI config `created` via crane
get_age_days() {
    local bare="${1}"
    local last_pushed=""
    local pushed_ts
    local now

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
    case "${bare}" in
    docker.io/*)
        local remainder
        local ns_repo
        local tag_part
        local dh_url
        local dh_out
        remainder="${bare#docker.io/}"
        ns_repo="${remainder%%:*}"
        tag_part="${remainder#*:}"
        dh_url="https://hub.docker.com/v2/repositories/${ns_repo}/tags/${tag_part}"
        if dh_out=$(curl -fsSL --max-time 10 "${dh_url}" 2>/dev/null); then
            last_pushed=$(echo "${dh_out}" | jq -r '.tag_last_pushed // empty')
        fi
        ;;
    *) ;;
    esac

    if [ -z "${last_pushed}" ]; then
        local crane_out
        if ! crane_out=$(crane config "${bare}" 2>/dev/null); then
            echo ""
            return 0
        fi
        last_pushed=$(echo "${crane_out}" | jq -r '.created // empty')
    fi

    if [ -z "${last_pushed}" ]; then
        echo ""
        return 0
    fi

    # Skip zero-time / reproducible-build placeholder timestamps.
    case "${last_pushed}" in
    "0001-01-01"* | "1970-01-01"*)
        echo "skip"
        return 0
        ;;
    *) ;;
    esac

    pushed_ts=$(date -d "${last_pushed}" +%s)
    now=$(date +%s)
    echo $(((now - pushed_ts) / 86400))
}

# --- Scan all images in compose files and build the STALE list ---------------

# SC2312: set -o pipefail (via set -euo pipefail above) already surfaces pipeline
# failures — the per-stage warning is a false positive in this context.
# shellcheck disable=SC2312
while IFS= read -r full_image; do
    # Strip @sha256:... to get the name:tag for display (keep the version)
    bare="${full_image%%@*}"
    log_state "Checking ${bare}"

    age_days=$(get_age_days "${bare}")
    if [ -z "${age_days}" ]; then
        log_warn "Could not determine push date for ${bare}, skipping"
        continue
    fi

    if [ "${age_days}" = "skip" ]; then
        log_info "${bare} has a zero-time placeholder timestamp (reproducible build image) — skipping"
        continue
    fi

    if [ "${age_days}" -gt "${THRESHOLD_DAYS}" ]; then
        log_warn "STALE: ${bare} (${age_days} days old)"
        STALE+=("${full_image}")
    else
        log_info "OK: ${bare} (${age_days} days old)"
    fi
done < <(
    grep -rh 'image:' services/*/compose.yaml |
        grep -v '^[[:space:]]*#' |
        sed 's/.*image:[[:space:]]*//' |
        tr -d "'" |
        sort -u
)

# --- Open new issues for freshly discovered stale images ---------------------

if [ "${#STALE[@]}" -eq 0 ]; then
    log_result "All images are within the ${THRESHOLD_DAYS}-day threshold"
else
    printf '%s\n' "${STALE[@]}" |
        log_data WARN "Stale images detected: ${#STALE[@]}"

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
            log_result "Created issue: ${title}"
        else
            log_info "Still stale, issue already open: ${title}"
        fi
    done
fi

# --- Close resolved stale-dependency issues ----------------------------------
# Re-check each open stale-dependency issue against the current image in the
# compose files. If the image is now fresh (or has been removed entirely),
# close the issue automatically.

log_rule STATE "Checking open stale-dependency issues for resolution"

# shellcheck disable=SC2312
while IFS= read -r issue_json; do
    issue_number=$(printf '%s' "${issue_json}" | jq -r '.number')
    issue_title=$(printf '%s' "${issue_json}" | jq -r '.title')

    # Only process issues matching the expected "[image:tag] Stale image detected" format.
    case "${issue_title}" in
    *"] Stale image detected") ;;
    *)
        log_info "Issue #${issue_number} does not match expected title format — skipping"
        continue
        ;;
    esac

    # Extract the image name:tag from between the surrounding brackets.
    title_image="${issue_title#[}"
    title_image="${title_image%%]*}"

    # Find the current full image reference (with digest) in compose files.
    # shellcheck disable=SC2312
    current_full=$(grep -rh 'image:' services/*/compose.yaml |
        grep -v '^[[:space:]]*#' |
        sed 's/.*image:[[:space:]]*//' |
        tr -d "'" |
        grep -F "${title_image}@" | head -1 || true)

    if [ -z "${current_full}" ]; then
        log_result "${title_image}: no longer in any compose file — closing issue #${issue_number}"
        gh issue close "${issue_number}" \
            --comment "This image is no longer referenced in any compose file. Closing automatically."
        continue
    fi

    current_bare="${current_full%%@*}"
    age_days=$(get_age_days "${current_bare}")
    if [ -z "${age_days}" ]; then
        log_warn "Could not re-check age for ${current_bare}, skipping issue #${issue_number}"
        continue
    fi

    if [ "${age_days}" = "skip" ]; then
        log_info "${current_bare} has a placeholder timestamp — skipping issue #${issue_number}"
        continue
    fi

    if [ "${age_days}" -le "${THRESHOLD_DAYS}" ]; then
        log_result "${current_bare} is now ${age_days} days old — closing issue #${issue_number}"
        gh issue close "${issue_number}" \
            --comment "The image \`${current_bare}\` is no longer stale (${age_days} days old, threshold: ${THRESHOLD_DAYS} days). Closing automatically."
    else
        log_info "STILL STALE: ${current_bare} (${age_days} days old) — issue #${issue_number} remains open"
    fi
done < <(
    gh issue list \
        --label stale-dependency \
        --state open \
        --json number,title |
        jq -c '.[]'
)
