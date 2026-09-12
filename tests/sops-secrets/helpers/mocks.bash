#!/usr/bin/env bash
# PATH-based mise/SOPS and random-source mocks.

# Writes a fake `sops` executable to $1 that emulates just enough of real
# SOPS behavior (dotenv decrypt/set plus SOPS_AGE_KEY_CMD/SOPS_AGE_KEY_FILE
# key-source handling) for generate-sops-secrets.sh and
# validate-sops-secrets.sh to exercise their full logic against. Shared by
# create_mise_mock (fronted by a `mise exec -- sops ...` wrapper, the
# default invocation path) and create_fake_sops_bin (installed as an
# explicit SOPS_BIN override), so both code paths run through byte-for-byte
# identical sops semantics instead of two subtly different test doubles.
write_fake_sops() {
  local path="${1:?write_fake_sops: path required}"

  cat >"${path}" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_LOG}/sops.calls"

if [ -n "${SOPS_AGE_KEY_CMD:-}" ]; then
    printf '%s\n' command >>"${MOCK_LOG}/key-source.calls"
    if [[ ! "${SOPS_AGE_KEY_CMD}" =~ ^op[[:space:]]+read[[:space:]]+\"([^\"]+)\"$ ]]; then
        exit 91
    fi
    key_output="$(op read "${BASH_REMATCH[1]}")" || exit 91
    identity_count=0
    invalid_identity=0
    while IFS= read -r line || [ -n "${line}" ]; do
        line="${line%$'\r'}"
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        if [[ "${line}" =~ ^AGE-(SECRET-KEY|PLUGIN)-[0-9A-Z-]+$ ]]; then
            identity_count=$((identity_count + 1))
        else
            invalid_identity=1
        fi
    done <<<"${key_output}"
    unset key_output line
    [ "${identity_count}" -eq 1 ] && [ "${invalid_identity}" -eq 0 ] || exit 91
elif [ -n "${SOPS_AGE_KEY_FILE:-}" ]; then
    printf '%s\n' file >>"${MOCK_LOG}/key-source.calls"
    [ -f "${SOPS_AGE_KEY_FILE}" ] || exit 91
fi

operation=""
variable=""
target=""
value=""
for argument do
    case "${argument}" in
        decrypt|set)
            operation="${argument}"
            ;;
        "${MOCK_TARGET}"|"${MOCK_TARGET}".generated.*)
            target="${argument}"
            ;;
        \[\"*\"\])
            variable="${argument#\[\"}"
            variable="${variable%\"\]}"
            ;;
    esac
done

case "${operation}" in
    decrypt)
        if [ "${MOCK_DECRYPT_EXIT:-0}" != "0" ]; then
            exit "${MOCK_DECRYPT_EXIT}"
        fi
        if [ "${MOCK_REQUIRE_ENCRYPTED:-0}" = "1" ] &&
            ! grep -q '^sops_mac=ENC\[AES256_GCM,' "${target}"; then
            exit 92
        fi
        if [ -n "${variable}" ]; then
            value="$(awk -F= -v variable="${variable}" '
                $1 == variable { print substr($0, length(variable) + 2); found = 1 }
                END { if (!found) exit 1 }
            ' "${MOCK_PLAINTEXT}")" || exit 1
            printf '%s\n' "${value}"
        else
            cat "${MOCK_PLAINTEXT}"
        fi
        ;;
    set)
        count_file="${MOCK_LOG}/sops-set.count"
        count=0
        if [ -f "${count_file}" ]; then
            count="$(cat "${count_file}")"
        fi
        count=$((count + 1))
        printf '%s\n' "${count}" >"${count_file}"

        value="$(cat)"
        if [ -z "${value}" ]; then
            for argument do
                candidate="${argument#\"}"
                candidate="${candidate%\"}"
                if printf '%s\n' "${candidate}" | grep -Eq '^[0-9a-f]+$'; then
                    value="${candidate}"
                fi
            done
        fi
        value="${value#\"}"
        value="${value%\"}"

        if [ "${MOCK_SET_FAIL:-0}" = "1" ]; then
            if [ "${MOCK_SET_CORRUPT:-0}" = "1" ]; then
                printf '%s\n' 'corrupted' >"${target}"
            fi
            exit 93
        fi
        if [ -z "${variable}" ] ||
            ! printf '%s\n' "${value}" | grep -Eq '^[0-9a-f]+$'; then
            exit 94
        fi

        awk -v variable="${variable}" -v value="${value}" '
            index($0, variable "=") == 1 { print variable "=" value; next }
            { print }
        ' "${MOCK_PLAINTEXT}" >"${MOCK_LOG}/plaintext.next"
        mv "${MOCK_LOG}/plaintext.next" "${MOCK_PLAINTEXT}"

        cat >"${target}" <<EOF
FIRST=ENC[AES256_GCM,data:mock-${count},iv:bW9jaw==,tag:bW9jaw==,type:str]
SECOND=ENC[AES256_GCM,data:mock-${count},iv:bW9jaw==,tag:bW9jaw==,type:str]
EXISTING=ENC[AES256_GCM,data:mock-${count},iv:bW9jaw==,tag:bW9jaw==,type:str]
sops_age__list_0__map_recipient=age1example
sops_mac=ENC[AES256_GCM,data:mock-${count},iv:bW9jaw==,tag:bW9jaw==,type:str]
sops_version=3.13.3
EOF
        ;;
    *)
        exit 2
        ;;
esac
MOCK
  chmod +x "${path}"
}

# Default invocation path: a `mise` wrapper that forwards `exec -- sops ...`
# straight through to the shared fake sops implementation above. Preserves
# the existing mise.calls call-log (tests assert on its presence/absence and
# contents) in addition to the fake sops's own sops.calls log.
create_mise_mock() {
  write_fake_sops "${MOCK_BIN}/__fake_sops"
  cat >"${MOCK_BIN}/mise" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${MOCK_LOG}/mise.calls"
"${MOCK_BIN}/__fake_sops" "\$@"
MOCK
  chmod +x "${MOCK_BIN}/mise"
}

# Explicit SOPS_BIN override path: installs the identical fake sops
# implementation directly at an arbitrary path, bypassing mise entirely.
# Tests set SOPS_BIN to the returned path (or pass it explicitly) to prove
# the override is honored — mise.calls must never appear when this is used.
create_fake_sops_bin() {
  local path="${1:?create_fake_sops_bin: path required}"

  write_fake_sops "${path}"
}

create_od_mock() {
  cat >"${MOCK_BIN}/od" <<'MOCK'
#!/bin/sh
if [ "${MOCK_OD_FAIL:-0}" = "1" ]; then
    exit 1
fi

count_file="${MOCK_LOG}/od.count"
count=0
if [ -f "${count_file}" ]; then
    count="$(cat "${count_file}")"
fi
count=$((count + 1))
printf '%s\n' "${count}" >"${count_file}"

case "${count}" in
    1) byte="ab" ;;
    2) byte="cd" ;;
    *) byte="ef" ;;
esac

bytes=0
while [ "$#" -gt 0 ]; do
    if [ "$1" = "-N" ]; then
        bytes="$2"
        break
    fi
    shift
done

index=0
while [ "${index}" -lt "${bytes}" ]; do
    printf ' %s' "${byte}"
    index=$((index + 1))
done
printf '\n'
MOCK
  chmod +x "${MOCK_BIN}/od"
}

create_op_mock() {
  cat >"${MOCK_BIN}/op" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >>"${MOCK_LOG}/op.calls"

if [ "${MOCK_OP_EXIT:-0}" != "0" ]; then
    exit "${MOCK_OP_EXIT}"
fi
if [ -n "${MOCK_OP_OUTPUT_FILE:-}" ]; then
    cat "${MOCK_OP_OUTPUT_FILE}"
else
    printf '%s\n' "${MOCK_OP_OUTPUT:-}"
fi
MOCK
  chmod +x "${MOCK_BIN}/op"
}

sops_set_count() {
  if [[ -f "${MOCK_LOG}/sops-set.count" ]]; then
    tr -d '[:space:]' <"${MOCK_LOG}/sops-set.count"
  else
    printf '0\n'
  fi
}
