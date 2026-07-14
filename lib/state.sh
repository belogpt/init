#!/usr/bin/env bash

get_target_user() {
  if [ -n "${TARGET_USER:-}" ]; then
    printf '%s\n' "${TARGET_USER}"
  elif [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    printf '%s\n' "${SUDO_USER}"
  elif [ "${EUID:-$(id -u)}" -ne 0 ]; then
    id -un
  else
    return 1
  fi
}

validate_target_user() {
  local user
  user="$(get_target_user)" || { log_error "Target user is not set. Use --target-user USER; root requires explicit --target-user root."; return 1; }
  getent passwd "${user}" >/dev/null 2>&1 || { log_error "Target user does not exist: ${user}"; return 1; }
}

get_target_home() {
  local user
  user="$(get_target_user)" || return 1
  getent passwd "${user}" | cut -d: -f6
}

target_path() {
  local path="$1" home
  home="$(get_target_home)" || return 1
  case "${path}" in
    \~) printf '%s\n' "${home}" ;;
    \~/*) printf '%s/%s\n' "${home}" "${path#\~/}" ;;
    *) printf '%s\n' "${path}" ;;
  esac
}

run_as_target_user() {
  local user home
  validate_target_user || return 1
  user="$(get_target_user)"
  home="$(get_target_home)"
  if [ "$(id -u -n 2>/dev/null || true)" = "${user}" ]; then
    HOME="${home}" "$@"
  elif need_cmd runuser; then
    run_root runuser -u "${user}" -- env HOME="${home}" "$@"
  else
    run_root sudo -H -u "${user}" env HOME="${home}" "$@"
  fi
}
