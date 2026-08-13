#!/usr/bin/env bash

init_error_trap() {
  local exit_code="$?" line_no="${1:-unknown}" command="${2:-unknown}" file="${BASH_SOURCE[1]:-${0}}"
  log_error "Command failed: file=${file} line=${line_no} command=${command} exit=${exit_code}"
  exit "${exit_code}"
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

run_root() { if [ "${EUID:-$(id -u)}" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

apt_assume_yes() {
  [ "${ASSUME_YES:-0}" = "1" ] && return 0
  local fn
  for fn in "${FUNCNAME[@]:1}"; do [ "$fn" = menu_run_apply ] && return 0; done
  return 1
}

run_apt_install() { local yes_args=(); apt_assume_yes && yes_args=(-y); run_root apt "${yes_args[@]}" install "$@"; }

is_deb_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }

module_status_text() { case "$1" in 0) printf configured;; 1) printf 'needs changes';; 3) printf blocked;; *) printf 'check failed';; esac; }

status_slug() { printf '%s' "$1" | tr ' ' '_'; }

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}; s=${s//"/\\"}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

print_json_string_array() {
  local first=1 item
  printf '['
  for item in "$@"; do [ "$first" -eq 1 ] || printf ','; first=0; printf '"%s"' "$(json_escape "$item")"; done
  printf ']'
}

plan_line() {
  local symbol="$1" msg="$2" color=""
  case "$symbol" in '*' ) color="${COLOR_GREEN:-}";; '~') color="${COLOR_YELLOW:-}";; '-') color="${COLOR_RED:-}";; '=') color="${COLOR_GREEN:-}";; '!') color="${COLOR_YELLOW:-}";; esac
  printf '%s%s%s %s\n' "$color" "$symbol" "${COLOR_RESET:-}" "$msg"
}
plan_add() { plan_line '*' "$*"; }
plan_change() { plan_line '~' "$*"; }
plan_remove() { plan_line '-' "$*"; }
plan_ok() { plan_line '=' "$*"; }
plan_warn() { plan_line '!' "$*"; }

record_result() {
  RESULT_MODULES+=("$1"); RESULT_STATUSES+=("$2"); RESULT_DETAILS+=("$3")
}
