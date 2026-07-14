#!/usr/bin/env bash

firewall_module_check() { need_cmd ufw || return 1; ufw status >/dev/null 2>&1 || return 1; return 0; }
firewall_module_plan() { if need_cmd ufw; then log_success "UFW installed"; else log_info "Install UFW"; fi; log_info "Allow SSH plus requested ports: http=${ALLOW_HTTP} https=${ALLOW_HTTPS} custom=${ALLOW_PORTS[*]:-none}"; }
firewall_module_apply() {
  ensure_apt
  if ! need_cmd ufw; then run_root apt update; run_apt_install ufw; fi
  if ! ufw status 2>/dev/null | grep -q 'OpenSSH\|22/tcp'; then if ! run_root ufw allow OpenSSH; then run_root ufw allow ssh; fi; fi
  if [ "${ALLOW_HTTP}" = "1" ]; then run_root ufw allow 80/tcp; fi
  if [ "${ALLOW_HTTPS}" = "1" ]; then run_root ufw allow 443/tcp; fi
  local port; for port in "${ALLOW_PORTS[@]}"; do run_root ufw allow "${port}"; done
  run_root ufw --force enable
}
