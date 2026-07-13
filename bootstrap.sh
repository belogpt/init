#!/usr/bin/env bash
set -euo pipefail

# =========================
# Server init CLI: git + docker + github ssh key + firewall + security basics
# Works on Ubuntu/Debian (apt).
# =========================

DRY_RUN=0
ASSUME_YES=0
SKIP_UPGRADE=0
RUN_ALL=0
DO_CHECK=0
DO_DOCKER=0
DO_GIT=0
DO_SSH_KEY=0
DO_FIREWALL=0
DO_SECURITY=0
ALLOW_HTTP=0
ALLOW_HTTPS=0
ALLOW_PORTS=()
GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"
SSH_KEY_COMMENT="${SSH_KEY_COMMENT:-server-$(hostname)}"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "✅ %s\n" "$*"; }
warn() { printf "⚠️  %s\n" "$*"; }
err()  { printf "❌ %s\n" "$*" >&2; }
info() { printf "ℹ️  %s\n" "$*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'USAGE'
Server init CLI for Ubuntu/Debian.

Usage:
  ./bootstrap.sh [commands] [options]

Commands:
  --all                  Run the full recommended setup: Docker, SSH key, Git, firewall, security, checks
  --check                Show a server readiness report without changing the system
  --docker               Install and configure Docker + Docker Compose plugin
  --git                  Configure global git identity
  --ssh-key              Create/show GitHub SSH key
  --firewall             Install and enable UFW firewall
  --security             Install basic security packages: fail2ban, unattended-upgrades, needrestart

Global options:
  -h, --help             Show this help
  -y, --yes              Assume yes for supported prompts and apt operations
  --dry-run              Print commands that would run without changing the system
  --skip-upgrade         Run apt update, but skip apt upgrade

Git options:
  --git-name NAME        Set git config --global user.name
  --git-email EMAIL      Set git config --global user.email
                         You can also use GIT_NAME and GIT_EMAIL environment variables.

SSH key options:
  --ssh-key-path PATH    Path for the SSH key (default: ~/.ssh/id_ed25519)
  --ssh-key-comment TEXT Comment for generated SSH key (default: server-<hostname>)

Firewall options:
  --allow-http           Allow inbound 80/tcp when --firewall is used
  --allow-https          Allow inbound 443/tcp when --firewall is used
  --allow-port PORT      Allow an extra UFW port rule, e.g. 8080/tcp. Can be repeated.

Examples:
  ./bootstrap.sh --check
  ./bootstrap.sh --dry-run --all
  ./bootstrap.sh --all --skip-upgrade
  ./bootstrap.sh --docker
  ./bootstrap.sh --git --git-name "Admin" --git-email "admin@example.com"
  ./bootstrap.sh --ssh-key --ssh-key-comment "deploy@app-01"
  ./bootstrap.sh --firewall --allow-http --allow-https
  ./bootstrap.sh --security
USAGE
}

parse_args() {
  if [ "$#" -eq 0 ]; then
    usage
    exit 0
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -y|--yes) ASSUME_YES=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --skip-upgrade) SKIP_UPGRADE=1 ;;
      --all) RUN_ALL=1 ;;
      --check) DO_CHECK=1 ;;
      --docker) DO_DOCKER=1 ;;
      --git) DO_GIT=1 ;;
      --ssh-key) DO_SSH_KEY=1 ;;
      --firewall) DO_FIREWALL=1 ;;
      --security) DO_SECURITY=1 ;;
      --allow-http) ALLOW_HTTP=1 ;;
      --allow-https) ALLOW_HTTPS=1 ;;
      --allow-port)
        [ "$#" -ge 2 ] || { err "--allow-port requires a value."; exit 2; }
        ALLOW_PORTS+=("$2")
        shift
        ;;
      --git-name)
        [ "$#" -ge 2 ] || { err "--git-name requires a value."; exit 2; }
        GIT_NAME="$2"
        shift
        ;;
      --git-email)
        [ "$#" -ge 2 ] || { err "--git-email requires a value."; exit 2; }
        GIT_EMAIL="$2"
        shift
        ;;
      --ssh-key-path)
        [ "$#" -ge 2 ] || { err "--ssh-key-path requires a value."; exit 2; }
        SSH_KEY_PATH="$2"
        shift
        ;;
      --ssh-key-comment)
        [ "$#" -ge 2 ] || { err "--ssh-key-comment requires a value."; exit 2; }
        SSH_KEY_COMMENT="$2"
        shift
        ;;
      *) err "Unknown argument: $1"; echo; usage; exit 2 ;;
    esac
    shift
  done

  if [ "$RUN_ALL" -eq 1 ]; then
    DO_DOCKER=1
    DO_GIT=1
    DO_SSH_KEY=1
    DO_FIREWALL=1
    DO_SECURITY=1
    DO_CHECK=1
  fi

  if [ "$DO_CHECK$DO_DOCKER$DO_GIT$DO_SSH_KEY$DO_FIREWALL$DO_SECURITY" = "000000" ]; then
    err "No command selected. Use --help to see available commands."
    exit 2
  fi
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    info "Would run as root: $*"
    return 0
  fi

  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    bash -lc "$*"
  else
    sudo bash -lc "$*"
  fi
}


require_root_or_sudo() {
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  if [ "${EUID:-$(id -u)}" -ne 0 ] && ! need_cmd sudo; then
    err "Need root or sudo installed."
    exit 1
  fi
}

ensure_apt() {
  need_cmd apt || { err "This script requires apt (Ubuntu/Debian)."; exit 1; }
}

apt_install() {
  run "DEBIAN_FRONTEND=noninteractive apt -y install $*"
}

install_base_packages() {
  bold "Updating system & installing base packages..."
  run "apt update"
  if [ "$SKIP_UPGRADE" -eq 1 ]; then
    warn "Skipping apt upgrade because --skip-upgrade is set."
  else
    run "DEBIAN_FRONTEND=noninteractive apt -y upgrade"
  fi
  apt_install "git ca-certificates curl gnupg lsb-release"
  ok "Base packages installed."
}

detect_distro() {
  if [ ! -r /etc/os-release ]; then
    err "Cannot read /etc/os-release."
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  local distro_id="${ID:-}"
  local codename="${VERSION_CODENAME:-}"

  if [ -z "$codename" ]; then
    codename="$(lsb_release -cs 2>/dev/null || true)"
  fi

  if [ -z "$distro_id" ] || [ -z "$codename" ]; then
    err "Cannot determine distro id or codename."
    exit 1
  fi

  case "$distro_id" in
    ubuntu|debian)
      DOCKER_REPO_URL="https://download.docker.com/linux/${distro_id}"
      DISTRO_ID="$distro_id"
      DISTRO_CODENAME="$codename"
      ;;
    *)
      err "Unsupported distro for Docker install: $distro_id. Supported: ubuntu, debian."
      exit 1
      ;;
  esac
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
  detect_distro
  info "Detected distro: ${DISTRO_ID} ${DISTRO_CODENAME}"
  info "Docker repo: ${DOCKER_REPO_URL}"

  run "for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do apt-get remove -y \$pkg >/dev/null 2>&1 || true; done"
  run "install -m 0755 -d /etc/apt/keyrings"
  run "curl -fsSL ${DOCKER_REPO_URL}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
  run "chmod a+r /etc/apt/keyrings/docker.gpg"
  run "echo 'deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_REPO_URL} ${DISTRO_CODENAME} stable' > /etc/apt/sources.list.d/docker.list"
  run "apt update"
  apt_install "docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

  if [ "$DRY_RUN" -eq 1 ]; then
    ok "Docker install plan completed (dry-run)."
    return 0
  fi

  ok "Docker installed: $(docker --version | head -n1)"
  ok "Docker Compose plugin: $(docker compose version | head -n1)"
}

ensure_docker_running() {
  bold "Checking Docker daemon..."

  if [ "$DRY_RUN" -eq 1 ]; then
    info "Would check, start, and enable Docker service."
    return 0
  fi

  if ! need_cmd systemctl; then
    warn "systemctl not found. Skipping docker service management."
    return 0
  fi

  run "systemctl status docker --no-pager -n 5 || true"

  if run "systemctl is-active --quiet docker"; then
    ok "Docker service is running."
  else
    warn "Docker service not running. Starting..."
    run "systemctl start docker"
  fi

  run "systemctl enable docker"

  if [ -S /var/run/docker.sock ]; then
    ok "Docker socket exists: /var/run/docker.sock"
  else
    warn "Docker socket not found yet (may appear after service starts)."
  fi

  if docker info >/dev/null 2>&1; then
    ok "Docker daemon responding correctly (docker info OK)."
  else
    warn "Docker daemon not responding for current user."
    warn "If you run as non-root, ensure user is in docker group and re-login."
    warn "Try: sudo systemctl restart docker"
  fi
}

maybe_add_user_to_docker_group() {
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

  local key_path="${SSH_KEY_PATH/#\~/$HOME}"
  local key_dir
  key_dir="$(dirname "$key_path")"

  if [ "$DRY_RUN" -eq 1 ]; then
    info "Would ensure SSH directory exists: $key_dir"
    info "Would create SSH key if missing: $key_path"
    info "Would use SSH key comment: $SSH_KEY_COMMENT"
    return 0
  fi

  mkdir -p "$key_dir"
  chmod 700 "$key_dir"

  if [ -f "$key_path" ]; then
    ok "SSH key already exists: $key_path"
  else
    ssh-keygen -t ed25519 -C "$SSH_KEY_COMMENT" -f "$key_path" -N ""
    ok "SSH key created: $key_path"
  fi

  if need_cmd ssh-agent; then
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

  if [ -z "$GIT_NAME" ]; then
    GIT_NAME="$current_name"
  fi
  if [ -z "$GIT_EMAIL" ]; then
    GIT_EMAIL="$current_email"
  fi

  if [ -z "$GIT_NAME" ] && [ "$ASSUME_YES" -eq 0 ]; then
    read -r -p "Enter git user.name: " GIT_NAME
  fi
  if [ -z "$GIT_EMAIL" ] && [ "$ASSUME_YES" -eq 0 ]; then
    read -r -p "Enter git user.email: " GIT_EMAIL
  fi

  if [ -z "${GIT_NAME:-}" ] || [ -z "${GIT_EMAIL:-}" ]; then
    warn "Skipped git identity (empty input). You can set later with:"
    echo "  git config --global user.name \"Your Name\""
    echo "  git config --global user.email \"you@example.com\""
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    info "Would run: git config --global user.name <provided>"
    info "Would run: git config --global user.email <provided>"
  else
    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
  fi

  ok "Git identity configured:"
  echo "  user.name  = $GIT_NAME"
  echo "  user.email = $GIT_EMAIL"
}

configure_firewall() {
  bold "Configuring UFW firewall..."
  apt_install "ufw"
  run "ufw allow OpenSSH"

  if [ "$ALLOW_HTTP" -eq 1 ]; then
    run "ufw allow 80/tcp"
  fi
  if [ "$ALLOW_HTTPS" -eq 1 ]; then
    run "ufw allow 443/tcp"
  fi
  for port in "${ALLOW_PORTS[@]}"; do
    run "ufw allow '$port'"
  done

  run "ufw --force enable"
  run "ufw status verbose"
  ok "Firewall configured."
}

configure_security() {
  bold "Installing basic security packages..."
  apt_install "fail2ban unattended-upgrades needrestart"

  if need_cmd systemctl; then
    run "systemctl enable --now fail2ban || true"
    run "systemctl status fail2ban --no-pager -n 5 || true"
  else
    warn "systemctl not found. Skipping fail2ban service management."
  fi

  ok "Security packages installed."
  warn "SSH hardening is intentionally not changed by this command to avoid locking you out."
}

check_system() {
  bold "Server readiness check:"

  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    ok "OS: ${PRETTY_NAME:-unknown}"
  else
    warn "OS: cannot read /etc/os-release"
  fi

  if need_cmd apt; then ok "apt: available"; else warn "apt: not found"; fi
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then ok "privileges: running as root"; elif need_cmd sudo; then ok "privileges: sudo available"; else warn "privileges: no root/sudo"; fi
  if need_cmd git; then ok "git: $(git --version)"; else warn "git: not found"; fi
  if need_cmd curl; then ok "curl: available"; else warn "curl: not found"; fi
  if need_cmd docker; then ok "docker: $(docker --version | head -n1)"; else warn "docker: not found"; fi
  if need_cmd docker && docker compose version >/dev/null 2>&1; then ok "docker compose: $(docker compose version | head -n1)"; else warn "docker compose: not found"; fi

  if need_cmd systemctl; then
    if systemctl is-active --quiet docker 2>/dev/null; then ok "docker service: active"; else warn "docker service: not active or unavailable"; fi
    if systemctl is-active --quiet fail2ban 2>/dev/null; then ok "fail2ban service: active"; else warn "fail2ban service: not active or unavailable"; fi
  else
    warn "systemctl: not found"
  fi

  local current_name current_email
  current_name="$(git config --global user.name || true)"
  current_email="$(git config --global user.email || true)"
  if [ -n "$current_name" ] && [ -n "$current_email" ]; then ok "git identity: $current_name <$current_email>"; else warn "git identity: incomplete"; fi

  local key_path="${SSH_KEY_PATH/#\~/$HOME}"
  if [ -f "${key_path}.pub" ]; then ok "SSH public key: ${key_path}.pub"; else warn "SSH public key: not found at ${key_path}.pub"; fi

  local target_user="${SUDO_USER:-${USER:-}}"
  if [ -n "$target_user" ] && id -nG "$target_user" 2>/dev/null | grep -qw docker; then ok "docker group: '$target_user' is a member"; else warn "docker group: target user is not a member"; fi

  if need_cmd ufw; then run "ufw status verbose || true"; else warn "ufw: not installed"; fi
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
  parse_args "$@"

  if [ "$DO_CHECK" -eq 1 ] && [ "$RUN_ALL" -eq 0 ] && [ "$DO_DOCKER$DO_GIT$DO_SSH_KEY$DO_FIREWALL$DO_SECURITY" = "00000" ]; then
    check_system
    return 0
  fi

  require_root_or_sudo
  ensure_apt

  if [ "$DO_DOCKER" -eq 1 ] || [ "$DO_FIREWALL" -eq 1 ] || [ "$DO_SECURITY" -eq 1 ]; then
    install_base_packages
  fi

  if [ "$DO_DOCKER" -eq 1 ]; then
    install_docker
    ensure_docker_running
    maybe_add_user_to_docker_group
  fi
  if [ "$DO_SSH_KEY" -eq 1 ]; then
    setup_github_ssh_key
  fi
  if [ "$DO_GIT" -eq 1 ]; then
    configure_git_identity
  fi
  if [ "$DO_FIREWALL" -eq 1 ]; then
    configure_firewall
  fi
  if [ "$DO_SECURITY" -eq 1 ]; then
    configure_security
  fi

  show_versions
  if [ "$DO_CHECK" -eq 1 ]; then
    check_system
  fi

  bold "Done."
  echo "Next steps:"
  echo "  1) If a public key was printed, add it to GitHub."
  echo "  2) Test GitHub SSH: ssh -T git@github.com"
  echo "  3) Clone via SSH: git clone git@github.com:OWNER/REPO.git"
  echo "  4) If docker access is denied after group add: log out/in or run: newgrp docker"
}

main "$@"
