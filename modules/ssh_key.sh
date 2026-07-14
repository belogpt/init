#!/usr/bin/env bash

ssh_key_module_check() {
  local user key_path
  user="$(get_target_user)" || { log_warn "SSH target user: unresolved"; return 2; }
  key_path="$(target_path "${SSH_KEY_PATH}")" || return 2
  log_info "Checking SSH key for target user: ${user} at ${key_path}"
  [ -f "${key_path}.pub" ] && return 0 || return 1
}

ssh_key_module_plan() {
  local user key_path
  user="$(get_target_user)" || { log_warn "SSH target user: unresolved; apply will require --target-user"; return 0; }
  key_path="$(target_path "${SSH_KEY_PATH}")"
  log_info "Create ed25519 SSH key for target user ${user} at ${key_path} if missing"
}

ssh_key_module_apply() {
  validate_target_user
  local user key_path key_dir
  user="$(get_target_user)"; key_path="$(target_path "${SSH_KEY_PATH}")"; key_dir="$(dirname -- "${key_path}")"
  if [ -e "${key_path}" ] || [ -e "${key_path}.pub" ]; then log_success "SSH key already exists for ${user}: ${key_path}"; return 0; fi
  run_root install -d -m 700 -o "${user}" -g "$(id -gn "${user}")" "${key_dir}"
  run_as_target_user ssh-keygen -t ed25519 -C "${SSH_KEY_COMMENT}" -f "${key_path}" -N ''
  run_root chmod 700 "${key_dir}"
  run_root chmod 600 "${key_path}"
  run_root chmod 644 "${key_path}.pub"
  run_root chown "${user}:$(id -gn "${user}")" "${key_dir}" "${key_path}" "${key_path}.pub"
  log_success "SSH key created for ${user}: ${key_path}"
}
