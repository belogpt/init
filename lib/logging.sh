#!/usr/bin/env bash
: "${INIT_NO_COLOR:=0}"; : "${INIT_DEBUG:=0}"; : "${OUTPUT_FORMAT:=text}"
logging_init() {
  if [ "${OUTPUT_FORMAT:-text}" = json ] || [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ] || [ "${INIT_NO_COLOR}" = 1 ]; then
    COLOR_RESET=""; COLOR_BOLD=""; COLOR_RED=""; COLOR_GREEN=""; COLOR_YELLOW=""; COLOR_BLUE=""; COLOR_GRAY=""
  else
    COLOR_RESET=$'\033[0m'; COLOR_BOLD=$'\033[1m'; COLOR_RED=$'\033[31m'; COLOR_GREEN=$'\033[32m'; COLOR_YELLOW=$'\033[33m'; COLOR_BLUE=$'\033[34m'; COLOR_GRAY=$'\033[90m'
  fi
}
_log_line() { local color="$1" level="$2" message="$3" out=1; [ "${OUTPUT_FORMAT:-text}" = json ] && out=2; printf '%s%s%s %s\n' "${color}" "${level}" "${COLOR_RESET}" "${message}" >&"$out"; }
log_info() { _log_line "${COLOR_BLUE}" INFO "$*"; }
log_warn() { _log_line "${COLOR_YELLOW}" WARN "$*"; }
log_error() { _log_line "${COLOR_RED}" ERROR "$*" >&2; }
log_success() { _log_line "${COLOR_GREEN}" OK "$*"; }
log_debug() { [ "${INIT_DEBUG}" = 1 ] && _log_line "${COLOR_GRAY}" DEBUG "$*" || true; }
