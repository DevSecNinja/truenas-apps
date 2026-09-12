#!/usr/bin/env bash
# Stateful command mocks for truenas-prep-app.sh integration tests.

create_prep_mocks() {
  cat >"${MOCK_BIN}/midclt" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_LOG}/midclt.calls"

case "$1 $2" in
"call group.query")
    printf '%s\n' "GROUPS_STATE"
    ;;
"call group.create")
    touch "${MOCK_STATE}/group.exists"
    ;;
"call user.query")
    printf '%s\n' "USERS_STATE"
    ;;
"call user.create")
    touch "${MOCK_STATE}/user.exists"
    ;;
"call user.update")
    touch "${MOCK_STATE}/admin-member"
    ;;
"call pool.dataset.create")
    if [[ -e "${MOCK_STATE}/dataset-create-fails" ]]; then
        exit 1
    fi
    mkdir -p "${TEST_REPO_ROOT}/services/${MOCK_APP_NAME}"
    touch "${MOCK_STATE}/dataset.exists"
    ;;
*)
    printf 'Unexpected midclt call: %s\n' "$*" >&2
    exit 2
    ;;
esac
MOCK

  cat >"${MOCK_BIN}/zfs" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_LOG}/zfs.calls"

if [[ "$*" == "list -H -o name,mountpoint" ]]; then
    printf 'tank/services\t%s\n' "${TEST_REPO_ROOT}/services"
elif [[ "$*" == "list -H -o name tank/services/${MOCK_APP_NAME}" ]] &&
    [[ -e "${MOCK_STATE}/dataset.exists" ]]; then
    printf '%s\n' "tank/services/${MOCK_APP_NAME}"
else
    exit 1
fi
MOCK

  cat >"${MOCK_BIN}/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_LOG}/docker.calls"
[[ -e "${MOCK_STATE}/app-running" ]] && printf '%s\n' "container-id"
MOCK

  cat >"${MOCK_BIN}/chown" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_LOG}/chown.calls"
MOCK

  cat >"${MOCK_BIN}/chmod" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_LOG}/chmod.calls"
MOCK

  cat >"${MOCK_BIN}/jq" <<'MOCK'
#!/usr/bin/env bash
args="$*"

# Registry reads must exercise jq's real JSON parsing. Only the focused
# TrueNAS API queries below are mocked because midclt returns state sentinels.
for arg in "$@"; do
    if [[ "${arg}" == "${TEST_REPO_ROOT}/truenas-apps.json" ]]; then
        exec "${REAL_JQ}" "$@"
    fi
done
case "${args}" in
*'.account_name | select(type == "string")'* | \
*'.account_id | select(type == "number" and floor == .)'* | \
*'.admin_group_member | select(type == "boolean") | tostring'*)
    exec "${REAL_JQ}" "$@"
    ;;
esac

input="$(cat)"

case "${args}" in
*'{name: $name, gid: $gid'*)
    printf '{"name":"%s","gid":%s,"smb":false}\n' \
        "${MOCK_ACCOUNT_NAME}" "${MOCK_ACCOUNT_ID}"
    ;;
*'username: $username'*)
    printf '{"username":"%s","uid":%s,"group":41}\n' \
        "${MOCK_ACCOUNT_NAME}" "${MOCK_ACCOUNT_ID}"
    ;;
*'{name: $name}'*)
    printf '{"name":"tank/services/%s"}\n' "${MOCK_APP_NAME}"
    ;;
*'{groups: $groups}'*)
    printf '%s\n' '{"groups":[41]}'
    ;;
*'first(.[] | select(.local == true and .name == $name)) | .id'*)
    if [[ -e "${MOCK_STATE}/group.exists" ]]; then
        printf '%s\n' "41"
    else
        printf '%s\n' "null"
    fi
    ;;
*'.name == $name'*)
    if [[ -e "${MOCK_STATE}/group.exists" ]]; then
        printf '%s\n' "GROUP_CORRECT"
    elif [[ -e "${MOCK_STATE}/group-name-wrong-gid" ]]; then
        printf '%s\n' "GROUP_WRONG"
    fi
    ;;
*'.gid == $gid'*)
    [[ -e "${MOCK_STATE}/gid-collision" ]] &&
        printf '%s\n' "GROUP_GID_COLLISION"
    ;;
*'--arg name truenas_admin'*'.username == $name'*)
    printf '%s\n' "ADMIN_USER"
    ;;
*'.username == $name'*)
    if [[ -e "${MOCK_STATE}/user.exists" ]]; then
        printf '%s\n' "USER_CORRECT"
    elif [[ -e "${MOCK_STATE}/user-name-wrong-uid" ]]; then
        printf '%s\n' "USER_WRONG"
    fi
    ;;
*'.uid == $uid'*)
    [[ -e "${MOCK_STATE}/uid-collision" ]] &&
        printf '%s\n' "USER_UID_COLLISION"
    ;;
*'index($group_id) != null'*)
    [[ -e "${MOCK_STATE}/admin-member" ]]
    ;;
*'.groups + [$group_id] | unique'*)
    printf '%s\n' "[41]"
    ;;
"-r .gid")
    case "${input}" in
    GROUP_CORRECT) printf '%s\n' "${MOCK_ACCOUNT_ID}" ;;
    GROUP_WRONG) printf '%s\n' "9999" ;;
    esac
    ;;
"-r .name")
    [[ "${input}" == "GROUP_GID_COLLISION" ]] &&
        printf '%s\n' "legacy-group"
    ;;
"-r .id")
    case "${input}" in
    GROUP_CORRECT) printf '%s\n' "41" ;;
    ADMIN_USER) printf '%s\n' "7" ;;
    esac
    ;;
"-r .uid")
    case "${input}" in
    USER_CORRECT) printf '%s\n' "${MOCK_ACCOUNT_ID}" ;;
    USER_WRONG) printf '%s\n' "9999" ;;
    esac
    ;;
"-r .group.id")
    printf '%s\n' "41"
    ;;
"-r .username")
    [[ "${input}" == "USER_UID_COLLISION" ]] &&
        printf '%s\n' "legacy-user"
    ;;
*)
    printf 'Unexpected jq call: %s\n' "${args}" >&2
    exit 2
    ;;
esac
MOCK

  /bin/chmod +x "${MOCK_BIN}/midclt" "${MOCK_BIN}/zfs" \
    "${MOCK_BIN}/docker" "${MOCK_BIN}/chown" \
    "${MOCK_BIN}/chmod" "${MOCK_BIN}/jq"
}

assert_mock_called_with() {
  local command="$1"
  local expected="$2"

  assert_file_exists "${MOCK_LOG}/${command}.calls"
  run grep -F "${expected}" "${MOCK_LOG}/${command}.calls"
  assert_success
}

assert_mock_call_count() {
  local command="$1"
  local expected="$2"

  if [[ -e "${MOCK_LOG}/${command}.calls" ]]; then
    run awk 'END { print NR }' "${MOCK_LOG}/${command}.calls"
  else
    run printf '%s\n' "0"
  fi
  assert_success
  assert_output "${expected}"
}

assert_midclt_call_count() {
  local method="$1"
  local expected="$2"

  assert_file_exists "${MOCK_LOG}/midclt.calls"
  run awk -v method="call ${method}" \
    'index($0, method) == 1 { count++ } END { print count + 0 }' \
    "${MOCK_LOG}/midclt.calls"
  assert_success
  assert_output "${expected}"
}
