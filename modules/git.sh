#!/usr/bin/env bash

git_module_check() {
  local user name email
  user="$(get_target_user)" || { log_warn "Git target user: unresolved"; return 2; }
  log_info "Checking Git identity for target user: ${user}"
  need_cmd git || return 1
  name="$(run_as_target_user git config --global user.name 2>/dev/null || true)"
  email="$(run_as_target_user git config --global user.email 2>/dev/null || true)"
  [ -n "${name}" ] && [ -n "${email}" ] && return 0 || return 1
}

git_module_plan() {
  local user; user="$(get_target_user)" || { log_warn "Git target user: unresolved; apply will require --target-user"; return 0; }
  log_info "Configure Git identity for target user: ${user}"
  if git_module_check; then log_success "Git identity already configured for ${user}"; else log_info "Set git config --global user.name/user.email when values are provided"; fi
}

git_module_apply() {
  validate_target_user
  need_cmd git || { log_warn "git is not installed; skipping Git identity"; return 0; }
  local user current_name current_email name email
  user="$(get_target_user)"
  current_name="$(run_as_target_user git config --global user.name 2>/dev/null || true)"
  current_email="$(run_as_target_user git config --global user.email 2>/dev/null || true)"
  name="${GIT_NAME:-${current_name}}"; email="${GIT_EMAIL:-${current_email}}"
  if [ -z "${name}" ] && [ "${ASSUME_YES}" != "1" ] && [ -t 0 ]; then read -r -p "Enter git user.name for ${user}: " name; fi
  if [ -z "${email}" ] && [ "${ASSUME_YES}" != "1" ] && [ -t 0 ]; then read -r -p "Enter git user.email for ${user}: " email; fi
  if [ -z "${name}" ] || [ -z "${email}" ]; then log_warn "Git identity skipped for ${user}: name or email missing"; return 0; fi
  run_as_target_user git config --global user.name "${name}"
  run_as_target_user git config --global user.email "${email}"
  log_success "Git identity configured for ${user}"
}
