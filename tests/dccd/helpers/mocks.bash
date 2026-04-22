#!/usr/bin/env bash
# Mock generators for dccd.sh tests.
# Load in each .bats file: load '../helpers/mocks'

# Create a simple mock command that logs its args and returns a fixed exit code/output.
# Usage: create_mock <command> [exit_code] [stdout]
create_mock() {
    local cmd="$1" exit_code="${2:-0}" stdout="${3:-}"
    cat >"${MOCK_BIN}/${cmd}" <<MOCK
#!/bin/bash
echo "\$@" >> "${MOCK_LOG}/${cmd}.calls"
echo "${stdout}"
exit ${exit_code}
MOCK
    chmod +x "${MOCK_BIN}/${cmd}"
}

# Create a mock that returns different outputs on sequential calls.
# Usage: create_sequential_mock <command> <exit1:out1> <exit2:out2> ...
create_sequential_mock() {
    local cmd="$1"
    shift
    local -a responses=("$@")

    # Write responses to a file
    local resp_file="${MOCK_LOG}/${cmd}.responses"
    printf '%s\n' "${responses[@]}" >"${resp_file}"

    cat >"${MOCK_BIN}/${cmd}" <<MOCK
#!/bin/bash
echo "\$@" >> "${MOCK_LOG}/${cmd}.calls"
COUNTER_FILE="${MOCK_LOG}/${cmd}.counter"
RESP_FILE="${resp_file}"
count=0
if [ -f "\${COUNTER_FILE}" ]; then
    count=\$(cat "\${COUNTER_FILE}")
fi
echo \$((count + 1)) > "\${COUNTER_FILE}"
line=\$(sed -n "\$((count + 1))p" "\${RESP_FILE}")
exit_code=\${line%%:*}
output=\${line#*:}
echo "\${output}"
exit "\${exit_code}"
MOCK
    chmod +x "${MOCK_BIN}/${cmd}"
}

# Assert a mock was called at least once.
assert_mock_called() {
    local cmd="$1"
    assert_file_exists "${MOCK_LOG}/${cmd}.calls"
}

# Assert a mock was NOT called.
assert_mock_not_called() {
    local cmd="$1"
    if [ -f "${MOCK_LOG}/${cmd}.calls" ]; then
        fail "Expected '${cmd}' not to be called, but it was:$(cat "${MOCK_LOG}/${cmd}.calls")"
    fi
}

# Assert a mock was called with specific arguments (partial match).
assert_mock_called_with() {
    local cmd="$1" expected="$2"
    assert_file_exists "${MOCK_LOG}/${cmd}.calls"
    run grep -F "${expected}" "${MOCK_LOG}/${cmd}.calls"
    assert_success
}

# Get the number of times a mock was called.
get_mock_call_count() {
    local cmd="$1"
    if [ -f "${MOCK_LOG}/${cmd}.calls" ]; then
        wc -l <"${MOCK_LOG}/${cmd}.calls"
    else
        echo 0
    fi
}

# Get all recorded call args for a mock.
get_mock_call_args() {
    local cmd="$1"
    cat "${MOCK_LOG}/${cmd}.calls" 2>/dev/null || true
}

# Create default mocks for common external commands.
create_default_mocks() {
    create_mock "docker" 0 ""
    create_mock "git" 0 ""
    create_mock "curl" 0 ""
    create_mock "dig" 0 ""
    create_mock "sops" 0 ""
    create_mock "sudo" 0 ""
    create_mock "yq" 0 ""
}
