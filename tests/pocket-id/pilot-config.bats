#!/usr/bin/env bats
# Offline source/model checks only: no daemon, pulls, secret files or lifecycle claims.

load 'helpers/common'

setup_file() {
  pocket_require_helpers || return
  local tool
  for tool in yq jq; do
    command -v "${tool}" || return 1
  done
  if docker-cli-plugin-docker-compose version >/dev/null 2>&1; then
    export POCKET_COMPOSE_PROVIDER=docker-cli-plugin-docker-compose
  elif docker-compose version >/dev/null 2>&1; then
    export POCKET_COMPOSE_PROVIDER=docker-compose
  elif docker compose version >/dev/null 2>&1; then
    export POCKET_COMPOSE_PROVIDER=docker
  else
    printf 'Required working Compose provider missing: docker-cli-plugin-docker-compose, docker-compose or docker compose\n' >&2
    return 1
  fi
}

setup() {
  pocket_load_helpers
  # Keep real yq/jq/Compose; do not install the backup guard's PATH mocks.
  POCKET_CONFIG_TMPDIR="$(mktemp -d "${BATS_TMPDIR}/dccd-test.XXXXXX")"
  POCKET_COMPOSE_FILE="${POCKET_REPO_ROOT}/services/pocket-id/compose.yaml"
  TRAEFIK_COMPOSE_FILE="${POCKET_REPO_ROOT}/services/traefik/compose.yaml"
  cd "${POCKET_CONFIG_TMPDIR}" || return
}

teardown() {
  if [[ -n "${POCKET_CONFIG_TMPDIR:-}" ]]; then
    local result=0
    assert_dir_not_exists "${POCKET_CONFIG_TMPDIR}/data" || result=1
    assert_dir_not_exists "${POCKET_CONFIG_TMPDIR}/backups" || result=1
    assert_file_not_exists "${POCKET_CONFIG_TMPDIR}/.env" || result=1
    rm -rf -- "${POCKET_CONFIG_TMPDIR}"
    return "${result}"
  fi
}

pocket_compose_config() {
  local format="$1"
  shift
  local -a compose_command=("${POCKET_COMPOSE_PROVIDER}") config_args=()
  if [[ "${POCKET_COMPOSE_PROVIDER}" == docker ]]; then
    compose_command+=(compose)
  fi
  case "${format}" in
  services) config_args=(--services) ;;
  json) config_args=(--format json) ;;
  *) return 1 ;;
  esac
  # Render the actual files, including native !override semantics. No model
  # rewriting: --no-env-resolution leaves service env_file entries unread.
  # env -i also removes inherited COMPOSE_PROFILES and production credentials.
  env -i PATH="${PATH}" HOME="${POCKET_CONFIG_TMPDIR}" TMPDIR="${POCKET_CONFIG_TMPDIR}" \
    LC_ALL=C DOMAINNAME=example.invalid \
    ENCRYPTION_KEY=synthetic-pilot-key-at-least-16-bytes \
    DB_ENC_PASSPHRASE=synthetic-pilot-passphrase COMPOSE_DISABLE_ENV_FILE=true \
    "${compose_command[@]}" \
    --project-directory "${POCKET_CONFIG_TMPDIR}" \
    --project-name "pocket-id-pilot-${BATS_TEST_NUMBER}-$$" \
    --env-file /dev/null "$@" config --no-env-resolution "${config_args[@]}"
}

@test "pocket_pilot_config: default selection includes exactly three services with init and healthy backup ordering" {
  run pocket_compose_config services -f "${POCKET_COMPOSE_FILE}"
  assert_success
  local selected="${output}"

  run pocket_compose_config json -f "${POCKET_COMPOSE_FILE}"
  assert_success
  local document="${output}"

  run jq -c '.services | keys' <<<"${document}"
  assert_success
  assert_output '["pocket-id","pocket-id-db-backup","pocket-id-init"]'

  run jq -e --arg selected "${selected}" '
    ((.services | keys) == ($selected | split("\n") | sort)) and
    (.services | all(.[]; (.profiles // []) == [])) and
    ((.services | with_entries(
      .value = ((.value.depends_on // {}) | with_entries(.value = .value.condition))
    )) == {
      "pocket-id-init": {},
      "pocket-id": {"pocket-id-init": "service_completed_successfully"},
      "pocket-id-db-backup": {"pocket-id": "service_healthy"}
    }) and
    (.services["pocket-id"].healthcheck.test == ["CMD", "/app/pocket-id", "healthcheck"]) and
    (.services["pocket-id"].healthcheck.disable != true) and
    (.services["pocket-id-init"].restart == "no")
  ' <<<"${document}"
  assert_success
  assert_output "true"
}

@test "pocket_pilot_config: source has no profile gates and an unrelated profile still selects the whole stack" {
  run yq -o=json '.services' "${POCKET_COMPOSE_FILE}"
  assert_success
  local source="${output}"
  run jq -e 'all(.[]; has("profiles") | not)' <<<"${source}"
  assert_success
  assert_output "true"

  run pocket_compose_config services --profile surveillance -f "${POCKET_COMPOSE_FILE}"
  assert_success
  local selected="${output}"
  run jq -Rsc 'split("\n") | map(select(length > 0)) | sort' <<<"${selected}"
  assert_success
  assert_output '["pocket-id","pocket-id-db-backup","pocket-id-init"]'
}

@test "pocket_pilot_config: app uses registry UID 3133 with private persistence and no published ports" {
  assert_dir_exists "${POCKET_REPO_ROOT}/services/pocket-id"
  assert_file_exists "${POCKET_COMPOSE_FILE}"
  run pocket_compose_config json -f "${POCKET_COMPOSE_FILE}"
  assert_success
  local document="${output}"
  run jq -e --arg root "${POCKET_CONFIG_TMPDIR}" \
    --slurpfile registry "${POCKET_REPO_ROOT}/truenas-apps.json" '
    $registry[0].apps["pocket-id"] as $account |
    ($account == {
      "account_name": "svc-app-pocket-id", "account_id": 3133, "admin_group_member": false
    }) and
    (.services["pocket-id"].user == "\($account.account_id):\($account.account_id)") and
    (.services | all(.[]; ((.ports // []) | length) == 0)) and
    (.services["pocket-id"].read_only == true) and
    ((.services["pocket-id"].networks | keys) == ["pocket-id-frontend"]) and
    (.services["pocket-id-init"].network_mode == "none") and
    (.services["pocket-id-init"].read_only == true) and
    ((.services["pocket-id"].volumes | map({
      type, source, target, read_only: (.read_only // false)
    })) == [{
      "type": "bind", "source": ($root + "/data"), "target": "/app/data", "read_only": false
    }]) and
    ((.services["pocket-id-init"].volumes | map({type, source, target})) == [{
      "type": "bind", "source": ($root + "/data"), "target": "/data"
    }]) and
    (.services["pocket-id"].environment.DB_CONNECTION_STRING == "/app/data/pocket-id.db") and
    (.services["pocket-id"].environment.FILE_BACKEND == "database")
  ' <<<"${document}"
  assert_success
  assert_output "true"
}

@test "pocket_pilot_config: backup retains the bounded guard, dccd job label and read-only source and config" {
  run pocket_compose_config json -f "${POCKET_COMPOSE_FILE}"
  assert_success
  local document="${output}"
  run jq -e --arg root "${POCKET_CONFIG_TMPDIR}" '
    .services["pocket-id-db-backup"] |
    (.command == [
      "timeout", "--signal=TERM", "--kill-after=10s", "180s", "bash", "/config/verify-backup.sh"
    ]) and
    (.labels["dccd.backup-jobs"] == "01") and
    (.network_mode == "none") and (.restart == "no") and
    (.environment.MODE == "MANUAL") and
    (.environment.MANUAL_RUN_FOREVER == "FALSE") and
    (.environment.CONTAINER_ENABLE_SCHEDULING == "FALSE") and
    (.environment.DBBACKUP_USER == "pocketbackup") and
    (.environment.DBBACKUP_GROUP == "pocketbackup") and
    (.environment.DB01_HOST == "/pocket-id-data/pocket-id.db") and
    (.environment.DEFAULT_ENCRYPT == "TRUE") and
    (.environment.DEFAULT_ENCRYPT_PASSPHRASE == "synthetic-pilot-passphrase") and
    ((.volumes | map({
      type, source, target, read_only: (.read_only // false)
    }) | sort_by(.target)) == [
      {"type": "bind", "source": ($root + "/backups/db-backup"), "target": "/backup", "read_only": false},
      {"type": "bind", "source": ($root + "/config/verify-backup.sh"), "target": "/config/verify-backup.sh", "read_only": true},
      {"type": "bind", "source": ($root + "/data"), "target": "/pocket-id-data", "read_only": true}
    ])
  ' <<<"${document}"
  assert_success
  assert_output "true"
}

@test "pocket_pilot_config: DNS has exactly one id domain record pointing at the NAS variable" {
  # Unbound repeats local-data keys, so parse records rather than treating this
  # configuration as YAML (which would discard duplicate keys).
  run awk -F '"' '
    /^[[:space:]]*local-data:[[:space:]]*"/ {
      split($2, record, /[[:space:]]+/)
      if (record[1] == "id.${DOMAINNAME}") print $2
    }
  ' "${POCKET_REPO_ROOT}/services/adguard/config/unbound/conf.d/a-records.conf"
  assert_success
  assert_output 'id.${DOMAINNAME} A ${IP_SVLNAS}'
}

@test "pocket_pilot_config: active Traefik joins the app bridge and the ID router avoids an authentication loop" {
  run pocket_compose_config json -f "${TRAEFIK_COMPOSE_FILE}"
  assert_success
  local traefik="${output}"
  run jq -e '
    (.services.traefik.networks | has("pocket-id-frontend")) and
    (.networks["pocket-id-frontend"].name == "pocket-id-frontend") and
    (.networks["pocket-id-frontend"].external == true)
  ' <<<"${traefik}"
  assert_success
  assert_output "true"

  run pocket_compose_config json -f "${POCKET_COMPOSE_FILE}"
  assert_success
  local document="${output}"
  run jq -e '
    (.networks["pocket-id-frontend"].name == "pocket-id-frontend") and
    (.networks["pocket-id-frontend"].driver == "bridge") and
    (.networks["pocket-id-frontend"].external != true) and
    (.services["pocket-id"].environment.APP_URL == "https://id.example.invalid") and
    (.services["pocket-id"].labels | {
      enabled: .["traefik.enable"],
      network: .["traefik.docker.network"],
      rule: .["traefik.http.routers.pocket-id-rtr.rule"],
      entrypoints: .["traefik.http.routers.pocket-id-rtr.entrypoints"],
      middlewares: .["traefik.http.routers.pocket-id-rtr.middlewares"],
      service: .["traefik.http.routers.pocket-id-rtr.service"],
      port: .["traefik.http.services.pocket-id.loadbalancer.server.port"]
    } == {
      "enabled": "true",
      "network": "pocket-id-frontend",
      "rule": "Host(`id.example.invalid`)",
      "entrypoints": "https",
      "middlewares": "chain-no-auth@file",
      "service": "pocket-id",
      "port": "1411"
    })
  ' <<<"${document}"
  assert_success
  assert_output "true"
}

@test "pocket_pilot_config: svlazext override excludes the Pocket network and the inert fragment is absent" {
  assert_file_not_exists "${POCKET_REPO_ROOT}/services/traefik/compose.pocket-id.yaml"
  run pocket_compose_config json -f "${TRAEFIK_COMPOSE_FILE}" \
    -f "${POCKET_REPO_ROOT}/services/traefik/compose.svlazext.yaml"
  assert_success
  local document="${output}"
  # An unused top-level network is harmless; the service attachment is the gate.
  run jq -e '
    .services.traefik.networks |
    (has("traefik-backend")) and (has("adguard-frontend")) and
    (has("pocket-id-frontend") | not)
  ' <<<"${document}"
  assert_success
  assert_output "true"
}
