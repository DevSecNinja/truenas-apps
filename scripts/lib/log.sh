#!/bin/sh
# log - Reusable shell logging library (v2).
#
# Source from POSIX sh / Bash / Zsh, or execute directly. Fish users get an
# auto-generated wrapper from config.fish.
#
# Quick start
# -----------
#   . "${HOME}/.config/shell/functions/log.sh"
#   log_info   "starting"
#   log_state  "Deploying app"          # cyan, info-priority
#   log_result "30 deployed, 0 failed"  # green
#   log_hint   "Re-run to fix"          # magenta
#   log_step   "Pulling images"         # dim
#   log_warn   "fallback used"
#   log_error  "connection failed"
#   log_banner "Phase 1 complete" RESULT
#   log_kv     duration=12s app=adguard status=ok
#   printf '%s\n' "$payload" | log_data INFO config
#
# Severity vs kind
# ----------------
# Severity (levels) controls filtering: TRACE < DEBUG < INFO < NOTICE < WARN
#   < ERROR < FATAL. Set LOG_LEVEL to suppress lines below a threshold.
# Kinds are info-priority categories with distinct colors/labels: STATE,
#   RESULT, HINT, STEP. They render the same priority as INFO in syslog/journal
#   and never affect filtering.
#
# Output
# ------
#   - Human timestamp on TTY: "2026-04-29 20:27:28"
#   - ISO-8601 UTC in LOG_FILE and journald: "2026-04-29T18:27:28Z"
#   - Set LOG_TIMESTAMP to a literal value (test hook) — used verbatim everywhere.
#   - 6-char padded label column: "INFO  ", "WARN  ", "STATE ", "RESULT".
#   - Optional tag in square brackets: "[deploy]". See "Tag" below.
#   - INFO/NOTICE/DEBUG/TRACE/STATE/RESULT/HINT/STEP go to stdout; WARN/ERROR/
#     FATAL go to stderr.
#   - Color is used only when LOG_COLOR=always, or LOG_COLOR=auto with a TTY
#     stdout/stderr and a non-dumb TERM. NO_COLOR disables color globally.
#
# Tag handling
# ------------
# In priority order, the displayed tag is:
#   1. Explicit ${LOG_TAG} (validated against ^[A-Za-z0-9._-]{1,32}$).
#   2. Auto-detected basename of the calling script (no extension), when
#      log.sh is sourced from a real script. Common interactive names
#      ("bash", "zsh", "log", etc.) are filtered out so calling `log_info` from
#      an interactive shell shows no tag.
#   3. Empty (no tag rendered).
#
# Banner styles
# -------------
# LOG_BANNER_STYLE selects the visual style: unicode (default), ascii, heavy,
# box, rule. Multi-byte styles auto-fall-back to ASCII when:
#   - the active output is the LOG_FILE (file output is always single-line),
#   - LANG=C / LC_ALL=C, or
#   - TERM=dumb / no TTY.
#
# Output formats
# --------------
# LOG_FORMAT=text (default) emits the human/iso line above.
# LOG_FORMAT=json emits one JSON object per call with keys:
#   timestamp, level, kind, tag, message, data
# Banners in JSON mode collapse to a single object with kind=BANNER.
#
# Configuration env vars
# ----------------------
#   LOG_LEVEL              minimum severity (default INFO)
#   LOG_TAG                explicit tag override
#   LOG_FORMAT             text | json (default text)
#   LOG_COLOR              auto | always | never  (default auto)
#   LOG_BANNER_STYLE       unicode | ascii | heavy | box | rule (default unicode)
#   LOG_RULE_WIDTH         banner/rule width (default 40, capped at COLUMNS or 80)
#   LOG_MAX_BYTES          per-line byte cap (default 8192)
#   LOG_FILE               optional log file path (requires a rotation policy)
#   LOG_FILE_MAX_BYTES     rotate when file exceeds this size
#   LOG_FILE_TTL_DAYS      delete file when older than N days
#   LOG_JOURNAL            auto | always | never (default auto)
#   LOG_TO_STDIO           1 | 0 (default 1)
#
# Test hooks
# ----------
#   LOG_TIMESTAMP          fixed timestamp, used verbatim everywhere
#   LOG_LOGGER_COMMAND     stub logger executable for journal tests
#   LOG_FORCE_TTY          1 to pretend stdout/stderr are TTYs
#   LOG_FORCE_LANG_C       1 to force ASCII fallback regardless of LANG

LOG_DEFAULT_LEVEL="${LOG_DEFAULT_LEVEL:-INFO}"
_LOG_MAX_BYTES_DEFAULT=8192
_LOG_TAG_PATTERN_BAD='*[!A-Za-z0-9._-]*'

# Capture the invoking script's $0 at source time. In zsh, $0 inside a
# function expands to the function name (when FUNCTION_ARGZERO is set), so we
# must snapshot it now. Bash exposes BASH_SOURCE; zsh exposes ZSH_ARGZERO.
# shellcheck disable=SC3028,SC3054
if [ -n "${ZSH_ARGZERO:-}" ]; then
	_LOG_SCRIPT0="$ZSH_ARGZERO"
elif [ -n "${BASH_SOURCE:-}" ]; then
	_LOG_SCRIPT0="$0"
else
	_LOG_SCRIPT0="$0"
fi

# Pre-computed control-character literals for POSIX-safe matching.
_LOG_NL=$(printf '\nx')
_LOG_NL=${_LOG_NL%x}
_LOG_CR=$(printf '\rx')
_LOG_CR=${_LOG_CR%x}
_LOG_ESC=$(printf '\033x')
_LOG_ESC=${_LOG_ESC%x}
_LOG_BEL=$(printf '\007x')
_LOG_BEL=${_LOG_BEL%x}

# ----------------------------------------------------------------------------
# Level / kind resolution
# ----------------------------------------------------------------------------

# Print "LEVEL KIND LEVEL_NUM" for a user-supplied severity-or-kind string.
_log_resolve() {
	case "$1" in
	trace | TRACE) printf '%s\n' "TRACE TRACE 10" ;;
	debug | DEBUG) printf '%s\n' "DEBUG DEBUG 20" ;;
	info | INFO | "") printf '%s\n' "INFO INFO 30" ;;
	notice | NOTICE) printf '%s\n' "NOTICE NOTICE 35" ;;
	warn | warning | WARN | WARNING) printf '%s\n' "WARN WARN 40" ;;
	error | err | ERROR | ERR) printf '%s\n' "ERROR ERROR 50" ;;
	fatal | crit | critical | FATAL | CRIT | CRITICAL) printf '%s\n' "FATAL FATAL 60" ;;
	state | STATE) printf '%s\n' "INFO STATE 30" ;;
	result | RESULT) printf '%s\n' "INFO RESULT 30" ;;
	hint | HINT) printf '%s\n' "INFO HINT 30" ;;
	step | STEP) printf '%s\n' "INFO STEP 30" ;;
	banner | BANNER) printf '%s\n' "INFO BANNER 30" ;;
	*) return 1 ;;
	esac
}

_log_min_level_num() {
	_lv=$(_log_resolve "${LOG_LEVEL:-${LOG_MIN_LEVEL:-$LOG_DEFAULT_LEVEL}}") || _lv="INFO INFO 30"
	# shellcheck disable=SC2086
	set -- $_lv
	printf '%s' "$3"
}

log_level_enabled() {
	_lv=$(_log_resolve "${1:-INFO}") || _lv="INFO INFO 30"
	# shellcheck disable=SC2086
	set -- $_lv
	test "$3" -ge "$(_log_min_level_num)"
}

log_set_level() {
	_lv=$(_log_resolve "${1:-}") || return 1
	# shellcheck disable=SC2086
	set -- $_lv
	LOG_LEVEL="$1"
	export LOG_LEVEL
}

_log_priority() {
	case "$1" in
	TRACE | DEBUG) printf '%s' "debug" ;;
	NOTICE) printf '%s' "notice" ;;
	WARN) printf '%s' "warning" ;;
	ERROR) printf '%s' "err" ;;
	FATAL) printf '%s' "crit" ;;
	*) printf '%s' "info" ;;
	esac
}

_log_pad_label() {
	# Right-pad to 6 characters.
	_pl="$1"
	_pl_len=${#_pl}
	while [ "$_pl_len" -lt 6 ]; do
		_pl="$_pl "
		_pl_len=$((_pl_len + 1))
	done
	printf '%s' "$_pl"
}

# ----------------------------------------------------------------------------
# Color
# ----------------------------------------------------------------------------

_log_kind_color() {
	case "$1" in
	TRACE) printf '\033[2m' ;;
	DEBUG) printf '\033[2;36m' ;;
	INFO) printf '%s' "" ;;
	NOTICE) printf '\033[1;34m' ;;
	WARN) printf '\033[1;33m' ;;
	ERROR) printf '\033[1;31m' ;;
	FATAL) printf '\033[1;37;41m' ;;
	STATE) printf '\033[36m' ;;
	RESULT) printf '\033[32m' ;;
	HINT) printf '\033[35m' ;;
	STEP) printf '\033[2;37m' ;;
	BANNER) printf '\033[1m' ;;
	*) printf '%s' "" ;;
	esac
}

_log_use_color_for_fd() {
	test -z "${NO_COLOR:-}" || return 1
	case "${LOG_COLOR:-auto}" in
	always | true | 1) return 0 ;;
	never | false | 0) return 1 ;;
	auto | "") ;;
	*) return 1 ;;
	esac

	if [ "${LOG_FORCE_TTY:-0}" = "1" ]; then
		case "${TERM:-}" in
		"" | dumb) return 1 ;;
		*) return 0 ;;
		esac
	fi

	test -t 1 || return 1
	test -t "$1" || return 1
	case "${TERM:-}" in
	"" | dumb) return 1 ;;
	*) return 0 ;;
	esac
}

# ----------------------------------------------------------------------------
# Timestamps
# ----------------------------------------------------------------------------

_log_ts_iso() {
	if [ -n "${LOG_TIMESTAMP:-}" ]; then
		printf '%s' "$LOG_TIMESTAMP"
	elif command -v date >/dev/null 2>&1; then
		date -u '+%Y-%m-%dT%H:%M:%SZ' | tr -d '\n'
	else
		printf '%s' "0000-00-00T00:00:00Z"
	fi
}

_log_ts_human() {
	if [ -n "${LOG_TIMESTAMP:-}" ]; then
		printf '%s' "$LOG_TIMESTAMP"
	elif command -v date >/dev/null 2>&1; then
		date '+%Y-%m-%d %H:%M:%S' | tr -d '\n'
	else
		printf '%s' "0000-00-00 00:00:00"
	fi
}

# ----------------------------------------------------------------------------
# Tag handling
# ----------------------------------------------------------------------------

# Echo the tag if it passes validation; nothing otherwise.
_log_validate_tag() {
	# shellcheck disable=SC2254 # _LOG_TAG_PATTERN_BAD is intentionally an unquoted glob
	case "$1" in
	"") return 0 ;;
	-*) return 0 ;;
	.*) return 0 ;;
	$_LOG_TAG_PATTERN_BAD) return 0 ;;
	esac
	if [ "${#1}" -le 32 ]; then
		printf '%s' "$1"
	fi
}

# Determine the active tag: explicit override, auto-detected script name,
# or empty when called interactively / from the logger script itself.
_log_tag() {
	if [ -n "${LOG_TAG:-}" ]; then
		_log_validate_tag "$LOG_TAG"
		return 0
	fi

	_t="${_LOG_SCRIPT0##*/}"
	case "$_t" in
	*.sh | *.bash | *.zsh | *.ksh) _t="${_t%.*}" ;;
	esac

	case "$_t" in
	"" | log | log.sh | sh | bash | zsh | ksh | dash | fish | -sh | -bash | -zsh | -ksh | -dash) ;;
	*) _log_validate_tag "$_t" ;;
	esac
}

# ----------------------------------------------------------------------------
# Sanitization
# ----------------------------------------------------------------------------

# Returns 0 if the string contains characters that need sanitizing.
_log_needs_sanitize() {
	case "$1" in
	*"$_LOG_NL"* | *"$_LOG_CR"* | *"$_LOG_ESC"* | *"$_LOG_BEL"*) return 0 ;;
	esac
	# Length cap
	if [ "${#1}" -gt "${LOG_MAX_BYTES:-$_LOG_MAX_BYTES_DEFAULT}" ]; then
		return 0
	fi
	return 1
}

# Sanitize message for safe single-line log output:
#   - strip NUL, ESC, BEL
#   - escape CR -> \r, LF -> \n (literal two-char sequences)
#   - cap to LOG_MAX_BYTES
_log_sanitize() {
	if ! _log_needs_sanitize "$1"; then
		printf '%s' "$1"
		return 0
	fi
	_max="${LOG_MAX_BYTES:-$_LOG_MAX_BYTES_DEFAULT}"
	printf '%s' "$1" | LC_ALL=C awk -v max="$_max" '
		BEGIN { ORS=""; out = "" }
		{
			s = $0
			gsub(/[\000\033\007]/, "", s)
			gsub(/\r/, "\\r", s)
			out = (NR == 1 ? s : out "\\n" s)
		}
		END {
			if (length(out) > max) {
				out = substr(out, 1, max) " ...[truncated]"
			}
			print out
		}
	'
}

# ----------------------------------------------------------------------------
# Banner / rule rendering
# ----------------------------------------------------------------------------

_log_effective_banner_style() {
	_st="${LOG_BANNER_STYLE:-unicode}"
	# JSON mode always uses ASCII (banners are single objects anyway).
	if [ "${LOG_FORMAT:-text}" = "json" ]; then
		_st="ascii"
	fi

	# Multi-byte styles need a real TTY and a UTF-8 locale.
	case "$_st" in
	unicode | box | rule)
		if [ "${LOG_FORCE_LANG_C:-0}" = "1" ]; then
			_st="ascii"
		fi
		case "${LC_ALL:-${LANG:-}}" in
		C | POSIX) _st="ascii" ;;
		esac
		case "${TERM:-}" in
		dumb) _st="ascii" ;;
		esac
		# Headless / file-only invocations get ASCII so log files stay
		# grep- and editor-friendly.
		if [ "${LOG_FORCE_TTY:-0}" != "1" ] && ! { [ -t 1 ] && [ -t 2 ]; }; then
			_st="ascii"
		fi
		;;
	esac
	printf '%s' "$_st"
}

_log_banner_width() {
	_w="${LOG_RULE_WIDTH:-40}"
	_max="${COLUMNS:-80}"
	if [ "$_w" -gt "$_max" ] 2>/dev/null; then
		_w="$_max"
	fi
	printf '%s' "$_w"
}

# Build a separator line of the given width using the specified style char.
_log_repeat_char() {
	# $1 = char, $2 = count
	_rc=""
	_i=0
	while [ "$_i" -lt "$2" ]; do
		_rc="$_rc$1"
		_i=$((_i + 1))
	done
	printf '%s' "$_rc"
}

# ----------------------------------------------------------------------------
# Emit (low-level write) functions
# ----------------------------------------------------------------------------

_log_stdio_fd() {
	case "$1" in
	WARN | ERROR | FATAL) printf '%s' "2" ;;
	*) printf '%s' "1" ;;
	esac
}

_log_journal_available() {
	case "${LOG_JOURNAL:-auto}" in
	never | false | 0) return 1 ;;
	esac

	_log_logger_command="${LOG_LOGGER_COMMAND:-logger}"
	command -v "$_log_logger_command" >/dev/null 2>&1 || return 1

	case "${LOG_JOURNAL:-auto}" in
	always | true | 1) return 0 ;;
	esac

	test -S /run/systemd/journal/socket ||
		test -S /dev/log ||
		test -S /var/run/syslog ||
		test -S /var/run/log ||
		test -n "${JOURNAL_STREAM:-}" ||
		test -n "${INVOCATION_ID:-}"
}

_log_write_journal() {
	# $1=level, $2=kind, $3=tag, $4=sanitized message
	_log_journal_available || return 0

	_lj_cmd="${LOG_LOGGER_COMMAND:-logger}"
	_lj_tag="${3:-shell-log}"
	# Validate tag again to be safe (logger -t accepts arbitrary; keep us safe)
	# shellcheck disable=SC2254 # _LOG_TAG_PATTERN_BAD is intentionally an unquoted glob
	case "$_lj_tag" in
	$_LOG_TAG_PATTERN_BAD) _lj_tag="shell-log" ;;
	esac
	_lj_pri=$(_log_priority "$1")
	if [ "$2" = "$1" ]; then
		_lj_msg="$1 $4"
	else
		_lj_msg="$1 $2 $4"
	fi

	"$_lj_cmd" -t "$_lj_tag" -p "user.$_lj_pri" -- "$_lj_msg" >/dev/null 2>&1 ||
		"$_lj_cmd" -t "$_lj_tag" -p "user.$_lj_pri" "$_lj_msg" >/dev/null 2>&1 ||
		:
}

_log_file_enabled() {
	test -n "${LOG_FILE:-}" || return 1
	test -n "${LOG_FILE_MAX_BYTES:-}" || test -n "${LOG_FILE_TTL_DAYS:-}"
}

_log_prepare_file() {
	_log_file_enabled || return 1

	_log_file_dir=$(dirname "$LOG_FILE" 2>/dev/null) || return 1
	test -d "$_log_file_dir" || mkdir -p "$_log_file_dir" 2>/dev/null || return 1

	# Refuse to write through a symlink (simple traversal guard).
	if [ -L "$LOG_FILE" ]; then
		return 1
	fi

	if [ -n "${LOG_FILE_TTL_DAYS:-}" ] && [ -f "$LOG_FILE" ] && command -v find >/dev/null 2>&1; then
		find "$LOG_FILE" -type f -mtime +"$LOG_FILE_TTL_DAYS" -exec rm -f {} \; 2>/dev/null || :
	fi

	if [ -n "${LOG_FILE_MAX_BYTES:-}" ] && [ -f "$LOG_FILE" ] && command -v wc >/dev/null 2>&1; then
		_log_file_size=$(wc -c <"$LOG_FILE" 2>/dev/null | tr -d ' ')
		case "$_log_file_size:$LOG_FILE_MAX_BYTES" in
		*[!0123456789:]* | :* | *:) return 0 ;;
		esac
		if [ "$_log_file_size" -ge "$LOG_FILE_MAX_BYTES" ] 2>/dev/null; then
			mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null || :
		fi
	fi
}

_log_write_file_line() {
	_log_prepare_file || return 0
	printf '%s\n' "$1" >>"$LOG_FILE" 2>/dev/null || :
}

_log_write_stdio_line() {
	# $1=level, $2=kind, $3=line (no newline)
	test "${LOG_TO_STDIO:-1}" = "0" && return 0

	_ws_fd=$(_log_stdio_fd "$1")

	if _log_use_color_for_fd "$_ws_fd"; then
		_ws_reset=$(printf '\033[0m')
		_ws_color=$(_log_kind_color "$2")
		if [ "$_ws_fd" = "2" ]; then
			printf '%s%s%s\n' "$_ws_color" "$3" "$_ws_reset" >&2
		else
			printf '%s%s%s\n' "$_ws_color" "$3" "$_ws_reset"
		fi
	else
		if [ "$_ws_fd" = "2" ]; then
			printf '%s\n' "$3" >&2
		else
			printf '%s\n' "$3"
		fi
	fi
}

# ----------------------------------------------------------------------------
# Line formatters
# ----------------------------------------------------------------------------

_log_format_text() {
	# $1=ts $2=label $3=tag $4=message
	_lf_label=$(_log_pad_label "$2")
	if [ -n "$3" ]; then
		printf '%s %s [%s] %s' "$1" "$_lf_label" "$3" "$4"
	else
		printf '%s %s %s' "$1" "$_lf_label" "$4"
	fi
}

# JSON-escape a single string (printed without surrounding quotes).
_log_json_escape() {
	# In awk, the replacement string interprets backslashes specially:
	# "\\" in source = "\" in replacement. To emit two backslashes we need
	# four backslashes in the replacement source.
	printf '%s' "$1" | LC_ALL=C awk '
		BEGIN { ORS=""; out = "" }
		{
			s = $0
			gsub(/\\/, "\\\\\\\\", s)
			gsub(/"/, "\\\"", s)
			gsub(/\t/, "\\\\t", s)
			gsub(/\r/, "\\\\r", s)
			gsub(/\b/, "\\\\b", s)
			gsub(/\f/, "\\\\f", s)
			gsub(/[\000-\037]/, "", s)
			out = (NR == 1 ? s : out "\\\\n" s)
		}
		END { print out }
	'
}

_log_format_json() {
	# $1=ts_iso $2=level $3=kind $4=tag $5=message $6=data(or empty)
	_jt=$(_log_json_escape "$1")
	_jl=$(_log_json_escape "$2")
	_jk=$(_log_json_escape "$3")
	_jg=$(_log_json_escape "$4")
	_jm=$(_log_json_escape "$5")
	if [ -n "${6:-}" ]; then
		_jd=$(_log_json_escape "$6")
		printf '{"timestamp":"%s","level":"%s","kind":"%s","tag":"%s","message":"%s","data":"%s"}' \
			"$_jt" "$_jl" "$_jk" "$_jg" "$_jm" "$_jd"
	else
		printf '{"timestamp":"%s","level":"%s","kind":"%s","tag":"%s","message":"%s"}' \
			"$_jt" "$_jl" "$_jk" "$_jg" "$_jm"
	fi
}

# ----------------------------------------------------------------------------
# Public: low-level emit
# ----------------------------------------------------------------------------

# Emit one log entry with explicit level, kind, message.
_log_emit() {
	# $1=LEVEL $2=KIND $3=message $4=optional data payload
	_e_level="$1"
	_e_kind="$2"
	_e_msg="$3"
	_e_data="${4:-}"

	log_level_enabled "$_e_level" || return 0

	_e_msg=$(_log_sanitize "$_e_msg")
	test -n "$_e_msg" || _e_msg="-"
	if [ -n "$_e_data" ]; then
		_e_data=$(_log_sanitize "$_e_data")
	fi

	_e_tag=$(_log_tag)
	_e_ts_human=$(_log_ts_human)
	_e_ts_iso=$(_log_ts_iso)

	if [ "${LOG_FORMAT:-text}" = "json" ]; then
		_e_line=$(_log_format_json "$_e_ts_iso" "$_e_level" "$_e_kind" "$_e_tag" "$_e_msg" "$_e_data")
		_log_write_stdio_line "$_e_level" "$_e_kind" "$_e_line"
		_log_write_file_line "$_e_line"
	else
		_e_stdio_line=$(_log_format_text "$_e_ts_human" "$_e_kind" "$_e_tag" "$_e_msg")
		_e_file_line=$(_log_format_text "$_e_ts_iso" "$_e_kind" "$_e_tag" "$_e_msg")
		_log_write_stdio_line "$_e_level" "$_e_kind" "$_e_stdio_line"
		_log_write_file_line "$_e_file_line"

		if [ -n "$_e_data" ]; then
			# Iterate lines of the data (already sanitized to the literal
			# two-char `\n` sequence) and emit each as a continuation entry.
			_rest="$_e_data"
			while [ -n "$_rest" ]; do
				case "$_rest" in
				*'\n'*)
					_seg="${_rest%%\\n*}"
					_rest="${_rest#*\\n}"
					;;
				*)
					_seg="$_rest"
					_rest=""
					;;
				esac
				_e_stdio_cont=$(_log_format_text "$_e_ts_human" "$_e_kind" "$_e_tag" "│ $_seg")
				_e_file_cont=$(_log_format_text "$_e_ts_iso" "$_e_kind" "$_e_tag" "| $_seg")
				_log_write_stdio_line "$_e_level" "$_e_kind" "$_e_stdio_cont"
				_log_write_file_line "$_e_file_cont"
			done
		fi
	fi

	# Journal entry uses the original sanitized message and (optionally) data
	if [ -n "$_e_data" ]; then
		_log_write_journal "$_e_level" "$_e_kind" "$_e_tag" "$_e_msg | $_e_data"
	else
		_log_write_journal "$_e_level" "$_e_kind" "$_e_tag" "$_e_msg"
	fi
}

# ----------------------------------------------------------------------------
# Public: log() and helpers
# ----------------------------------------------------------------------------

log() {
	_lr=$(_log_resolve "${1:-}") && shift || _lr="INFO INFO 30"
	# shellcheck disable=SC2086
	set -- $_lr "$@"
	# args are now: LEVEL KIND NUM message...
	_g_level="$1"
	_g_kind="$2"
	shift 3
	_log_emit "$_g_level" "$_g_kind" "$*"
}

log_trace() { _log_emit TRACE TRACE "$*"; }
log_debug() { _log_emit DEBUG DEBUG "$*"; }
log_info() { _log_emit INFO INFO "$*"; }
log_notice() { _log_emit NOTICE NOTICE "$*"; }
log_warn() { _log_emit WARN WARN "$*"; }
log_error() { _log_emit ERROR ERROR "$*"; }
log_fatal() { _log_emit FATAL FATAL "$*"; }

log_state() { _log_emit INFO STATE "$*"; }
log_result() { _log_emit INFO RESULT "$*"; }
log_hint() { _log_emit INFO HINT "$*"; }
log_step() { _log_emit INFO STEP "$*"; }

# ----------------------------------------------------------------------------
# Public: log_kv (logfmt)
# ----------------------------------------------------------------------------

log_kv() {
	# Each argument is a key=value pair. Quote values with whitespace or "=".
	_kv_msg=""
	for _kv_pair in "$@"; do
		case "$_kv_pair" in
		*=*)
			_kv_k="${_kv_pair%%=*}"
			_kv_v="${_kv_pair#*=}"
			case "$_kv_v" in
			*' '* | *"$_LOG_NL"* | *'"'*)
				# Escape inner backslashes and quotes
				_kv_v_escaped=$(printf '%s' "$_kv_v" | sed 's/\\/\\\\/g; s/"/\\"/g')
				_kv_msg="$_kv_msg $_kv_k=\"$_kv_v_escaped\""
				;;
			*)
				_kv_msg="$_kv_msg $_kv_k=$_kv_v"
				;;
			esac
			;;
		*)
			_kv_msg="$_kv_msg $_kv_pair"
			;;
		esac
	done
	# Strip leading space
	_kv_msg="${_kv_msg# }"
	_log_emit INFO INFO "$_kv_msg"
}

# ----------------------------------------------------------------------------
# Public: log_data (read payload from stdin)
# ----------------------------------------------------------------------------

log_data() {
	# log_data <KIND> <message...>
	# Reads the payload from stdin.
	_ld_first="${1:-INFO}"
	shift 2>/dev/null || :
	_ld_msg="$*"
	test -n "$_ld_msg" || _ld_msg="data"

	_ld_resolved=$(_log_resolve "$_ld_first") || _ld_resolved="INFO INFO 30"
	# shellcheck disable=SC2086
	set -- $_ld_resolved
	_ld_level="$1"
	_ld_kind="$2"

	# Read all of stdin
	_ld_payload=$(cat)
	_log_emit "$_ld_level" "$_ld_kind" "$_ld_msg" "$_ld_payload"
}

# ----------------------------------------------------------------------------
# Public: banners & rules
# ----------------------------------------------------------------------------

log_sep() {
	_b_kind="${1:-INFO}"
	_b_resolved=$(_log_resolve "$_b_kind") || _b_resolved="INFO INFO 30"
	# shellcheck disable=SC2086
	set -- $_b_resolved
	_b_level="$1"
	_b_kind="$2"
	log_level_enabled "$_b_level" || return 0

	_b_style=$(_log_effective_banner_style)
	_b_width=$(_log_banner_width)

	case "$_b_style" in
	ascii) _b_char="${LOG_RULE_CHAR:-=}" ;;
	heavy) _b_char="${LOG_RULE_CHAR:-#}" ;;
	unicode) _b_char="${LOG_RULE_CHAR:-━}" ;;
	rule) _b_char="${LOG_RULE_CHAR:-─}" ;;
	box) _b_char="${LOG_RULE_CHAR:-─}" ;;
	*) _b_char="=" ;;
	esac

	_b_line=$(_log_repeat_char "$_b_char" "$_b_width")
	_log_emit "$_b_level" "$_b_kind" "$_b_line"
}

log_rule() {
	# log_rule [KIND] <title>
	_r_kind_arg="${1:-INFO}"
	_r_resolved=$(_log_resolve "$_r_kind_arg") || _r_resolved=""
	if [ -n "$_r_resolved" ]; then
		shift
	else
		_r_resolved="INFO INFO 30"
	fi
	# shellcheck disable=SC2086
	set -- $_r_resolved "$@"
	_r_level="$1"
	_r_kind="$2"
	shift 3
	_r_title="$*"
	log_level_enabled "$_r_level" || return 0

	_r_style=$(_log_effective_banner_style)
	_r_width=$(_log_banner_width)

	case "$_r_style" in
	ascii) _r_char="${LOG_RULE_CHAR:-=}" ;;
	heavy) _r_char="${LOG_RULE_CHAR:-#}" ;;
	unicode) _r_char="${LOG_RULE_CHAR:-━}" ;;
	*) _r_char="${LOG_RULE_CHAR:-─}" ;;
	esac

	# Format: ──── title ──────
	_r_prefix=$(_log_repeat_char "$_r_char" 4)
	_r_used=$((4 + 1 + ${#_r_title} + 1))
	_r_remain=$((_r_width - _r_used))
	if [ "$_r_remain" -lt 0 ]; then _r_remain=0; fi
	_r_suffix=$(_log_repeat_char "$_r_char" "$_r_remain")
	_r_line="$_r_prefix $_r_title $_r_suffix"
	_log_emit "$_r_level" "$_r_kind" "$_r_line"
}

log_banner() {
	# log_banner <title> [KIND]
	_bn_title="${1:-}"
	_bn_kind_arg="${2:-STATE}"
	_bn_resolved=$(_log_resolve "$_bn_kind_arg") || _bn_resolved="INFO STATE 30"
	# shellcheck disable=SC2086
	set -- $_bn_resolved
	_bn_level="$1"
	_bn_kind="$2"
	log_level_enabled "$_bn_level" || return 0

	_bn_style=$(_log_effective_banner_style)
	_bn_width=$(_log_banner_width)

	if [ "${LOG_FORMAT:-text}" = "json" ]; then
		# Single JSON line for banners.
		_log_emit "$_bn_level" BANNER "$_bn_title"
		return 0
	fi

	if [ "$_bn_style" = "box" ]; then
		_bn_inner=$((_bn_width - 2))
		if [ "$_bn_inner" -lt 4 ]; then _bn_inner=4; fi
		_bn_top_mid=$(_log_repeat_char "─" "$_bn_inner")
		_bn_top="┌${_bn_top_mid}┐"
		_bn_bot="└${_bn_top_mid}┘"

		# Pad title to inner width minus 2 (one space each side)
		_bn_pad_target=$((_bn_inner - 2))
		_bn_t="$_bn_title"
		_bn_t_len=${#_bn_t}
		while [ "$_bn_t_len" -lt "$_bn_pad_target" ]; do
			_bn_t="$_bn_t "
			_bn_t_len=$((_bn_t_len + 1))
		done
		_bn_mid="│ $_bn_t │"

		_log_emit "$_bn_level" "$_bn_kind" "$_bn_top"
		_log_emit "$_bn_level" "$_bn_kind" "$_bn_mid"
		_log_emit "$_bn_level" "$_bn_kind" "$_bn_bot"
	else
		log_sep "$_bn_kind_arg"
		_log_emit "$_bn_level" "$_bn_kind" " $_bn_title"
		log_sep "$_bn_kind_arg"
	fi
}

# ----------------------------------------------------------------------------
# Sourced detection + standalone entry point
# ----------------------------------------------------------------------------

_log_is_sourced() {
	if [ -n "${ZSH_EVAL_CONTEXT:-}" ]; then
		case "$ZSH_EVAL_CONTEXT" in
		*:file:*) return 0 ;;
		*:file) return 0 ;;
		esac
	fi

	# shellcheck disable=SC3028
	if [ -n "${BASH_VERSION:-}" ] && [ -n "${BASH_SOURCE:-}" ]; then
		test "${BASH_SOURCE:-$0}" != "$0"
		return
	fi

	return 1
}

if ! _log_is_sourced && [ "${0##*/}" = "log.sh" ]; then
	log "$@"
fi
