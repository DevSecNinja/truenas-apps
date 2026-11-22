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
    assert_dir_not_exists "${POCKET_CONFIG_TMPDIR}/services/pocket-id/data" || result=1
    assert_dir_not_exists "${POCKET_CONFIG_TMPDIR}/services/pocket-id/backups" || result=1
    assert_file_not_exists "${POCKET_CONFIG_TMPDIR}/.env" || result=1
    rm -rf -- "${POCKET_CONFIG_TMPDIR}"
    return "${result}"
  fi
}

pocket_compose_config() {
  local format="$1"
  shift
  local -a compose_command=("${POCKET_COMPOSE_PROVIDER}") config_args=()
  local project_directory="${POCKET_CONFIG_TMPDIR}" env_file=/dev/null
  local -a env_resolution_args=(--no-env-resolution)
  local -a interpolation_env=(
    DOMAINNAME=example.invalid
    ENCRYPTION_KEY=testtesttesttest
    DB_ENC_PASSPHRASE=synthetic-pilot-passphrase
  )
  if [[ "${POCKET_COMPOSE_PROVIDER}" == docker ]]; then
    compose_command+=(compose)
  fi
  case "${format}" in
  services) config_args=(--services) ;;
  json) config_args=(--format json) ;;
  json-with-env)
    config_args=(--format json)
    project_directory="${POCKET_CONFIG_TMPDIR}/services/pocket-id"
    env_file="${project_directory}/.env"
    env_resolution_args=()
    interpolation_env=()
    ;;
  *) return 1 ;;
  esac
  # Render the actual files, including native !override semantics. No model
  # rewriting: by default, --no-env-resolution leaves env_file entries unread.
  # json-with-env instead resolves only the isolated synthetic fixture files.
  # env -i also removes inherited COMPOSE_PROFILES and production credentials.
  env -i PATH="${PATH}" HOME="${POCKET_CONFIG_TMPDIR}" TMPDIR="${POCKET_CONFIG_TMPDIR}" \
    LC_ALL=C COMPOSE_DISABLE_ENV_FILE=true \
    "${interpolation_env[@]}" "${compose_command[@]}" \
    --project-directory "${project_directory}" \
    --project-name "pocket-id-pilot-${BATS_TEST_NUMBER}-$$" \
    --env-file "${env_file}" "$@" config "${env_resolution_args[@]}" "${config_args[@]}"
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

@test "pocket_pilot_config: app Docker and OTEL logging are disabled without disabling backup receipt logging" {
  run pocket_compose_config json -f "${POCKET_COMPOSE_FILE}"
  assert_success
  local document="${output}"
  run jq -e '
    (.services["pocket-id"].logging.driver == "none") and
    (.services["pocket-id"].environment.OTEL_LOGS_EXPORTER == "none") and
    (.services["pocket-id"].environment.OTEL_TRACES_EXPORTER == "none") and
    (.services["pocket-id-db-backup"].logging.driver != "none")
  ' <<<"${document}"
  assert_success
  assert_output "true"
}

@test "pocket_pilot_config: the router matching the Pocket ID hostname disables access logs" {
  run pocket_compose_config json -f "${POCKET_COMPOSE_FILE}"
  assert_success
  local document="${output}"
  run jq -e '
    .services["pocket-id"].labels |
    (.["traefik.http.routers.pocket-id-rtr.rule"] == "Host(`id.example.invalid`)") and
    (.["traefik.http.routers.pocket-id-rtr.service"] == "pocket-id") and
    (.["traefik.http.routers.pocket-id-rtr.observability.accesslogs"] == "false")
  ' <<<"${document}"
  assert_success
  assert_output "true"
}

@test "pocket_pilot_config: full env resolution keeps app secrets out of backup while retaining explicit backup settings" {
  local app_directory="${POCKET_CONFIG_TMPDIR}/services/pocket-id"
  local shared_directory="${POCKET_CONFIG_TMPDIR}/services/shared/env"
  mkdir -p "${app_directory}" "${shared_directory}"
  # Copy only Compose, never a checkout .env or shared env file. Config rendering
  # needs no database, backup directory, mounted script, daemon or image.
  cp -- "${POCKET_COMPOSE_FILE}" "${app_directory}/compose.yaml"
  assert_file_exists "${app_directory}/compose.yaml"
  touch "${app_directory}/.env" "${shared_directory}/tz.env"
  # Use the existing yq writer to create dotenv-compatible properties in place.
  run yq -i -p=yaml -o=props '{
    "DOMAINNAME": "example.invalid",
    "ENCRYPTION_KEY": "testtesttesttest",
    "DB_ENC_PASSPHRASE": "synthetic-pilot-passphrase"
  }' "${app_directory}/.env"
  assert_success
  run yq -i -p=yaml -o=props '{"TZ": "Etc/UTC"}' "${shared_directory}/tz.env"
  assert_success
  assert_file_exists "${app_directory}/.env"
  assert_file_exists "${shared_directory}/tz.env"

  run yq -p=props -o=json '.' "${app_directory}/.env"
  assert_success
  local fixture="${output}"
  run jq -e '. == {
    "DOMAINNAME": "example.invalid",
    "ENCRYPTION_KEY": "testtesttesttest",
    "DB_ENC_PASSPHRASE": "synthetic-pilot-passphrase"
  }' <<<"${fixture}"
  assert_success
  assert_output "true"

  # Unlike the source-only helper mode, this loads service env_file entries and
  # supplies interpolation solely from the synthetic .env, not shell variables.
  run pocket_compose_config json-with-env -f "${app_directory}/compose.yaml"
  assert_success
  local document="${output}"
  run jq -e --argjson fixture "${fixture}" '
    (.services["pocket-id"].environment.ENCRYPTION_KEY == $fixture.ENCRYPTION_KEY) and
    (.services["pocket-id"].environment.APP_URL == ("https://id." + $fixture.DOMAINNAME))
  ' <<<"${document}"
  assert_success
  assert_output "true"

  run jq -e '
    .services["pocket-id-db-backup"].environment |
    (has("ENCRYPTION_KEY") | not) and
    (has("DOMAINNAME") | not) and
    (has("DB_ENC_PASSPHRASE") | not)
  ' <<<"${document}"
  assert_success
  assert_output "true"

  run jq -e --argjson fixture "${fixture}" '
    .services["pocket-id-db-backup"].environment | {
      TZ, MODE, MANUAL_RUN_FOREVER, CONTAINER_ENABLE_SCHEDULING,
      DBBACKUP_USER, DBBACKUP_GROUP, DB01_TYPE, DB01_HOST,
      DEFAULT_ENCRYPT, DEFAULT_ENCRYPT_PASSPHRASE,
      DEFAULT_COMPRESSION, DEFAULT_CHECKSUM, DEFAULT_CLEANUP_TIME
    } == {
      "TZ": "Etc/UTC",
      "MODE": "MANUAL",
      "MANUAL_RUN_FOREVER": "FALSE",
      "CONTAINER_ENABLE_SCHEDULING": "FALSE",
      "DBBACKUP_USER": "pocketbackup",
      "DBBACKUP_GROUP": "pocketbackup",
      "DB01_TYPE": "sqlite3",
      "DB01_HOST": "/pocket-id-data/pocket-id.db",
      "DEFAULT_ENCRYPT": "TRUE",
      "DEFAULT_ENCRYPT_PASSPHRASE": $fixture.DB_ENC_PASSPHRASE,
      "DEFAULT_COMPRESSION": "ZSTD",
      "DEFAULT_CHECKSUM": "SHA1",
      "DEFAULT_CLEANUP_TIME": "2880"
    }
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
