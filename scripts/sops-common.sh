#!/usr/bin/env bash
# scripts/sops-common.sh — shared SOPS execution helpers.
#
# Sourced by generate-sops-secrets.sh and validate-sops-secrets.sh so both
# scripts invoke SOPS through byte-for-byte identical logic instead of two
# subtly different copy-pasted wrappers. This file only defines functions
# and variables — it does not set shell options and has no side effects
# beyond that when sourced. It is not meant to be executed directly.
#
# Source with:
#   _MY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=sops-common.sh disable=SC1091
#   . "${_MY_SCRIPT_DIR}/sops-common.sh"
#
# Provided functions:
#
#   sops_common_error <message>
#       Print "ERROR: <message>" to stderr. Shared error format for every
#       consumer script.
#
#   sops_key_setup_help
#       Print the standard SOPS_AGE_KEY_CMD / 1Password setup guidance to
#       stderr. Shared so every consumer gives identical guidance on a key
#       or decryption failure.
#
#   sops_bin_resolve
#       Validate an explicit SOPS_BIN override, if set. A path-like value
#       (contains a "/") must reference an existing, executable regular
#       file; a bare command name must resolve via `command -v`. A clear
#       error is printed for an invalid/unusable override. No-op (and
#       always succeeds) when SOPS_BIN is unset. The result is memoized for
#       the lifetime of the process (repeated calls are cheap).
#
#   run_sops <sops-arguments...>
#       Invoke SOPS with <sops-arguments...>. Uses "${SOPS_BIN}" directly
#       (the exact configured executable, with a safely quoted argv — no
#       shell re-interpretation of its arguments) when SOPS_BIN is set,
#       otherwise falls back to the existing `mise exec -- sops` invocation.
#       Either way: when SOPS_AGE_KEY_CMD is set, SOPS_AGE_KEY and
#       SOPS_AGE_KEY_FILE are unset for the invocation, so the two mutually
#       exclusive key sources can never leak into each other in the same
#       process. Requires `mise` only when SOPS_BIN is unset. Only the
#       underlying sops tool's own stderr is suppressed (2>/dev/null) —
#       preflight diagnostics (invalid SOPS_BIN, missing mise, missing op)
#       are always left visible, so callers must NOT wrap the whole call in
#       `2>/dev/null` themselves or those diagnostics would be lost too.
#
#   sops_is_encrypted_dotenv <file>
#       Structural check only (no decryption attempted): does <file> look
#       like a SOPS-encrypted dotenv file? Requires an encrypted
#       `sops_mac=ENC[AES256_GCM,...]` line, a `sops_version=` line, and at
#       least one `VARIABLE=ENC[AES256_GCM,...]` line.

# Source guard — sourcing this file twice in the same shell just redefines
# identical functions, which is harmless, but skipping the work is cheap and
# avoids resetting the SOPS_BIN memoization below mid-script.
if [[ -n "${_SOPS_COMMON_LOADED:-}" ]]; then
    return 0
fi
_SOPS_COMMON_LOADED=1

sops_common_error() {
    printf 'ERROR: %s\n' "${1}" >&2
}

sops_key_setup_help() {
    cat >&2 <<'EOF'
Recommended 1Password setup:
  export SOPS_AGE_KEY_CMD='op read "op://<vault>/<item>/<field>"'

Alternatively, use `op run --env-file <gitignored-file>` to inject
SOPS_AGE_KEY from an op:// reference. Never run op read directly or print its
output. SOPS_AGE_KEY_FILE and SOPS standard key-file locations remain optional
fallbacks.
EOF
}

_SOPS_BIN_RESOLVED=""

sops_bin_resolve() {
    if [[ -n "${_SOPS_BIN_RESOLVED}" ]]; then
        return 0
    fi

    if [[ -z "${SOPS_BIN:-}" ]]; then
        _SOPS_BIN_RESOLVED=1
        return 0
    fi

    if [[ "${SOPS_BIN}" == */* ]]; then
        if [[ ! -e "${SOPS_BIN}" ]]; then
            sops_common_error "SOPS_BIN does not exist: ${SOPS_BIN}"
            return 1
        fi
        if [[ ! -f "${SOPS_BIN}" ]]; then
            sops_common_error "SOPS_BIN is not a regular file: ${SOPS_BIN}"
            return 1
        fi
        if [[ ! -x "${SOPS_BIN}" ]]; then
            sops_common_error "SOPS_BIN is not executable: ${SOPS_BIN}"
            return 1
        fi
    elif ! command -v "${SOPS_BIN}" >/dev/null 2>&1; then
        sops_common_error "SOPS_BIN command not found on PATH: ${SOPS_BIN}"
        return 1
    fi

    _SOPS_BIN_RESOLVED=1
}

# Internal: fail fast with clear guidance when SOPS_AGE_KEY_CMD references
# the 1Password CLI but `op` is unavailable, instead of letting the
# underlying sops invocation fail with a less specific error.
_sops_check_key_cmd_preflight() {
    local trimmed_key_command

    trimmed_key_command="${SOPS_AGE_KEY_CMD#"${SOPS_AGE_KEY_CMD%%[![:space:]]*}"}"
    if [[ "${trimmed_key_command}" == "op" || "${trimmed_key_command}" == "op "* ]] &&
        ! command -v op >/dev/null 2>&1; then
        sops_common_error "SOPS_AGE_KEY_CMD uses 1Password, but the op CLI is unavailable"
        sops_key_setup_help
        return 1
    fi
}

run_sops() {
    # shellcheck disable=SC2310
    if ! sops_bin_resolve; then
        return 1
    fi

    if [[ -z "${SOPS_BIN:-}" ]] && ! command -v mise >/dev/null 2>&1; then
        sops_common_error "mise is required; install it and run 'mise install sops', or set SOPS_BIN to an explicit sops executable"
        return 1
    fi

    # Only the underlying sops tool's own stderr is suppressed here (its raw
    # diagnostics are replaced by each caller's own clearer error message on
    # failure). Preflight errors above (SOPS_BIN validation, missing mise,
    # missing op) are NOT suppressed — callers must not wrap this whole
    # function in `2>/dev/null`, or those diagnostics would be silently lost
    # along with the tool's own noise.
    if [[ -n "${SOPS_AGE_KEY_CMD:-}" ]]; then
        # shellcheck disable=SC2310
        if ! _sops_check_key_cmd_preflight; then
            return 1
        fi
        if [[ -n "${SOPS_BIN:-}" ]]; then
            env -u SOPS_AGE_KEY -u SOPS_AGE_KEY_FILE "${SOPS_BIN}" "$@" 2>/dev/null
        else
            env -u SOPS_AGE_KEY -u SOPS_AGE_KEY_FILE mise exec -- sops "$@" 2>/dev/null
        fi
    else
        if [[ -n "${SOPS_BIN:-}" ]]; then
            "${SOPS_BIN}" "$@" 2>/dev/null
        else
            mise exec -- sops "$@" 2>/dev/null
        fi
    fi
}

sops_is_encrypted_dotenv() {
    local file="${1}"

    [[ -f "${file}" ]] || return 1
    grep -q '^sops_mac=ENC\[AES256_GCM,' "${file}" || return 1
    grep -q '^sops_version=' "${file}" || return 1
    awk -F= '
        $1 !~ /^sops_/ && $1 ~ /^[A-Za-z_][A-Za-z0-9_]*$/ &&
            $2 ~ /^ENC\[AES256_GCM,/ { found = 1 }
        END { exit found ? 0 : 1 }
    ' "${file}"
}
