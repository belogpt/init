#!/usr/bin/env bash

state_user() { printf '%s\n' "${SUDO_USER:-${USER:-}}"; }

expand_home_path() {
  case "$1" in
    '~') printf '%s\n' "${HOME}" ;;
    '~/'*) printf '%s/%s\n' "${HOME}" "${1#~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}
