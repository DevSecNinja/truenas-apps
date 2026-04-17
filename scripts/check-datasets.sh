#!/usr/bin/env bash
# Check which service folders lack a dedicated ZFS dataset.
# Run on the TrueNAS server: bash scripts/check-datasets.sh /mnt/tank/apps/services
#
# The script compares top-level directories under the given path
# against ZFS datasets and reports any that are plain directories
# (i.e. created without a dataset underneath).

set -euo pipefail

SERVICES_PATH="${1:?Usage: $0 /mnt/<pool>/apps/services}"

# Resolve to absolute path
SERVICES_PATH="$(cd "${SERVICES_PATH}" && pwd)"

echo "Checking service directories under: ${SERVICES_PATH}"
echo ""

missing=0
for dir in "${SERVICES_PATH}"/*/; do
    [ -d "${dir}" ] || continue
    dir_name="$(basename "${dir}")"

    # Check if any ZFS dataset has its mountpoint exactly at this directory
    if ! zfs list -H -o mountpoint 2>/dev/null | grep -qx "${dir%/}"; then
        echo "NO DATASET: ${dir_name}  (${dir%/})"
        missing=$((missing + 1))
    fi
done

echo ""
if [ "${missing}" -eq 0 ]; then
    echo "All service directories have a dedicated ZFS dataset."
else
    echo "${missing} service director(y/ies) without a dedicated dataset."
fi
