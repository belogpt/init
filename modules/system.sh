#!/usr/bin/env bash

system_module_check() {
  load_os_release
  if [ -r /etc/os-release ]; then log_success "OS: ${OS_NAME} (${OS_ID:-unknown} ${OS_CODENAME:-unknown})"; else log_warn "OS: /etc/os-release not found"; return 2; fi
  case "${OS_ID}" in ubuntu|debian) return 0 ;; *) log_error "Unsupported OS: ${OS_ID:-unknown}"; return 2 ;; esac
}

system_module_plan() {
  log_info "Validate supported Ubuntu/Debian platform"
}

system_module_apply() {
  ensure_supported_platform
}
