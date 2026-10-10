#!/usr/bin/env bash
# Offline source/consumer regressions; never render Compose or read env files.

discovery_setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  DISCOVERY_TMPDIR="$(mktemp -d "${BATS_TMPDIR}/dccd-test.XXXXXX")"
  DISCOVERY_FIXTURES="${REPO_ROOT}/tests/dccd/fixtures/compose-image-discovery"
  MOCK_BIN="${DISCOVERY_TMPDIR}/bin"
  MOCK_LOG="${DISCOVERY_TMPDIR}/calls"
  export MOCK_BIN MOCK_LOG
  mkdir -p "${MOCK_BIN}" "${MOCK_LOG}" "${DISCOVERY_TMPDIR}/services/open-archiver"
  export PATH="${MOCK_BIN}:${PATH}"
  export LC_ALL=C
  DISCOVERY_IMAGE="$(yq -r '.x-app.image' "${REPO_ROOT}/services/open-archiver/compose.yaml")"
  export DISCOVERY_IMAGE
  DISCOVERY_BARE="${DISCOVERY_IMAGE%%@*}"
  export DISCOVERY_BARE
  cp "${DISCOVERY_FIXTURES}/mapping.compose" "${DISCOVERY_TMPDIR}/services/open-archiver/compose.yaml"
  yq -i '.x-app.image = strenv(DISCOVERY_IMAGE)' "${DISCOVERY_TMPDIR}/services/open-archiver/compose.yaml"
  cd "${DISCOVERY_TMPDIR}" || return
}

discovery_teardown() {
  if [[ -n "${DISCOVERY_TMPDIR:-}" ]]; then
    local result=0
    assert_dir_not_exists "${DISCOVERY_TMPDIR}/data" || result=1
    assert_dir_not_exists "${DISCOVERY_TMPDIR}/backups" || result=1
    assert_file_not_exists "${DISCOVERY_TMPDIR}/.env" || result=1
    cd "${REPO_ROOT}" || return
    rm -rf "${DISCOVERY_TMPDIR}"
    return "${result}"
  fi
}

# Deliberately mirror the EXISTING monitors, not a more permissive YAML parser.
# Empty image-less override files yield an empty set, as in process substitution
# in the scripts. Whole-script tests below guard against drift in this proxy.
discovery_scanner_images() {
  # shellcheck disable=SC2312 # Match the existing pipeline, including empty override files.
  grep -rh 'image:' "$@" |
    grep -v '^[[:space:]]*#' |
    sed 's/.*image:[[:space:]]*//' |
    tr -d "'" |
    sort -u
}

discovery_resolved_images() {
  local document
  document="$(yq --yaml-fix-merge-anchor-to-spec=true -r \
    'explode(.) | .services[] | select(has("image")) | .image' "$1")" || return
  if [[ -n "${document}" ]]; then
    printf '%s\n' "${document}" | sort -u
  fi
}

discovery_mock_monitors() {
  local command
  for command in gh crane curl mise trivy date docker docker-compose logger sops wget ssh; do
    cp "${DISCOVERY_FIXTURES}/monitor-mock.bash" "${MOCK_BIN}/${command}"
    chmod +x "${MOCK_BIN}/${command}"
  done
  export DISCOVERY_SARIF="${DISCOVERY_FIXTURES}/scan.sarif"
  export DISCOVERY_OPEN_ISSUE=0 DISCOVERY_STALE=0
  export THRESHOLD_DAYS=90 GH_TOKEN=offline-fixture GITHUB_TOKEN=offline-fixture
  export HOME="${DISCOVERY_TMPDIR}" GH_CONFIG_DIR="${DISCOVERY_TMPDIR}/gh"
  export LOG_COLOR=never LOG_JOURNAL=never LOG_FORMAT=text LOG_LEVEL=INFO
  export LOG_TO_STDIO=1 LOG_TIMESTAMP=regression
  unset LOG_FILE LOG_FILE_MAX_BYTES LOG_FILE_TTL_DAYS
}

discovery_assert_no_network_fallback() {
  local command
  for command in curl docker docker-compose sops wget ssh; do
    assert_mock_not_called "${command}" || return
  done
}
