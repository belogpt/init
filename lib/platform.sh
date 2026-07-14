#!/usr/bin/env bash

OS_ID=""; OS_NAME="unknown"; OS_CODENAME=""

load_os_release() {
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091 # /etc/os-release is the standard local OS metadata file.
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
    OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  fi
  if [ -z "${OS_CODENAME}" ] && need_cmd lsb_release; then
    OS_CODENAME="$(lsb_release -cs 2>/dev/null || true)"
  fi
}

ensure_supported_platform() {
  load_os_release
  case "${OS_ID}" in
    ubuntu|debian) return 0 ;;
    *) log_error "Only Ubuntu and Debian are supported. Detected: ${OS_NAME} (${OS_ID:-unknown})."; return 1 ;;
  esac
}

ensure_apt() {
  need_cmd apt || { log_error "This tool requires apt (Ubuntu/Debian)."; return 1; }
}
