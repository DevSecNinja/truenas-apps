#!/bin/sh
# Substitutes dollar-brace VAR placeholders in the immich.yaml template with values
# from the container environment (sourced from secret.sops.env at deploy time).
# Called by the immich-config-init service before immich-server starts.
#
# Variables are discovered automatically — adding a new placeholder to a template
# only requires adding the corresponding value to secret.sops.env.
set -eu

cp "/templates/immich.yaml" "/output/immich.yaml"
# shellcheck disable=SC2312  # grep/sort exit codes are intentionally unmasked; empty output is handled
grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' "/templates/immich.yaml" | sort -u | while read -r pattern; do
    name="${pattern#\$\{}"
    name="${name%\}}"
    val=$(printenv "${name}" 2>/dev/null) || continue
    sed -i "s|${pattern}|${val}|g" "/output/immich.yaml"
done

# Verify no unresolved placeholders remain — catches missing secret.sops.env entries
# before immich-server starts with a broken config. Fails the init container loudly.
# shellcheck disable=SC2312
unresolved=$(grep -onE '\$\{[A-Z_][A-Z0-9_]*\}' "/output/immich.yaml" 2>/dev/null || true)
if [ -n "${unresolved}" ]; then
    echo "ERROR: unresolved placeholders in immich.yaml:"
    echo "${unresolved}"
    exit 1
fi
