#!/bin/sh
# Substitutes ${VAR} placeholders in unbound config templates with values
# from the container environment (sourced from secret.sops.env at deploy time).
# Called by the adguard-unbound-init service before unbound starts.
#
# Variables are discovered automatically — adding a new ${VAR} to a template
# only requires adding the corresponding value to secret.sops.env.
set -eu

for f in a-records.conf forward-records.conf; do
  cp "/templates/${f}" "/output/${f}"
  # shellcheck disable=SC2312  # grep/sort exit codes are intentionally unmasked; empty output is handled
  grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' "/templates/${f}" | sort -u | while read -r pattern; do
    name="${pattern#\$\{}"
    name="${name%\}}"
    val=$(printenv "${name}" 2>/dev/null) || continue
    sed -i "s|${pattern}|${val}|g" "/output/${f}"
  done
done
