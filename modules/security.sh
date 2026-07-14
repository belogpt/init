#!/usr/bin/env bash

security_module_check() { all_debs_installed "${SECURITY_PACKAGES[@]}" && return 0 || return 1; }
security_module_plan() { if security_module_check; then log_success "Security packages already installed"; else log_info "Install security packages: ${SECURITY_PACKAGES[*]}"; fi; }
security_module_apply() {
  ensure_apt
  if ! all_debs_installed "${SECURITY_PACKAGES[@]}"; then run_root apt update; run_apt_install "${SECURITY_PACKAGES[@]}"; fi
  if need_cmd systemctl; then if ! run_root systemctl enable --now fail2ban; then log_warn "fail2ban service enable/start failed; inspect systemctl status fail2ban"; fi; fi
}
