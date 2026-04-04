#!/bin/sh
# Substitutes ${VAR} placeholders in the config.yaml template with values
# from the container environment (sourced from secret.sops.env at deploy time).
# Called by the traefik-forward-auth-init service before the main container starts.
#
# Variables are discovered automatically — adding a new ${VAR} to a template
# only requires adding the corresponding value to secret.sops.env.
set -eu

cp "/templates/config.yaml" "/output/config.yaml"
# shellcheck disable=SC2312  # grep/sort exit codes are intentionally unmasked; empty output is handled
grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' "/templates/config.yaml" | sort -u | while read -r pattern; do
    name="${pattern#\$\{}"
    name="${name%\}}"
    val=$(printenv "${name}" 2>/dev/null) || continue
    sed -i "s|${pattern}|${val}|g" "/output/config.yaml"
done

# Verify no ${VAR} placeholders remain — catches missing secret.sops.env entries
# before traefik-forward-auth starts with a broken config. Fails the init container loudly.
# shellcheck disable=SC2312
unresolved=$(grep -onE '\$\{[A-Z_][A-Z0-9_]*\}' "/output/config.yaml" 2>/dev/null)
if [ -n "${unresolved}" ]; then
    echo "ERROR: unresolved placeholders in config.yaml:"
    echo "${unresolved}"
    exit 1
fi
