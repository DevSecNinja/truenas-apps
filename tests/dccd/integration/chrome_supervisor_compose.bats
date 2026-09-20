#!/usr/bin/env bats
# Static, offline contract: never start the stack or read decrypted env files.

load '../helpers/chrome_supervisor'

setup_file() {
  chrome_supervisor_setup_file || return
  local tool
  for tool in yq docker-compose; do
    if ! command -v "${tool}" >/dev/null; then
      printf 'Missing %s; run this test with mise exec -- bats\n' "${tool}" >&2
      return 1
    fi
  done
}

setup() {
  chrome_supervisor_setup
  COMPOSE_FILE="${REPO_ROOT}/services/karakeep/compose.yaml"
}

teardown() {
  chrome_supervisor_teardown
}

@test "chrome_supervisor: Compose retains a digest-pinned Chrome image, browser defaults and existing command flags" {
  run yq -r '.services."karakeep-chrome".image' "${COMPOSE_FILE}"
  assert_success
  assert_output --regexp '^ghcr\.io/karakeep-app/karakeep-chrome(:[[:alnum:]_][[:alnum:]_.-]*)?@sha256:[0-9a-f]{64}$'

  # These are the intended replacement-entrypoint flags, not evidence that
  # run.sh inside the exact image has been inspected or executed.
  run yq -o=json -I=0 '.services."karakeep-chrome".entrypoint' "${COMPOSE_FILE}"
  assert_success
  assert_output '["/bin/bash","/usr/local/bin/chrome-supervisor.sh","/headless-shell/headless-shell","--no-sandbox","--use-gl=angle","--use-angle=swiftshader","--remote-debugging-address=0.0.0.0","--remote-debugging-port=9223"]'

  run yq -o=json -I=0 '.services."karakeep-chrome".command' "${COMPOSE_FILE}"
  assert_success
  assert_output '["--disable-gpu","--disable-dev-shm-usage","--hide-scrollbars","--disable-blink-features=AutomationControlled","--window-size=1440,900"]'
}

@test "chrome_supervisor: Compose mounts the supervisor read-only and hashes config for recreation" {
  assert_file_exists "${REPO_ROOT}/services/karakeep/config/chrome-supervisor.sh"
  run yq -o=json -I=0 '.services."karakeep-chrome".volumes' "${COMPOSE_FILE}"
  assert_success
  assert_output '["./config/chrome-supervisor.sh:/usr/local/bin/chrome-supervisor.sh:ro"]'

  # shellcheck disable=SC2016 # Compose expands this placeholder, not the test shell.
  run yq -r '.services."karakeep-chrome".labels[] | select(. == "config.sha256=${CONFIG_HASH:-}")' "${COMPOSE_FILE}"
  assert_success
  # shellcheck disable=SC2016
  assert_output 'config.sha256=${CONFIG_HASH:-}'
}

@test "chrome_supervisor: Compose keeps init, on-failure restart and security" {
  run yq -o=json -I=0 '.services."karakeep-chrome" |
    {"init": .init, "user": .user,
     "security_opt": .security_opt, "cap_drop": .cap_drop,
     "cap_add": (.cap_add // []), "privileged": (.privileged // false),
     "read_only": .read_only, "tmpfs": .tmpfs,
     "restart_policy": .deploy.restart_policy,
     "restart": .restart, "pid": .pid}' "${COMPOSE_FILE}"
  assert_success
  assert_output '{"init":true,"user":"65534:65534","security_opt":["no-new-privileges=true"],"cap_drop":["ALL"],"cap_add":[],"privileged":false,"read_only":true,"tmpfs":["/tmp","/var/cache/fontconfig"],"restart_policy":{"condition":"on-failure","max_attempts":3,"window":"120s"},"restart":null,"pid":null}'

  run yq -o=json -I=0 '.services."karakeep-chrome" |
    {"ports": (.ports // []), "networks": .networks}' "${COMPOSE_FILE}"
  assert_success
  assert_output '{"ports":[],"networks":["karakeep-browser-egress","karakeep-browser"]}'
}

@test "chrome_supervisor: Compose validates offline with a bounded positive default PID limit" {
  touch "${TEST_TMPDIR}/empty.env"
  # env -i excludes host secrets and Compose overrides; --env-file excludes
  # implicit .env loading. Render only synthetic values, without reading
  # service env files or contacting a daemon.
  run --separate-stderr env -i PATH="${PATH}" HOME="${TEST_TMPDIR}" \
    DOMAINNAME=supervisor.invalid \
    KARAKEEP_MEILI_MASTER_KEY=synthetic-test-value \
    KARAKEEP_NEXTAUTH_SECRET=synthetic-test-value \
    KARAKEEP_MOBILE_PROXY_TOKEN=synthetic-test-value \
    docker-compose --project-name chrome-supervisor-contract \
    --env-file "${TEST_TMPDIR}/empty.env" -f "${COMPOSE_FILE}" \
    config --no-env-resolution --format json
  assert_success
  # Check the rendered default, allowing future configurable limits without
  # pinning a value from another change. Missing, zero and unlimited (-1) fail.
  run yq -p=json -r '.services."karakeep-chrome".pids_limit' <<<"${output}"
  assert_success
  assert_output --regexp '^[1-9][0-9]*$'
}
