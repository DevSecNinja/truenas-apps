#!/bin/sh
set -eu

mkdir -p /data/config /data/lib
cp /templates/config.yaml /data/config/config.yaml

# shellcheck disable=SC2312  # grep/sort pipeline exit codes are intentionally unmasked here
grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' /templates/config.yaml | sort -u | while read -r pattern; do
    name="${pattern#\$\{}"
    name="${name%\}}"
    val=$(printenv "${name}" 2>/dev/null) || continue
    sed -i "s|${pattern}|${val}|g" /data/config/config.yaml
done

if grep -qE '\$\{[A-Z_][A-Z0-9_]*\}' /data/config/config.yaml; then
    echo "ERROR: unresolved placeholders remain in /data/config/config.yaml" >&2
    exit 1
fi
