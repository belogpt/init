#!/usr/bin/env bash

init_error_trap() {
  local exit_code="$?" line_no="${1:-unknown}" command="${2:-unknown}" file="${BASH_SOURCE[1]:-${0}}"
  log_error "Command failed: file=${file} line=${line_no} command=${command} exit=${exit_code}"
  exit "${exit_code}"
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

require_root_or_sudo() {
  if [ "${EUID:-$(id -u)}" -ne 0 ] && ! need_cmd sudo; then
    log_error "Need root or sudo installed."
    return 1
  fi
}

run_root() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

apt_yes_args() {
  if [ "${ASSUME_YES:-0}" = "1" ]; then
    printf '%s\n' -y
  fi
}

run_apt_install() {
  local yes_args=()
  if [ "${ASSUME_YES:-0}" = "1" ]; then yes_args=(-y); fi
  run_root apt "${yes_args[@]}" install "$@"
}

is_deb_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }

all_debs_installed() {
  local package
  for package in "$@"; do
    is_deb_installed "${package}" || return 1
  done
}
