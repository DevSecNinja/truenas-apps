#!/usr/bin/env bash
set -euo pipefail

if (($# == 0)); then
    printf '%s\n' 'ERROR: provide at least one encrypted dotenv file' >&2
    exit 1
fi

for file in "$@"; do
    if ! grep -q '^sops_mac=' "${file}"; then
        printf 'ERROR: %s is not SOPS-encrypted\n' "${file}" >&2
        exit 1
    fi
done
