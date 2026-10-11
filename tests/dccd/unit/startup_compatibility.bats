#!/usr/bin/env bats
# Run the existing Node source-policy framework through the all-PR BATS job,
# including changes to Karakeep/Dawarich/Renovate outside the image workflow.
# No Docker daemon, network, secrets or additional libraries.
# The existing wrapper suite cleans up its own temporary mock executables.

load '../helpers/diagnostics'

setup_file() {
  diagnostics_require_helpers || return
  command -v node || return 1
}

setup() {
  # Loading common.bash sets REPO_ROOT relative to that helper's BASH_SOURCE;
  # common_setup is unnecessary and would add mocks/source production dccd.
  load '../helpers/common'
  assert_file_exists "${REPO_ROOT}/tests/open-archiver/compatibility.test.mjs" || return
  assert_file_exists "${REPO_ROOT}/tests/open-archiver/backup.test.mjs"
}

@test "startup_compatibility: Meilisearch migration and backup v4 source-policy regressions" {
  run node --test --test-reporter=tap \
    "${REPO_ROOT}/tests/open-archiver/compatibility.test.mjs" \
    "${REPO_ROOT}/tests/open-archiver/backup.test.mjs"

  assert_success
  assert_output --partial "# fail 0"
  assert_output --partial "# skipped 0"
}
