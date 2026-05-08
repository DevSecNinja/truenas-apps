#!/bin/sh
# Init script for the openclaw stack. Runs as root in a busybox sidecar.
#
# 1. Chowns ./data so the non-root openclaw user (3127:3127) can write to it.
# 2. On first deploy only (cp -n equivalent), seeds ./data/openclaw.json from
#    the git-tracked ./config/openclaw.json template, substituting ${VAR}
#    placeholders with values from the container environment (e.g. DOMAINNAME
#    from secret.sops.env). On subsequent deploys the file is left alone so
#    OpenClaw's own writes (auto-updated meta.lastTouchedAt, Control UI
#    edits, etc.) are not clobbered.
#
# To re-seed after a config change in git, delete ./data/openclaw.json on the
# host and redeploy.
set -eu

chown -Rv 3127:3127 /data || true

if [ ! -f /data/openclaw.json ]; then
    echo "Seeding /data/openclaw.json from template..."
    cp -v /templates/openclaw.json /data/openclaw.json

    # Substitute ${VAR} placeholders with values from the container env.
    # shellcheck disable=SC2312  # grep exit code is intentionally unmasked
    grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' /data/openclaw.json | sort -u | while read -r pattern; do
        name="${pattern#\$\{}"
        name="${name%\}}"
        val=$(printenv "${name}" 2>/dev/null) || continue
        sed -i "s|${pattern}|${val}|g" /data/openclaw.json
    done

    # Verify no unresolved placeholders remain.
    # shellcheck disable=SC2312
    unresolved=$(grep -onE '\$\{[A-Z_][A-Z0-9_]*\}' /data/openclaw.json 2>/dev/null || true)
    if [ -n "${unresolved}" ]; then
        echo "ERROR: unresolved placeholders in /data/openclaw.json:"
        echo "${unresolved}"
        exit 1
    fi

    chown -v 3127:3127 /data/openclaw.json
    chmod 600 /data/openclaw.json
fi
