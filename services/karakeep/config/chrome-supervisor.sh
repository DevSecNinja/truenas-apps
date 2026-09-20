#!/bin/bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
    printf '%s\n' 'ERROR: Chrome supervisor requires a browser command' >&2
    exit 1
fi

proxy_pid=""
browser_pid=""

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
stop_children() {
    local pid
    for pid in "${proxy_pid}" "${browser_pid}"; do
        if [ -n "${pid}" ]; then
            # A child may already have exited. Docker's init reaps its descendants.
            kill -TERM "${pid}" 2>/dev/null || true
        fi
    done
}

trap 'stop_children' EXIT
trap 'exit 0' TERM INT

socat TCP4-LISTEN:9222,fork,reuseaddr TCP4:127.0.0.1:9223 &
proxy_pid=$!

"$@" &
browser_pid=$!

status=0
wait -n "${proxy_pid}" "${browser_pid}" || status=$?
printf 'ERROR: Chrome browser or DevTools proxy exited unexpectedly (status %s); stopping container\n' "${status}" >&2
# Even a clean child exit is unexpected; trigger the on-failure restart policy.
exit 1
