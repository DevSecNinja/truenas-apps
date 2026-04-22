#!/usr/bin/env bash
# Mock / stub helpers for BATS tests.
#
# create_mock writes a stub executable that records each invocation's argv
# to "${MOCK_LOG}/<cmd>.calls" (one line per call) and either prints a fixed
# string or cats a stdout fixture. Using a separate stdout fixture file is
# deliberate: embedding arbitrary strings in the stub source would break as
# soon as the desired output contained quotes, backticks, `$`, or newlines.
#
# Variables expected in the caller shell:
#   MOCK_BIN  directory for stubs (already on PATH)
#   MOCK_LOG  directory for call logs
#
# Public functions:
#   create_mock <cmd> [exit_code] [stdout]
#   create_mock_stdout <cmd> <stdout>
#   create_mock_passthrough <cmd>              — runs the real binary
#   create_mock_script <cmd> <body>            — arbitrary shell body
#   mock_called <cmd>                          — returns 0 if ever called
#   mock_call_count <cmd>                      — prints number of calls
#   mock_calls <cmd>                           — prints all call argv lines
#   mock_last_call <cmd>                       — prints last call argv line

create_mock() {
    local cmd="$1"
    local exit_code="${2:-0}"
    local stdout="${3:-}"

    local stdout_file="${MOCK_BIN}/${cmd}.stdout"
    # Use printf %s with no trailing newline so callers can control framing.
    printf '%s' "${stdout}" >"${stdout_file}"

    cat >"${MOCK_BIN}/${cmd}" <<MOCK_SCRIPT
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${MOCK_LOG}/${cmd}.calls"
if [ -s "${stdout_file}" ]; then
    cat "${stdout_file}"
fi
exit ${exit_code}
MOCK_SCRIPT
    chmod +x "${MOCK_BIN}/${cmd}"
}

create_mock_stdout() {
    local cmd="$1"
    local stdout="$2"
    create_mock "${cmd}" 0 "${stdout}"
}

create_mock_passthrough() {
    local cmd="$1"
    local real
    # Resolve real binary from the ORIGINAL PATH (ours has MOCK_BIN prepended).
    real="$(PATH="${ORIG_PATH:-/usr/local/bin:/usr/bin:/bin}" command -v "${cmd}")"
    if [ -z "${real}" ]; then
        create_mock "${cmd}" 127 ""
        return
    fi
    cat >"${MOCK_BIN}/${cmd}" <<MOCK_SCRIPT
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${MOCK_LOG}/${cmd}.calls"
exec "${real}" "\$@"
MOCK_SCRIPT
    chmod +x "${MOCK_BIN}/${cmd}"
}

# Arbitrary mock body — $body must be a valid bash snippet.
# Automatically logs invocation to MOCK_LOG/<cmd>.calls.
create_mock_script() {
    local cmd="$1"
    local body="$2"
    {
        echo '#!/usr/bin/env bash'
        echo "printf '%s\\n' \"\$*\" >> \"${MOCK_LOG}/${cmd}.calls\""
        echo "${body}"
    } >"${MOCK_BIN}/${cmd}"
    chmod +x "${MOCK_BIN}/${cmd}"
}

mock_called() {
    [ -s "${MOCK_LOG}/$1.calls" ]
}

mock_call_count() {
    if [ -f "${MOCK_LOG}/$1.calls" ]; then
        wc -l <"${MOCK_LOG}/$1.calls" | tr -d ' '
    else
        echo 0
    fi
}

mock_calls() {
    cat "${MOCK_LOG}/$1.calls" 2>/dev/null || true
}

mock_last_call() {
    tail -n1 "${MOCK_LOG}/$1.calls" 2>/dev/null || true
}
