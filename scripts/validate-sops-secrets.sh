#!/usr/bin/env bash
# scripts/validate-sops-secrets.sh — non-printing SOPS secret validator.
#
# Verifies, without ever writing plaintext to disk or printing any decrypted
# value:
#
#   1. The target is a SOPS-encrypted dotenv file (same structural check
#      used by generate-sops-secrets.sh, via scripts/sops-common.sh).
#   2. It decrypts successfully with the current SOPS_BIN/mise + key-source
#      configuration.
#   3. Every required VARIABLE argument is present in the decrypted output.
#   4. No decrypted value in the file is exactly the literal sentinel
#      GENERATE or CHANGE_ME (i.e. no unresolved placeholder secrets
#      remain).
#
# Decrypted output is *streamed* directly from `sops decrypt` into an awk
# parser via a pipeline — it is never assigned to a bash variable, never
# written to a file, and never printed. awk sees each decrypted line only
# transiently while it evaluates it, and only ever emits safe variable
# *names* (never values), prefixed so the caller can distinguish "missing"
# from "unresolved". Only those names and error text are ever printed.
#
# This script intentionally does not rotate, generate, or modify anything;
# see generate-sops-secrets.sh for that.
#
# Usage (CLI) — the stable, documented interface:
#   bash scripts/validate-sops-secrets.sh <secret.sops.env> VARIABLE [VARIABLE ...]
#
# Example:
#   bash scripts/validate-sops-secrets.sh services/memos/secret.sops.env \
#       DOMAINNAME DB_ENC_PASSPHRASE
#
# Usage (sourced) — for reuse from other scripts or test helpers:
#   _DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=validate-sops-secrets.sh disable=SC1091
#   . "${_DIR}/validate-sops-secrets.sh"
#   validate_sops_secrets services/memos/secret.sops.env DOMAINNAME DB_ENC_PASSPHRASE
#
# Sourcing this file only defines the validate_sops_secrets function (and
# loads scripts/sops-common.sh) — it does not execute anything. The CLI
# entry point below only runs when this file is executed directly.
#
# SOPS_BIN and SOPS_AGE_KEY_CMD behave exactly as in generate-sops-secrets.sh
# (both are implemented by the shared scripts/sops-common.sh run_sops()).
#
# Exit codes:
#   0 — target is encrypted, decrypts, all required variables are present,
#       and none are left as an unresolved GENERATE/CHANGE_ME sentinel
#   1 — a validation check failed (see stderr for which one)
#   2 — usage error (missing arguments or an invalid VARIABLE name)

set +x +v

_VALIDATE_SOPS_SECRETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sops-common.sh disable=SC1091
. "${_VALIDATE_SOPS_SECRETS_DIR}/sops-common.sh"

_validate_sops_secrets_usage() {
    cat <<'EOF'
Usage: validate-sops-secrets.sh <secret.sops.env> VARIABLE [VARIABLE ...]

Streams the decrypted contents of <secret.sops.env> directly into an awk
parser (never assigned to a shell variable, never written to disk) and
verifies:
  - it is a SOPS-encrypted dotenv file
  - decryption succeeds with the current SOPS_BIN/mise + key-source setup
  - every VARIABLE argument is present in the decrypted output
  - no decrypted value in the file is exactly the literal sentinel
    GENERATE or CHANGE_ME

Only variable names and error messages are ever printed; decrypted values
are never shown, logged, or written to a file.
EOF
}

# validate_sops_secrets <secret.sops.env> VARIABLE [VARIABLE ...]
#
# Non-printing validation function — see the file header for the full
# contract. Safe to call repeatedly and from any sourcing script.
validate_sops_secrets() {
    local target="${1:-}"
    local variable
    local required_arg
    local combined
    local pipeline_line
    local decrypt_status=""
    local awk_status=""
    local missing_list=""
    local unresolved_list=""
    declare -a required=()
    declare -a missing=()
    declare -a unresolved=()

    if (($# < 2)); then
        _validate_sops_secrets_usage >&2
        return 2
    fi
    shift
    required=("$@")

    for variable in "${required[@]}"; do
        if [[ ! "${variable}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            sops_common_error "invalid variable name argument: ${variable}"
            return 2
        fi
    done

    if [[ ! -f "${target}" ]]; then
        sops_common_error "target does not exist: ${target}"
        return 1
    fi

    # shellcheck disable=SC2310
    if ! sops_is_encrypted_dotenv "${target}"; then
        sops_common_error "target is not a SOPS-encrypted dotenv file: ${target}"
        return 1
    fi

    required_arg="${required[*]}"

    # Stream sops's decrypted dotenv output directly into awk — the
    # plaintext is never assigned to a bash variable or written to a file
    # at any point; awk only ever emits safe variable *names* (never
    # values), prefixed MISSING:/UNRESOLVED:, plus a trailing
    # __EXIT__:<decrypt-status>:<awk-status> marker line.
    #
    # PIPESTATUS is only valid for a pipeline that ran directly in the
    # *current* shell, not one nested inside a command substitution from
    # the outside — so both exit statuses are captured and re-emitted from
    # inside this same command substitution (immediately after the
    # pipeline, in the same subshell it ran in) rather than read back from
    # the outer shell, where PIPESTATUS would no longer reflect it.
    combined="$(
        # shellcheck disable=SC2312
        run_sops decrypt \
            --input-type dotenv \
            --output-type dotenv \
            "${target}" |
            awk -v required="${required_arg}" '
                BEGIN {
                    n = split(required, req_arr, " ")
                    for (i = 1; i <= n; i++) seen[req_arr[i]] = 0
                }
                /^#/ { next }
                /^$/ { next }
                {
                    eq = index($0, "=")
                    if (eq == 0) next
                    key = substr($0, 1, eq - 1)
                    value = substr($0, eq + 1)
                    if (key in seen) seen[key] = 1
                    if (value == "GENERATE" || value == "CHANGE_ME") print "UNRESOLVED:" key
                }
                END {
                    for (i = 1; i <= n; i++) if (seen[req_arr[i]] == 0) print "MISSING:" req_arr[i]
                }
            '
        printf '__EXIT__:%s:%s\n' "${PIPESTATUS[0]}" "${PIPESTATUS[1]}"
    )"

    while IFS= read -r pipeline_line || [[ -n "${pipeline_line}" ]]; do
        case "${pipeline_line}" in
        __EXIT__:*)
            decrypt_status="${pipeline_line#__EXIT__:}"
            decrypt_status="${decrypt_status%%:*}"
            awk_status="${pipeline_line##*:}"
            ;;
        MISSING:*)
            missing+=("${pipeline_line#MISSING:}")
            ;;
        UNRESOLVED:*)
            unresolved+=("${pipeline_line#UNRESOLVED:}")
            ;;
        *) ;;
        esac
    done <<<"${combined}"
    unset combined pipeline_line

    if [[ "${decrypt_status}" != "0" ]]; then
        sops_common_error "SOPS could not decrypt ${target}"
        sops_key_setup_help
        return 1
    fi

    if [[ "${awk_status}" != "0" ]]; then
        sops_common_error "failed to parse decrypted output from ${target}"
        return 1
    fi

    if ((${#missing[@]} > 0)); then
        missing_list="${missing[*]}"
        sops_common_error "missing required variable(s) in ${target}: ${missing_list}"
        return 1
    fi

    if ((${#unresolved[@]} > 0)); then
        unresolved_list="${unresolved[*]}"
        sops_common_error "unresolved sentinel value(s) (GENERATE/CHANGE_ME) in ${target}: ${unresolved_list}"
        return 1
    fi

    printf 'OK: %s - all required variable(s) present and resolved: %s\n' "${target}" "${required[*]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_sops_secrets "$@"
fi
