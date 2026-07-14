#!/usr/bin/env bash

packages_module_check() {
  ensure_apt || return 2
  all_debs_installed "${BASE_PACKAGES[@]}" && return 0 || return 1
}

packages_module_plan() {
  ensure_apt
  if all_debs_installed "${BASE_PACKAGES[@]}"; then log_success "Base packages already installed"; else log_info "Install base packages: ${BASE_PACKAGES[*]}"; fi
  if [ "${UPGRADE}" = "1" ]; then log_info "Run apt upgrade for all packages"; else log_info "apt upgrade disabled by default; pass --upgrade to enable"; fi
}

packages_module_apply() {
  ensure_supported_platform; ensure_apt
  run_root apt update
  if [ "${UPGRADE}" = "1" ]; then
    local yes_args=(); [ "${ASSUME_YES}" = "1" ] && yes_args=(-y)
    run_root apt "${yes_args[@]}" upgrade
  fi
  if ! all_debs_installed "${BASE_PACKAGES[@]}"; then run_apt_install "${BASE_PACKAGES[@]}"; else log_success "Base packages already installed"; fi
  if [ -f /var/run/reboot-required ]; then log_warn "Reboot is recommended"; else log_success "No reboot-required marker found"; fi
}
