#!/usr/bin/env bash

docker_module_check() { need_cmd docker && docker compose version >/dev/null 2>&1 && return 0 || return 1; }
docker_module_plan() { if docker_module_check; then log_success "Docker and Compose plugin already detected"; else log_info "Install/configure Docker from official repository"; fi; }
_docker_repo_url() { printf 'https://download.docker.com/linux/%s\n' "${OS_ID}"; }
docker_module_apply() {
  ensure_supported_platform; ensure_apt
  if docker_module_check; then log_success "Docker already installed: $(docker --version | head -n1)"; return 0; fi
  local repo_url arch; repo_url="$(_docker_repo_url)"; arch="$(dpkg --print-architecture)"
  run_root apt update; run_apt_install ca-certificates curl gnupg lsb-release
  run_root install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "${repo_url}/gpg" | run_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  run_root chmod a+r /etc/apt/keyrings/docker.gpg
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] %s %s stable\n' "${arch}" "${repo_url}" "${OS_CODENAME}" | run_root tee /etc/apt/sources.list.d/docker.list >/dev/null
  run_root apt update; run_apt_install "${DOCKER_PACKAGES[@]}"
  if need_cmd systemctl; then
    run_root systemctl enable docker
    if ! run_root systemctl start docker; then log_warn "Docker service start failed; inspect systemctl status docker"; fi
  fi
  local target_user
  if target_user="$(get_target_user 2>/dev/null)" && [ -n "${target_user}" ]; then
    getent group docker >/dev/null 2>&1 || run_root groupadd docker
    if id -nG "${target_user}" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then log_success "User ${target_user} is already in docker group"; else run_root usermod -aG docker "${target_user}"; log_warn "Re-login may be required for docker group changes to apply"; fi
  fi
}
