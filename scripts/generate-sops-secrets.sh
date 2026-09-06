#!/usr/bin/env bash
# Fill encrypted GENERATE sentinels with random hexadecimal values.

set +x +v
set -eo pipefail

MIN_SECRET_BYTES=16
MAX_SECRET_BYTES=1024
TEMP_TARGET=""

error() {
    printf 'ERROR: %s\n' "${1}" >&2
}

cleanup() {
    local status=$?

    if [[ -n "${TEMP_TARGET}" ]]; then
        rm -f -- "${TEMP_TARGET}"
    fi
    return "${status}"
}

key_setup_help() {
    cat >&2 <<'EOF'
Recommended 1Password setup:
  export SOPS_AGE_KEY_CMD='op read "op://<vault>/<item>/<field>"'

Alternatively, use `op run --env-file <gitignored-file>` to inject
SOPS_AGE_KEY from an op:// reference. Never run op read directly or print its
output. SOPS_AGE_KEY_FILE and SOPS standard key-file locations remain optional
fallbacks.
EOF
}

usage() {
    cat <<EOF
Usage: $0 <secret.sops.env> VARIABLE=BYTE_COUNT [VARIABLE=BYTE_COUNT ...]

Only variables whose decrypted value is exactly GENERATE are changed. Byte
counts must be between ${MIN_SECRET_BYTES} and ${MAX_SECRET_BYTES}. Existing
values are preserved; rotate them manually with 'sops edit'.
EOF
}

run_sops() {
    if [[ -n "${SOPS_AGE_KEY_CMD:-}" ]]; then
        env -u SOPS_AGE_KEY -u SOPS_AGE_KEY_FILE mise exec -- sops "$@"
    else
        mise exec -- sops "$@"
    fi
}

generate_random_hex() {
    local byte_count="${1}"
    local value
    local expected_length=$((byte_count * 2))

    if ! value="$(od -An -N "${byte_count}" -tx1 /dev/urandom | tr -d '[:space:]')"; then
        return 1
    fi
    if [[ ! "${value}" =~ ^[0-9a-f]+$ || ${#value} -ne ${expected_length} ]]; then
        return 1
    fi

    REPLY="${value}"
}

main() {
    local target="${1:-}"
    local spec
    local variable
    local byte_count
    local current_value
    local generated_value
    local json_path
    local seen="|"
    local trimmed_key_command
    local index
    declare -a variables=()
    declare -a byte_counts=()
    declare -a pending_indexes=()

    if (($# < 2)); then
        usage >&2
        return 2
    fi
    shift

    if [[ ! -f "${target}" || -L "${target}" || ! -r "${target}" || ! -w "${target}" ]]; then
        error "target must be an existing readable and writable regular file: ${target}"
        return 1
    fi

    if ! grep -q '^sops_mac=ENC\[AES256_GCM,' "${target}" ||
        ! grep -q '^sops_version=' "${target}" ||
        ! grep -Eq '^[A-Za-z_][A-Za-z0-9_]*=ENC\[AES256_GCM,' "${target}"; then
        error "target is not a SOPS-encrypted dotenv file: ${target}"
        return 1
    fi

    for spec in "$@"; do
        if [[ ! "${spec}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=([1-9][0-9]*)$ ]]; then
            error "invalid specification '${spec}'; expected VARIABLE=BYTE_COUNT"
            return 2
        fi

        variable="${BASH_REMATCH[1]}"
        byte_count=$((10#${BASH_REMATCH[2]}))
        if ((byte_count < MIN_SECRET_BYTES || byte_count > MAX_SECRET_BYTES)); then
            error "${variable}: byte count must be between ${MIN_SECRET_BYTES} and ${MAX_SECRET_BYTES}"
            return 2
        fi
        if [[ "${seen}" == *"|${variable}|"* ]]; then
            error "duplicate variable: ${variable}"
            return 2
        fi

        seen+="${variable}|"
        variables+=("${variable}")
        byte_counts+=("${byte_count}")
    done

    if ! command -v mise >/dev/null 2>&1; then
        error "mise is required; install it and run 'mise install sops'"
        return 1
    fi

    if [[ -n "${SOPS_AGE_KEY_CMD:-}" ]]; then
        trimmed_key_command="${SOPS_AGE_KEY_CMD#"${SOPS_AGE_KEY_CMD%%[![:space:]]*}"}"
        if [[ "${trimmed_key_command}" == "op" || "${trimmed_key_command}" == "op "* ]] &&
            ! command -v op >/dev/null 2>&1; then
            error "SOPS_AGE_KEY_CMD uses 1Password, but the op CLI is unavailable"
            key_setup_help
            return 1
        fi
    fi

    for index in "${!variables[@]}"; do
        variable="${variables[${index}]}"
        json_path="[\"${variable}\"]"
        # shellcheck disable=SC2310
        if ! current_value="$(
            run_sops decrypt \
                --input-type dotenv \
                --output-type dotenv \
                --extract "${json_path}" \
                "${target}" 2>/dev/null
        )"; then
            error "SOPS could not decrypt ${target} or find ${variable}"
            key_setup_help
            return 1
        fi

        if [[ "${current_value}" == "GENERATE" ]]; then
            pending_indexes+=("${index}")
        fi
        unset current_value
    done

    if ((${#pending_indexes[@]} == 0)); then
        printf 'No random secrets need generation in %s\n' "${target}"
        return 0
    fi

    umask 077
    TEMP_TARGET="$(mktemp "${target}.generated.XXXXXX")"
    trap cleanup EXIT
    if ! cp -p -- "${target}" "${TEMP_TARGET}"; then
        error "failed to create encrypted working copy for ${target}"
        return 1
    fi

    for index in "${pending_indexes[@]}"; do
        variable="${variables[${index}]}"
        byte_count="${byte_counts[${index}]}"
        json_path="[\"${variable}\"]"

        # shellcheck disable=SC2310
        if ! generate_random_hex "${byte_count}"; then
            error "failed to generate ${byte_count} random bytes for ${variable}"
            return 1
        fi
        generated_value="${REPLY}"

        # shellcheck disable=SC2310
        if ! printf '"%s"\n' "${generated_value}" |
            run_sops set \
                --input-type dotenv \
                --output-type dotenv \
                --value-stdin \
                "${TEMP_TARGET}" \
                "${json_path}" >/dev/null 2>&1; then
            unset generated_value REPLY
            error "SOPS failed to set ${variable}; verify that ${target} remains decryptable before retrying"
            return 1
        fi
        unset generated_value REPLY
    done

    # shellcheck disable=SC2310
    if ! run_sops decrypt \
        --input-type dotenv \
        --output-type dotenv \
        "${TEMP_TARGET}" >/dev/null 2>&1; then
        error "SOPS produced an unusable encrypted file; ${target} was not changed"
        return 1
    fi
    if ! mv -f -- "${TEMP_TARGET}" "${target}"; then
        error "failed to atomically replace ${target}; the original file was not changed"
        return 1
    fi
    TEMP_TARGET=""

    printf 'Generated %s random value(s) in %s\n' "${#pending_indexes[@]}" "${target}"
}

main "$@"
