#!/usr/bin/env bats
# Source-layout contract plus offline execution of the actual monitor consumers.
# No Renovate reimplementation: upstream extraction/update is checked separately.
# shellcheck disable=SC2030,SC2031 # BATS test cases intentionally have isolated environments.

load '../helpers/diagnostics'
load '../helpers/compose_image_discovery'

setup_file() {
  diagnostics_require_helpers || return
  local tool root
  for tool in yq jq git; do
    command -v "${tool}" || return 1
  done
  root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  # shellcheck disable=SC2312 # git and grep form the checked tracked-file inventory.
  DISCOVERY_COMPOSE_FILES="$(git -C "${root}" ls-files -- \
    '*compose*.yaml' '*compose*.yml' |
    grep -E '(^|/)(docker-)?compose[^/]*\.ya?ml$')" || return
  export DISCOVERY_COMPOSE_FILES
}

setup() {
  discovery_setup
}

teardown() {
  discovery_teardown
}

@test "compose_image_discovery: actual app and migration resolve to the same complete shared pin" {
  run yq --yaml-fix-merge-anchor-to-spec=true -o=json 'explode(.)' \
    "${REPO_ROOT}/services/open-archiver/compose.yaml"
  assert_success
  local document="${output}"
  run jq -e --arg image "${DISCOVERY_IMAGE}" '
        (.["x-app"] | keys) == ["image"] and
        (.services["open-archiver"].image == $image) and
        (.services["open-archiver-migrate"].image == $image) and
        ($image | test("^ghcr.io/devsecninja/truenas-apps/open-archiver:[0-9a-f]{40}@sha256:[0-9a-f]{64}$"))
    ' <<<"${document}"
  assert_success
  assert_output true
}

@test "compose_image_discovery: actual shared pin occurs once as an unquoted standalone image line" {
  local compose="${REPO_ROOT}/services/open-archiver/compose.yaml"
  run grep -F "${DISCOVERY_IMAGE}" "${compose}"
  assert_success
  assert_output "  image: ${DISCOVERY_IMAGE}"
  run grep -A 1 -x 'x-app: &app-image' "${compose}"
  assert_success
  assert_output "x-app: &app-image"$'\n'"  image: ${DISCOVERY_IMAGE}"
  run grep -x '    <<: \*app-image' "${compose}"
  assert_success
  assert_output $'    <<: *app-image\n    <<: *app-image'
  run grep -E '^[[:space:]]*image:[[:space:]]*[&*]' "${compose}"
  assert_failure 1
}

@test "compose_image_discovery: every tracked Compose scanner input equals its YAML-resolved image set" {
  local relative discovered resolved count=0
  [[ -n "${DISCOVERY_COMPOSE_FILES}" ]] || fail "No tracked Compose files found"
  while IFS= read -r relative; do
    assert_file_exists "${REPO_ROOT}/${relative}"
    run discovery_resolved_images "${REPO_ROOT}/${relative}"
    assert_success
    resolved="${output}"
    run discovery_scanner_images "${REPO_ROOT}/${relative}"
    assert_success
    discovered="${output}"
    if [[ "${discovered}" != "${resolved}" ]]; then
      fail "${relative}: monitor input must equal resolved images (no omissions, aliases, anchors, or comment tokens)
scanner: ${discovered}
resolved: ${resolved}"
    fi
    count=$((count + 1))
  done <<<"${DISCOVERY_COMPOSE_FILES}"
  # Do not freeze the current stack count; new tracked templates join the audit.
  [[ "${count}" -gt 0 ]] || fail "Compose audit did not inspect any files"
}

@test "compose_image_discovery: old scalar fixture resolves but feeds anchor and alias tokens to monitors" {
  local fixture="${DISCOVERY_FIXTURES}/scalar.compose" reference
  run discovery_resolved_images "${fixture}"
  assert_success
  reference="${output}"
  run discovery_scanner_images "${fixture}"
  assert_success
  assert_output "&app-image ${reference}"$'\n''*app-image'
  refute_output "${reference}"
  # The discovery-safe standalone literal does not exist in the old layout.
  run grep -E '^[[:space:]]+image:[[:space:]]+ghcr[.]io/' "${fixture}"
  assert_failure 1
}

@test "compose_image_discovery: supported same-line mapping yields one image and unchanged resolved consumers" {
  local resolved
  run discovery_resolved_images "${DISCOVERY_FIXTURES}/scalar.compose"
  assert_success
  resolved="${output}"
  run discovery_resolved_images "${DISCOVERY_FIXTURES}/mapping.compose"
  assert_success
  assert_output "${resolved}"
  run discovery_scanner_images "${DISCOVERY_FIXTURES}/mapping.compose"
  assert_success
  assert_output "${resolved}"
}

@test "gha_trivy_image_scan: shared mapping scans exactly one complete reference and retains its SARIF" {
  discovery_mock_monitors
  run bash "${REPO_ROOT}/scripts/gha-trivy-image-scan.sh"
  assert_success
  assert_output --partial "Scanning ${DISCOVERY_IMAGE}"
  assert_output --partial "Merged 1 SARIF file(s)"
  run get_mock_call_count trivy
  assert_output 1
  run get_mock_call_count mise
  assert_output 1
  local slug="${DISCOVERY_IMAGE//[\/:@]/_}"
  slug="${slug//[^[:alnum:]_-]/}"
  run get_mock_call_args trivy
  assert_output "image --scanners vuln --ignore-unfixed --severity CRITICAL --format sarif --output sarif-tmp/${slug}.sarif ${DISCOVERY_IMAGE}"
  refute_output --partial '&app-image'
  refute_output --partial '*app-image'
  assert_dir_exists "${DISCOVERY_TMPDIR}/sarif-output"
  assert_file_exists "${DISCOVERY_TMPDIR}/sarif-output/trivy-images.sarif"
  run jq -c '[(.runs | length), (.runs[0].results | length), .runs[0].results[0].ruleId]' \
    "${DISCOVERY_TMPDIR}/sarif-output/trivy-images.sarif"
  assert_success
  assert_output '[1,1,"fixture-image"]'
  discovery_assert_no_network_fallback
}

@test "gha_image_age_check: shared mapping checks exactly one bare tag without digest or YAML tokens" {
  discovery_mock_monitors
  run bash "${REPO_ROOT}/scripts/gha-image-age-check.sh"
  assert_success
  assert_output --partial "OK: ${DISCOVERY_BARE} (1 days old)"
  assert_output --partial "All images are within the 90-day threshold"
  run get_mock_call_args crane
  assert_output "config ${DISCOVERY_BARE}"
  refute_output --partial '@sha256:'
  refute_output --partial '&app-image'
  refute_output --partial '*app-image'
  assert_mock_not_called gh.close
  discovery_assert_no_network_fallback
}

@test "gha_image_age_check: resolution finds the shared current image and closes a fresh issue as updated" {
  discovery_mock_monitors
  export DISCOVERY_OPEN_ISSUE=1
  run bash "${REPO_ROOT}/scripts/gha-image-age-check.sh"
  assert_success
  assert_output --partial "${DISCOVERY_BARE} is now 1 days old"
  refute_output --partial 'no longer in any compose file'
  run get_mock_call_args crane
  assert_output "config ${DISCOVERY_BARE}"$'\n'"config ${DISCOVERY_BARE}"
  run get_mock_call_args gh.close
  assert_output "issue close 41 --comment The image \`${DISCOVERY_BARE}\` is no longer stale (1 days old, threshold: 90 days). Closing automatically."
  discovery_assert_no_network_fallback
}

@test "gha_image_age_check: resolution recognizes a still-stale shared image instead of treating it as removed" {
  discovery_mock_monitors
  export DISCOVERY_OPEN_ISSUE=1 DISCOVERY_STALE=1
  run bash "${REPO_ROOT}/scripts/gha-image-age-check.sh"
  assert_success
  assert_output --partial "Still stale, issue already open: [${DISCOVERY_BARE}] Stale image detected"
  assert_output --partial "STILL STALE: ${DISCOVERY_BARE} (400 days old)"
  assert_output --partial 'issue #41 remains open'
  refute_output --partial 'no longer in any compose file'
  run get_mock_call_args crane
  assert_output "config ${DISCOVERY_BARE}"$'\n'"config ${DISCOVERY_BARE}"
  assert_mock_not_called gh.close
  run get_mock_call_args gh
  refute_output --partial 'issue create'
  refute_output --partial 'issue close'
  discovery_assert_no_network_fallback
}
