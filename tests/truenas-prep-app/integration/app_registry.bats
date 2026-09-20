#!/usr/bin/env bats
# Coverage for the declarative TrueNAS application registry.

load '../helpers/common'

setup_file() {
  require_test_jq
}

setup() {
  prep_common_setup
}

teardown() {
  prep_common_teardown
}

@test "load_app_config: loads exactly the 19 approved simple-model accounts" {
  local row app account_id admin_group_member
  local -a cases=(
    "adguard|3101|false"
    "alloy|3125|false"
    "bitwarden|3126|false"
    "changedetection|3131|false"
    "dawarich|3128|true"
    "dozzle|3109|false"
    "drawio|3119|false"
    "gatus|3103|false"
    "homepage|3102|false"
    "karakeep|3130|false"
    "memos|3129|false"
    "mosquitto|3122|false"
    "openclaw|3127|false"
    "outline|3120|false"
    "prowlarr|3113|false"
    "spottarr|3117|false"
    "traefik|3100|false"
    "unifi|3108|false"
    "wmbusmeters|3123|false"
  )

  for row in "${cases[@]}"; do
    IFS='|' read -r app account_id admin_group_member <<<"${row}"
    run load_app_config_values "${app}"

    assert_success
    assert_output "${app}|svc-app-${app}|${account_id}|${admin_group_member}"
  done

  # Successful loads prove every approved key exists; the count excludes all
  # additional keys, including deferred root/image-only/dataset-only models.
  run jq '.apps | length' "${TEST_REPO_ROOT}/truenas-apps.json"
  assert_success
  assert_output "${#cases[@]}"
}

@test "load_app_config: loads the Memos JSON registry when yq is absent" {
  hide_test_command yq
  run command -v yq
  assert_failure
  run command -v jq
  assert_success

  run load_app_config_values "memos"

  assert_success
  assert_output "memos|svc-app-memos|3129|false"
}

@test "load_app_config: registered service account names and IDs are unique" {
  local field
  for field in account_name account_id; do
    run jq -c --arg field "${field}" \
      '[.apps[] | .[$field]] | group_by(.) | map(select(length > 1) | .[0])' \
      "${TEST_REPO_ROOT}/truenas-apps.json"

    assert_success
    assert_output "[]"
  done
}

@test "load_app_config: advanced aliases, shared identities and non-app directories remain excluded" {
  local app
  for app in echo-server matter-server traefik-forward-auth \
    media photos plex cloudflared shared _bootstrap; do
    run jq -e --arg app "${app}" '.apps | has($app)' \
      "${TEST_REPO_ROOT}/truenas-apps.json"

    assert_failure
    assert_output "false"
  done

  # Do not repurpose legacy alias IDs, media/photos groups, Plex's identity,
  # root or an image-internal UID as a simple-model host service account.
  run jq -c --argjson excluded '[0, 911, 1000, 3104, 3105, 3124, 3200, 3202]' \
    '[.apps | to_entries[] |
      select(.value.account_id as $id | $excluded | index($id) != null)]' \
    "${TEST_REPO_ROOT}/truenas-apps.json"
  assert_success
  assert_output "[]"
}

@test "load_app_config: rejects an unsupported app" {
  run load_app_config "not-registered"

  assert_failure
  assert_output --partial "Unsupported app: not-registered"
}

@test "load_app_config: rejects an invalid app name before querying the registry" {
  run load_app_config "../memos"

  assert_failure
  assert_output --partial "Invalid app name: ../memos"
}

@test "load_app_config: rejects an account name that does not match the app" {
  write_test_app_manifest "dawarich" "svc-app-wrong" "3128" "true"

  run load_app_config "dawarich"

  assert_failure
  assert_output --partial \
    "Invalid account_name for dawarich: expected svc-app-dawarich"
}

@test "load_app_config: rejects a non-integer account ID" {
  write_test_app_manifest "dawarich" "svc-app-dawarich" "not-an-id" "true"

  run load_app_config "dawarich"

  assert_failure
  assert_output --partial \
    "Invalid account_id for dawarich: expected an integer"
}

@test "load_app_config: rejects an account ID outside the service range" {
  write_test_app_manifest "dawarich" "svc-app-dawarich" "3200" "true"

  run load_app_config "dawarich"

  assert_failure
  assert_output --partial \
    "Invalid account_id for dawarich: expected a value from 3100 to 3199"
}

@test "load_app_config: rejects a non-boolean admin membership value" {
  write_test_app_manifest "memos" "svc-app-memos" "3129" "yes"

  run load_app_config "memos"

  assert_failure
  assert_output --partial \
    "Invalid admin_group_member for memos: expected true or false"
}

@test "list_supported_apps: lists every registry key" {
  run jq -r '.apps | keys[] | "  \(.)"' \
    "${TEST_REPO_ROOT}/truenas-apps.json"
  assert_success
  local expected="${output}"

  run list_supported_apps

  assert_success
  assert_output "${expected}"
}

@test "usage: lists all registry keys and follows a replacement manifest" {
  local app
  local -a registered_apps
  run jq -r '.apps | keys[]' "${TEST_REPO_ROOT}/truenas-apps.json"
  assert_success
  mapfile -t registered_apps <<<"${output}"

  run usage
  assert_success
  assert_line "Supported apps:"
  for app in "${registered_apps[@]}"; do
    assert_line "  ${app}"
  done

  write_test_app_manifest "registry-fixture" "svc-app-registry-fixture" "3199" "false"
  run usage
  assert_success
  assert_line "  registry-fixture"
  for app in "${registered_apps[@]}"; do
    refute_line "  ${app}"
  done
}
