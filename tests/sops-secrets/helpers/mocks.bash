#!/usr/bin/env bash
# PATH-based mise/SOPS and random-source mocks.

create_mise_mock() {
  cat >"${MOCK_BIN}/mise" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >>"${MOCK_LOG}/mise.calls"

if [ -n "${SOPS_AGE_KEY_CMD:-}" ]; then
    printf '%s\n' command >>"${MOCK_LOG}/key-source.calls"
    /bin/sh -c "${SOPS_AGE_KEY_CMD}" >/dev/null 2>&1 || exit 91
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
  chmod +x "${MOCK_BIN}/mise"
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

sops_set_count() {
  if [[ -f "${MOCK_LOG}/sops-set.count" ]]; then
    tr -d '[:space:]' <"${MOCK_LOG}/sops-set.count"
  else
    printf '0\n'
  fi
}
