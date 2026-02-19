#!/usr/bin/env bash
set -euo pipefail

# =========================
# Server bootstrap: git + docker + github ssh key + git identity
# Works on Ubuntu/Debian (apt).
# =========================

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "✅ %s\n" "$*"; }
warn() { printf "⚠️  %s\n" "$*"; }
err()  { printf "❌ %s\n" "$*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

require_root_or_sudo() {
  if [ "${EUID:-$(id -u)}" -ne 0 ] && ! need_cmd sudo; then
    err "Need root or sudo installed."
    exit 1
  fi
}

run() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    bash -lc "$*"
  else
    sudo bash -lc "$*"
  fi
}

is_ubuntu_like() {
  [ -f /etc/os-release ] || return 1
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *"ubuntu"* || "${ID_LIKE:-}" == *"debian"* || "${ID:-}" == "debian" ]]
}

ensure_apt() {
  need_cmd apt || { err "This script requires apt (Ubuntu/Debian)."; exit 1; }
}

install_base_packages() {
  bold "Updating system & installing base packages..."
  run "apt update && apt -y upgrade"
  run "apt -y install git ca-certificates curl gnupg lsb-release"
  ok "Base packages installed."
}

install_docker() {
  if need_cmd docker && docker --version >/dev/null 2>&1; then
    ok "Docker already installed: $(docker --version | head -n1)"
    if docker compose version >/dev/null 2>&1; then
      ok "Docker Compose plugin: $(docker compose version | head -n1)"
    else
      warn "Docker present, but docker compose plugin not detected."
    fi
    return 0
  fi

  bold "Installing Docker (official repo)..."

  run "install -m 0755 -d /etc/apt/keyrings"
  run "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
  run "chmod a+r /etc/apt/keyrings/docker.gpg"

  # shellcheck disable=SC1091
  . /etc/os-release
  local codename="${VERSION_CODENAME:-}"
  if [ -z "$codename" ]; then
    # fallback for some Debian cases
    codename="$(lsb_release -cs 2>/dev/null || true)"
  fi
  if [ -z "$codename" ]; then
    err "Cannot determine distro codename."
    exit 1
  fi

  run "echo 'deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $codename stable' > /etc/apt/sources.list.d/docker.list"
  run "apt update"
  run "apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

  ok "Docker installed: $(docker --version | head -n1)"
  ok "Docker Compose plugin: $(docker compose version | head -n1)"
}

maybe_add_user_to_docker_group() {
  # If run as root, optionally add a target user to docker group.
  # If run as non-root, add current user.
  local target_user="${SUDO_USER:-${USER:-}}"

  if [ -z "$target_user" ]; then
    return 0
  fi

  if id -nG "$target_user" 2>/dev/null | grep -qw docker; then
    ok "User '$target_user' already in docker group."
    return 0
  fi

  bold "Adding user '$target_user' to docker group..."
  run "usermod -aG docker '$target_user'"
  ok "Added. Re-login may be required for group changes to take effect."
}

setup_github_ssh_key() {
  bold "GitHub SSH key setup (ed25519)..."

  local key_path="${HOME}/.ssh/id_ed25519"
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"

  if [ -f "$key_path" ]; then
    ok "SSH key already exists: $key_path"
  else
    ssh-keygen -t ed25519 -C "server-$(hostname)" -f "$key_path" -N ""
    ok "SSH key created: $key_path"
  fi

  # Start ssh-agent and add key (best-effort)
  if need_cmd ssh-agent; then
    # shellcheck disable=SC2046
    eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
  fi
  if need_cmd ssh-add; then
    ssh-add "$key_path" >/dev/null 2>&1 || true
  fi

  bold "Public key (add this in GitHub → Settings → SSH and GPG keys):"
  echo "----------------------------------------------------------------"
  cat "${key_path}.pub"
  echo "----------------------------------------------------------------"
  warn "After adding the key in GitHub, run: ssh -T git@github.com"
}

configure_git_identity() {
  bold "Configure global git identity (user.name / user.email)"

  local current_name
  local current_email
  current_name="$(git config --global user.name || true)"
  current_email="$(git config --global user.email || true)"

  if [ -n "$current_name" ] && [ -n "$current_email" ]; then
    ok "Git identity already set:"
    echo "  user.name  = $current_name"
    echo "  user.email = $current_email"
    return 0
  fi

  local name email
  read -r -p "Enter git user.name: " name
  read -r -p "Enter git user.email: " email

  if [ -z "${name:-}" ] || [ -z "${email:-}" ]; then
    warn "Skipped git identity (empty input). You can set later with:"
    echo "  git config --global user.name \"Your Name\""
    echo "  git config --global user.email \"you@example.com\""
    return 0
  fi

  git config --global user.name "$name"
  git config --global user.email "$email"

  ok "Git identity configured:"
  echo "  user.name  = $(git config --global user.name)"
  echo "  user.email = $(git config --global user.email)"
}

show_versions() {
  bold "Installed versions summary:"
  if need_cmd git; then ok "git: $(git --version)"; else warn "git: not found"; fi
  if need_cmd docker; then ok "docker: $(docker --version | head -n1)"; else warn "docker: not found"; fi
  if need_cmd docker && docker compose version >/dev/null 2>&1; then
    ok "docker compose: $(docker compose version | head -n1)"
  else
    warn "docker compose: not found"
  fi
}

main() {
  require_root_or_sudo
  ensure_apt
  if ! is_ubuntu_like; then
    warn "OS not detected as Ubuntu/Debian-like. Proceeding anyway (apt required)."
  fi

  install_base_packages
  install_docker
  maybe_add_user_to_docker_group
  setup_github_ssh_key
  configure_git_identity
  show_versions

  bold "Done."
  echo "Next steps:"
  echo "  1) Add the printed SSH public key to GitHub."
  echo "  2) Test: ssh -T git@github.com"
  echo "  3) Clone via SSH: git clone git@github.com:OWNER/REPO.git"
}

main "$@"
