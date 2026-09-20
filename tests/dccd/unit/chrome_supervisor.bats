#!/usr/bin/env bats

load '../helpers/chrome_supervisor'

setup_file() {
  chrome_supervisor_setup_file || return
  if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
    printf '%s\n' 'Chrome supervisor requires Bash with wait -n support (4.3+)' >&2
    return 1
  fi
}

setup() {
  chrome_supervisor_setup
  export SUPERVISOR_SCRIPT="${REPO_ROOT}/services/karakeep/config/chrome-supervisor.sh"
  DRIVER="${REPO_ROOT}/tests/dccd/fixtures/supervisor/drive.bash"
  local fixture="${REPO_ROOT}/tests/dccd/fixtures/supervisor/child.bash"
  cp "${fixture}" "${MOCK_BIN}/socat"
  cp "${fixture}" "${MOCK_BIN}/browser executable"
  chmod +x "${MOCK_BIN}/socat" "${MOCK_BIN}/browser executable"
}

teardown() {
  chrome_supervisor_teardown
}

assert_children_stopped() {
  assert_line 'children-stopped'
  assert_line 'unrelated-browser-alive'
  refute_stderr --partial 'HARNESS FAILURE'
}

assert_argv_file() {
  local file="$1" actual
  shift
  local -a args=()
  while IFS= read -r -d '' actual; do
    args+=("${actual}")
  done <"${file}"
  assert_equal "${#args[@]}" "$#" || return
  local i=0 expected
  for expected in "$@"; do
    assert_equal "${args[i]}" "${expected}" || return
    i=$((i + 1))
  done
}

@test "chrome_supervisor: socat failure exits one and terminates browser sibling" {
  run --separate-stderr bash "${DRIVER}" socat:23
  assert_failure 1
  assert_line 'supervisor-status=1'
  assert_stderr --partial 'exited unexpectedly (status 23)'
  assert_children_stopped
  assert_file_exists "${TEST_TMPDIR}/browser.terminated"
}

@test "chrome_supervisor: browser failure exits one and terminates socat sibling" {
  run --separate-stderr bash "${DRIVER}" browser:42
  assert_failure 1
  assert_stderr --partial 'exited unexpectedly (status 42)'
  assert_children_stopped
  assert_file_exists "${TEST_TMPDIR}/socat.terminated"
}

@test "chrome_supervisor: clean socat exit is still failure for on-failure restart" {
  run --separate-stderr bash "${DRIVER}" socat:0
  assert_failure 1
  assert_stderr --partial 'exited unexpectedly (status 0)'
  assert_children_stopped
}

@test "chrome_supervisor: clean browser exit is still failure for on-failure restart" {
  run --separate-stderr bash "${DRIVER}" browser:0
  assert_failure 1
  assert_stderr --partial 'exited unexpectedly (status 0)'
  assert_children_stopped
}

@test "chrome_supervisor: TERM is a successful intentional stop with neither child left running" {
  run --separate-stderr bash "${DRIVER}" term
  assert_success
  assert_line 'supervisor-status=0'
  assert_stderr ''
  assert_children_stopped
  assert_file_exists "${TEST_TMPDIR}/socat.terminated"
  assert_file_exists "${TEST_TMPDIR}/browser.terminated"
}

@test "chrome_supervisor: INT is a successful intentional stop and sends TERM to both children" {
  run --separate-stderr bash "${DRIVER}" int
  assert_success
  assert_line 'supervisor-status=0'
  assert_stderr ''
  assert_children_stopped
  assert_file_exists "${TEST_TMPDIR}/socat.terminated"
  assert_file_exists "${TEST_TMPDIR}/browser.terminated"
}

@test "chrome_supervisor: no browser command fails before launching either child" {
  run --separate-stderr bash "${DRIVER}" missing-args
  assert_failure 1
  assert_stderr --partial 'requires a browser command'
  assert_children_stopped
  assert_file_not_exists "${TEST_TMPDIR}/socat.pid"
  assert_file_not_exists "${TEST_TMPDIR}/browser.pid"
}

@test "chrome_supervisor: missing socat fails and does not strand the browser" {
  run --separate-stderr bash "${DRIVER}" missing-socat
  assert_failure 1
  assert_stderr --partial 'socat: command not found'
  assert_stderr --partial 'exited unexpectedly (status 127)'
  assert_children_stopped
}

@test "chrome_supervisor: missing browser executable fails and does not strand socat" {
  run --separate-stderr bash "${DRIVER}" missing-browser
  assert_failure 1
  assert_stderr --partial 'nonexistent-browser: No such file or directory'
  assert_stderr --partial 'exited unexpectedly (status 127)'
  assert_children_stopped
}

@test "chrome_supervisor: browser argv is literal and socat uses IPv4 fork and reuseaddr" {
  local literal="\$(touch ${TEST_TMPDIR}/injected)"
  run --separate-stderr bash "${DRIVER}" term \
    --no-sandbox '--window-size=1440,900' 'two words' '' '*.html' "${literal}" $'line\nbreak'
  assert_success
  assert_children_stopped
  assert_file_exists "${TEST_TMPDIR}/browser.argv"
  assert_argv_file "${TEST_TMPDIR}/browser.argv" \
    --no-sandbox '--window-size=1440,900' 'two words' '' '*.html' "${literal}" $'line\nbreak'
  assert_argv_file "${TEST_TMPDIR}/socat.argv" \
    TCP4-LISTEN:9222,fork,reuseaddr TCP4:127.0.0.1:9223
  assert_file_not_exists "${TEST_TMPDIR}/injected"
}
