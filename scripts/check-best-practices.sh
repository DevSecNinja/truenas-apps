#!/bin/bash
# Validates Docker Compose files against the project blueprint (docs/ARCHITECTURE.md).
#
# Required for every service:
#   - Image pinned to digest (@sha256:...)
#   - container_name
#   - security_opt: no-new-privileges=true
#   - pids_limit
#   - mem_limit
#   - restart policy
#
# Warnings (non-blocking):
#   - Missing healthcheck on non-init services

set -euo pipefail

ERRORS=0
WARNINGS=0

fail() {
  echo "FAIL: $1"
  ERRORS=$((ERRORS + 1))
}

warn() {
  echo "WARN: $1"
  WARNINGS=$((WARNINGS + 1))
}

for compose_file in src/*/compose.yaml; do
  mapfile -t services < <(yq '.services | keys | .[]' "$compose_file")

  for service in "${services[@]}"; do
    prefix="${compose_file} → ${service}"

    # 1. Image digest pinning
    image=$(yq ".services.\"${service}\".image // \"\"" "$compose_file")
    if [[ -n "$image" && "$image" != *"@sha256:"* ]]; then
      fail "${prefix}: image is not pinned to digest (@sha256:...)"
    fi

    # 2. container_name
    cname=$(yq ".services.\"${service}\".container_name // \"\"" "$compose_file")
    if [[ -z "$cname" ]]; then
      fail "${prefix}: missing container_name"
    fi

    # 3. no-new-privileges
    noprivs=$(yq ".services.\"${service}\".security_opt[] | select(. == \"no-new-privileges=true\")" "$compose_file" 2>/dev/null || true)
    if [[ -z "$noprivs" ]]; then
      fail "${prefix}: missing security_opt: no-new-privileges=true"
    fi

    # 4. pids_limit
    pidslimit=$(yq ".services.\"${service}\".pids_limit // \"\"" "$compose_file")
    if [[ -z "$pidslimit" ]]; then
      fail "${prefix}: missing pids_limit"
    fi

    # 5. mem_limit
    memlimit=$(yq ".services.\"${service}\".mem_limit // \"\"" "$compose_file")
    if [[ -z "$memlimit" ]]; then
      fail "${prefix}: missing mem_limit"
    fi

    # 6. restart policy
    restart=$(yq ".services.\"${service}\".restart // \"\"" "$compose_file")
    if [[ -z "$restart" ]]; then
      fail "${prefix}: missing restart policy"
    fi

    # 7. healthcheck (warning only, skip init containers with restart: "no")
    if [[ "$restart" != "no" && -n "$restart" ]]; then
      hc=$(yq ".services.\"${service}\".healthcheck // \"\"" "$compose_file")
      if [[ -z "$hc" ]]; then
        warn "${prefix}: no healthcheck (add one or document the exception with a comment)"
      fi
    fi
  done
done

echo ""
echo "Results: ${ERRORS} error(s), ${WARNINGS} warning(s)"

if [[ $ERRORS -gt 0 ]]; then
  exit 1
fi

echo "All best-practice checks passed!"
