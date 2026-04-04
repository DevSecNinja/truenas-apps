#!/bin/sh
# Substitutes ${VAR} placeholders in unbound config templates with values
# from the container environment (sourced from secret.sops.env at deploy time).
# Called by the adguard-unbound-init service before unbound starts.
#
# Variables are discovered automatically — adding a new ${VAR} to a template
# only requires adding the corresponding value to secret.sops.env.
set -eu

mkdir -p /output/conf.d /output/zones.d

for f in conf.d/a-records.conf conf.d/server-overrides.conf zones.d/forward-zones.conf; do
    cp "/templates/${f}" "/output/${f}"
    # shellcheck disable=SC2312  # grep/sort exit codes are intentionally unmasked; empty output is handled
    grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' "/templates/${f}" | sort -u | while read -r pattern; do
        name="${pattern#\$\{}"
        name="${name%\}}"
        val=$(printenv "${name}" 2>/dev/null) || continue
        sed -i "s|${pattern}|${val}|g" "/output/${f}"
    done
done

# Verify no ${VAR} placeholders remain — catches missing secret.sops.env entries
# before unbound starts with a broken config. Fails the init container loudly.
failed=0
for f in conf.d/a-records.conf conf.d/server-overrides.conf zones.d/forward-zones.conf; do
    # shellcheck disable=SC2312
    unresolved=$(grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' "/output/${f}" 2>/dev/null | sort -u)
    if [ -n "${unresolved}" ]; then
        echo "ERROR: unresolved placeholders in ${f}:"
        echo "${unresolved}"
        failed=1
    fi
done
[ "${failed}" -eq 0 ] || exit 1
