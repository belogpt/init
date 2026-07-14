#!/usr/bin/env bash

system_module_check() {
  log_info "Checking system state"
  load_os_release
  if [ -r /etc/os-release ]; then log_success "OS: ${OS_NAME} (${OS_ID:-unknown} ${OS_CODENAME:-unknown})"; else log_warn "OS: /etc/os-release not found"; fi
  if need_cmd apt; then log_success "apt: available"; else log_warn "apt: not found"; fi
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then log_success "root/sudo: running as root"; elif need_cmd sudo; then log_success "root/sudo: sudo available"; else log_warn "root/sudo: unavailable"; fi
  if need_cmd git; then log_success "git: $(git --version)"; else log_warn "git: not found"; fi
  _check_git_identity
  _check_ssh_key
  _check_docker
  _check_ufw
  if need_cmd fail2ban-client; then log_success "fail2ban: installed"; else log_warn "fail2ban: not installed"; fi
}

system_module_plan() {
  log_info "Planned system bootstrap changes"
  ensure_supported_platform
  ensure_apt
  if all_debs_installed "${BASE_PACKAGES[@]}"; then log_success "Base packages are already installed"; else log_info "Install base packages: ${BASE_PACKAGES[*]}"; fi
  if [ "${SKIP_UPGRADE}" = "1" ]; then log_warn "Skip apt upgrade"; else log_info "Run apt upgrade"; fi
  if need_cmd docker && docker compose version >/dev/null 2>&1; then log_success "Docker and Compose plugin already detected"; else log_info "Install/configure Docker from official repository"; fi
  if _git_identity_complete; then log_success "Git identity already configured"; else log_info "Configure Git identity when GIT_NAME and GIT_EMAIL are provided or interactive input is available"; fi
  if _ssh_key_exists; then log_success "SSH public key already exists"; else log_info "Create ed25519 SSH key at $(expand_home_path "${SSH_KEY_PATH}")"; fi
  if need_cmd ufw; then log_success "UFW already installed"; else log_info "Install UFW and allow SSH"; fi
  if all_debs_installed "${SECURITY_PACKAGES[@]}"; then log_success "Security packages already installed"; else log_info "Install security packages: ${SECURITY_PACKAGES[*]}"; fi
}

system_module_apply() {
  log_info "Applying system bootstrap"
  require_root_or_sudo
  ensure_supported_platform
  ensure_apt
  _apply_base_packages
  _apply_docker
  _apply_ssh_key
  _apply_git_identity
  _apply_firewall
  _apply_security
  log_success "System bootstrap complete"
}

_apply_base_packages() {
  if all_debs_installed "${BASE_PACKAGES[@]}"; then
    log_success "Base packages already installed"
    return 0
  fi
  run_root apt update
  local yes_args=()
  if [ "${ASSUME_YES}" = "1" ]; then yes_args=(-y); fi
  if [ "${SKIP_UPGRADE}" = "1" ]; then log_warn "Skipping apt upgrade"; else run_root apt "${yes_args[@]}" upgrade; fi
  run_apt_install "${BASE_PACKAGES[@]}"
}

_docker_repo_url() { printf 'https://download.docker.com/linux/%s\n' "${OS_ID}"; }

_apply_docker() {
  if need_cmd docker && docker compose version >/dev/null 2>&1; then
    log_success "Docker already installed: $(docker --version | head -n1)"
    return 0
  fi
  local repo_url arch
  repo_url="$(_docker_repo_url)"
  arch="$(dpkg --print-architecture)"
  run_root apt update
  run_apt_install ca-certificates curl gnupg lsb-release
  run_root install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "${repo_url}/gpg" | run_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  run_root chmod a+r /etc/apt/keyrings/docker.gpg
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] %s %s stable\n' "${arch}" "${repo_url}" "${OS_CODENAME}" | run_root tee /etc/apt/sources.list.d/docker.list >/dev/null
  run_root apt update
  run_apt_install "${DOCKER_PACKAGES[@]}"
  if need_cmd systemctl; then
    run_root systemctl enable docker
    run_root systemctl start docker || true
  fi
  _apply_docker_group
}

_apply_docker_group() {
  local target_user
  target_user="$(state_user)"
  [ -n "${target_user}" ] || return 0
  getent group docker >/dev/null 2>&1 || run_root groupadd docker
  if id -nG "${target_user}" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    log_success "User ${target_user} is already in docker group"
    return 0
  fi
  run_root usermod -aG docker "${target_user}"
  log_warn "Re-login may be required for docker group changes to apply"
}

_apply_ssh_key() {
  local key_path key_dir
  key_path="$(expand_home_path "${SSH_KEY_PATH}")"
  key_dir="$(dirname -- "${key_path}")"
  if [ -f "${key_path}" ]; then log_success "SSH key already exists: ${key_path}"; return 0; fi
  mkdir -p "${key_dir}"
  chmod 700 "${key_dir}"
  ssh-keygen -t ed25519 -C "${SSH_KEY_COMMENT}" -f "${key_path}" -N ''
  log_success "SSH key created: ${key_path}"
}

_apply_git_identity() {
  need_cmd git || { log_warn "git is not installed; skipping Git identity"; return 0; }
  local current_name current_email name email
  current_name="$(git config --global user.name 2>/dev/null || true)"
  current_email="$(git config --global user.email 2>/dev/null || true)"
  name="${GIT_NAME:-${current_name}}"
  email="${GIT_EMAIL:-${current_email}}"
  if [ -z "${name}" ] && [ "${ASSUME_YES}" != "1" ] && [ -t 0 ]; then read -r -p "Enter git user.name: " name; fi
  if [ -z "${email}" ] && [ "${ASSUME_YES}" != "1" ] && [ -t 0 ]; then read -r -p "Enter git user.email: " email; fi
  if [ -z "${name}" ] || [ -z "${email}" ]; then log_warn "Git identity skipped: name or email missing"; return 0; fi
  if [ "${current_name}" = "${name}" ] && [ "${current_email}" = "${email}" ]; then log_success "Git identity already configured"; return 0; fi
  git config --global user.name "${name}"
  git config --global user.email "${email}"
  log_success "Git identity configured"
}

_apply_firewall() {
  if ! need_cmd ufw; then run_root apt update; run_apt_install ufw; fi
  if ! ufw status 2>/dev/null | grep -q 'OpenSSH\|22/tcp'; then
    run_root ufw allow OpenSSH || run_root ufw allow ssh
  fi
  [ "${ALLOW_HTTP}" = "1" ] && run_root ufw allow 80/tcp || true
  [ "${ALLOW_HTTPS}" = "1" ] && run_root ufw allow 443/tcp || true
  local port
  for port in "${ALLOW_PORTS[@]}"; do run_root ufw allow "${port}"; done
  run_root ufw --force enable
}

_apply_security() {
  all_debs_installed "${SECURITY_PACKAGES[@]}" || { run_root apt update; run_apt_install "${SECURITY_PACKAGES[@]}"; }
  if need_cmd systemctl; then run_root systemctl enable --now fail2ban || true; fi
}

_git_identity_complete() { [ -n "$(git config --global user.name 2>/dev/null || true)" ] && [ -n "$(git config --global user.email 2>/dev/null || true)" ]; }
_check_git_identity() {
  if _git_identity_complete; then log_success "Git identity: configured"; else log_warn "Git identity: incomplete or missing"; fi
}
_ssh_key_exists() { [ -f "$(expand_home_path "${SSH_KEY_PATH}").pub" ]; }
_check_ssh_key() {
  if _ssh_key_exists; then log_success "SSH public key: $(expand_home_path "${SSH_KEY_PATH}").pub"; else log_warn "SSH public key: missing"; fi
}
_check_docker() {
  if need_cmd docker; then log_success "Docker: $(docker --version | head -n1)"; else log_warn "Docker: not found"; fi
  if need_cmd docker && docker compose version >/dev/null 2>&1; then log_success "Docker Compose: $(docker compose version | head -n1)"; else log_warn "Docker Compose: not found"; fi
}
_check_ufw() {
  if need_cmd ufw; then log_success "UFW: $(ufw status 2>/dev/null | head -n1)"; else log_warn "UFW: not installed"; fi
}
