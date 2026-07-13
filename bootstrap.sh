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

need_cmd() { command -v "$1" >/dev/null 2>&1; }

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

  # Determine codename
  # shellcheck disable=SC1091
  . /etc/os-release
  local codename="${VERSION_CODENAME:-}"
  if [ -z "$codename" ]; then
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

ensure_docker_running() {
  bold "Checking Docker daemon..."

  if ! need_cmd systemctl; then
    warn "systemctl not found. Skipping docker service management."
    return 0
  fi

  # Show current status briefly (non-fatal)
  run "systemctl status docker --no-pager -n 5 || true"

  if run "systemctl is-active --quiet docker"; then
    ok "Docker service is running."
  else
    warn "Docker service not running. Starting..."
    run "systemctl start docker"
  fi

  # Enable on boot
  run "systemctl enable docker"

  # Socket check
  if [ -S /var/run/docker.sock ]; then
    ok "Docker socket exists: /var/run/docker.sock"
  else
    warn "Docker socket not found yet (may appear after service starts)."
  fi

  # Daemon responsiveness check
  if docker info >/dev/null 2>&1; then
    ok "Docker daemon responding correctly (docker info OK)."
  else
    warn "Docker daemon not responding for current user."
    warn "If you run as non-root, ensure user is in docker group and re-login."
    warn "Try: sudo systemctl restart docker"
  fi
}

maybe_add_user_to_docker_group() {
  # If run with sudo: add original user; else add current user.
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

  local current_name current_email
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

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [OPTIONS]

Server bootstrap helper for Ubuntu/Debian. Run one or more operations explicitly,
or run without arguments to choose operations from an interactive menu.

Options:
  --help      Show this help message and exit without changes.
  --all       Run the full bootstrap scenario: base packages, Docker,
              GitHub SSH key, git identity, and version checks.
  --check     Show installed git/Docker versions only.
  --docker    Install Docker, ensure the Docker daemon is running, and add
              the current/sudo user to the docker group when needed.
  --git       Configure global git identity (user.name / user.email).
  --ssh-key   Create or show a GitHub ed25519 SSH key.

Examples:
  ./bootstrap.sh
  ./bootstrap.sh --all
  ./bootstrap.sh --docker --ssh-key
  ./bootstrap.sh --check
EOF
}

show_menu() {
  cat <<'EOF'

Select bootstrap operations to run:
  1) Full bootstrap (--all)
  2) Check installed versions (--check)
  3) Install/configure Docker (--docker)
  4) Configure git identity (--git)
  5) Create/show GitHub SSH key (--ssh-key)
  h) Show help
  0) Exit without changes

Enter one or more numbers separated by spaces or commas.
Example: 3,5
EOF
}

RUN_ALL=0
RUN_CHECK=0
RUN_DOCKER=0
RUN_GIT=0
RUN_SSH_KEY=0

parse_menu_choice() {
  local choice token

  show_menu
  printf "Choice: "
  if ! IFS= read -r choice; then
    echo
    warn "No input received. Exiting without changes."
    exit 0
  fi

  choice="${choice//,/ }"
  for token in $choice; do
    case "$token" in
      1|all|--all)
        RUN_ALL=1
        ;;
      2|check|--check)
        RUN_CHECK=1
        ;;
      3|docker|--docker)
        RUN_DOCKER=1
        ;;
      4|git|--git)
        RUN_GIT=1
        ;;
      5|ssh-key|--ssh-key)
        RUN_SSH_KEY=1
        ;;
      h|help|--help)
        usage
        exit 0
        ;;
      0|q|quit|exit)
        ok "No changes requested."
        exit 0
        ;;
      *)
        err "Unknown menu option: $token"
        echo
        show_menu
        exit 1
        ;;
    esac
  done

  if [ "$RUN_ALL" -eq 0 ] \
    && [ "$RUN_CHECK" -eq 0 ] \
    && [ "$RUN_DOCKER" -eq 0 ] \
    && [ "$RUN_GIT" -eq 0 ] \
    && [ "$RUN_SSH_KEY" -eq 0 ]; then
    warn "No operations selected. Exiting without changes."
    exit 0
  fi
}

parse_args() {
  if [ "$#" -eq 0 ]; then
    parse_menu_choice
    return 0
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help)
        usage
        exit 0
        ;;
      --all)
        RUN_ALL=1
        ;;
      --check)
        RUN_CHECK=1
        ;;
      --docker)
        RUN_DOCKER=1
        ;;
      --git)
        RUN_GIT=1
        ;;
      --ssh-key)
        RUN_SSH_KEY=1
        ;;
      *)
        err "Unknown option: $1"
        echo
        usage
        exit 1
        ;;
    esac
    shift
  done
}

main() {
  if [ "$RUN_ALL" -eq 1 ]; then
    require_root_or_sudo
    ensure_apt

    install_base_packages
    install_docker
    ensure_docker_running
    maybe_add_user_to_docker_group
    setup_github_ssh_key
    configure_git_identity
    show_versions

    bold "Done."
    echo "Next steps:"
    echo "  1) Add the printed SSH public key to GitHub."
    echo "  2) Test: ssh -T git@github.com"
    echo "  3) Clone via SSH: git clone git@github.com:OWNER/REPO.git"
    echo "  4) If docker access denied after group add: log out/in or run: newgrp docker"
    return 0
  fi

  if [ "$RUN_DOCKER" -eq 1 ]; then
    require_root_or_sudo
    ensure_apt
    install_docker
    ensure_docker_running
    maybe_add_user_to_docker_group
  fi

  if [ "$RUN_SSH_KEY" -eq 1 ]; then
    setup_github_ssh_key
  fi

  if [ "$RUN_GIT" -eq 1 ]; then
    configure_git_identity
  fi

  if [ "$RUN_CHECK" -eq 1 ]; then
    show_versions
  fi

  bold "Done."
}

parse_args "$@"
main
