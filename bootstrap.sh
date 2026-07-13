#!/usr/bin/env bash
set -euo pipefail

# =========================
# Server bootstrap helper for Ubuntu/Debian (apt).
# Supports explicit CLI commands, dry-run checks, Docker, Git, SSH keys,
# firewall (UFW), and baseline security packages.
# =========================

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "✅ %s\n" "$*"; }
warn() { printf "⚠️  %s\n" "$*"; }
err()  { printf "❌ %s\n" "$*"; }
info() { printf "ℹ️  %s\n" "$*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }
shell_quote() { printf "%q" "$1"; }

DRY_RUN=0
ASSUME_YES=0
SKIP_UPGRADE=0

RUN_ALL=0
RUN_CHECK=0
RUN_DOCKER=0
RUN_GIT=0
RUN_SSH_KEY=0
RUN_FIREWALL=0
RUN_SECURITY=0

GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519"
SSH_KEY_COMMENT="server-$(hostname)"
ALLOW_HTTP=0
ALLOW_HTTPS=0
ALLOW_PORTS=()

usage() {
  cat <<'USAGE'
Usage: ./bootstrap.sh [COMMANDS] [GLOBAL FLAGS] [OPTIONS]

Ubuntu/Debian bootstrap helper. Run one or more commands explicitly. Running
without arguments prints this help and exits without changing the system.

Commands:
  --all                 Run base packages, Docker, SSH key, Git identity,
                        firewall, security hardening, and check mode.
  --check               Check OS, apt, root/sudo, git, Docker, Docker Compose,
                        Docker service, Git identity, SSH public key, UFW,
                        and fail2ban.
  --docker              Install/configure Docker from the official repository.
  --git                 Configure global git user.name and user.email.
  --ssh-key             Create or show an ed25519 SSH public key.
  --firewall            Install and enable UFW with SSH allowed.
  --security            Install fail2ban, unattended-upgrades, and needrestart.

Global flags:
  --dry-run             Print commands that would run without executing them.
  --yes, -y             Assume yes for package manager prompts.
  --skip-upgrade        Skip apt upgrade during base package installation.
  --help                Show this help and exit without changes.

Git options:
  --git-name NAME       Set git config --global user.name.
  --git-email EMAIL     Set git config --global user.email.
                        GIT_NAME and GIT_EMAIL environment variables are also
                        supported.

SSH key options:
  --ssh-key-path PATH   SSH private key path (default: ~/.ssh/id_ed25519).
  --ssh-key-comment TXT SSH key comment (default: server-<hostname>).

Firewall options:
  --allow-http          Allow TCP port 80 in UFW (requires --firewall or --all).
  --allow-https         Allow TCP port 443 in UFW (requires --firewall or --all).
  --allow-port PORT/PROTO
                        Allow a custom UFW port rule, repeatable. Examples:
                        8080/tcp, 53/udp.

Examples:
  ./bootstrap.sh --help
  ./bootstrap.sh --check
  ./bootstrap.sh --all --yes
  ./bootstrap.sh --docker --skip-upgrade
  GIT_NAME="Your Name" GIT_EMAIL="you@example.com" ./bootstrap.sh --git
  ./bootstrap.sh --ssh-key --ssh-key-path ~/.ssh/deploy_key --ssh-key-comment deploy
  ./bootstrap.sh --firewall --allow-http --allow-https --allow-port 8080/tcp
  ./bootstrap.sh --all --dry-run --allow-http
USAGE
}

require_root_or_sudo() {
  if [ "${EUID:-$(id -u)}" -ne 0 ] && ! need_cmd sudo; then
    err "Need root or sudo installed."
    exit 1
  fi
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf "Would run: %s\n" "$*"
    return 0
  fi

  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    bash -lc "$*"
  else
    sudo bash -lc "$*"
  fi
}

run_user() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf "Would run: %s\n" "$*"
    return 0
  fi
  bash -lc "$*"
}

apt_yes_flag() {
  if [ "$ASSUME_YES" -eq 1 ]; then
    printf -- "-y"
  fi
}

ensure_apt() {
  need_cmd apt || { err "This script requires apt (Ubuntu/Debian)."; exit 1; }
}

load_os_release() {
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
    OS_CODENAME="${VERSION_CODENAME:-}"
    if [ -z "$OS_CODENAME" ]; then
      OS_CODENAME="${UBUNTU_CODENAME:-}"
    fi
  else
    OS_ID=""
    OS_NAME="unknown"
    OS_CODENAME=""
  fi
}

get_docker_repo_info() {
  load_os_release
  case "$OS_ID" in
    ubuntu|debian)
      DOCKER_REPO_OS="$OS_ID"
      ;;
    *)
      err "Unsupported distribution for Docker repo: ${OS_NAME} (${OS_ID:-unknown})."
      err "Only Ubuntu and Debian are supported by this script."
      exit 1
      ;;
  esac

  if [ -z "$OS_CODENAME" ]; then
    OS_CODENAME="$(lsb_release -cs 2>/dev/null || true)"
  fi
  if [ -z "$OS_CODENAME" ]; then
    err "Cannot determine distro codename from /etc/os-release or lsb_release."
    exit 1
  fi

  DOCKER_REPO_URL="https://download.docker.com/linux/${DOCKER_REPO_OS}"
}

install_base_packages() {
  bold "Updating system & installing base packages..."
  run "apt update"
  if [ "$SKIP_UPGRADE" -eq 1 ]; then
    warn "Skipping apt upgrade because --skip-upgrade was provided."
  else
    run "apt $(apt_yes_flag) upgrade"
  fi
  run "apt $(apt_yes_flag) install git ca-certificates curl gnupg lsb-release openssh-client"
  ok "Base packages installed."
}

install_docker() {
  get_docker_repo_info
  info "Distro: ${OS_NAME}"
  info "Codename: ${OS_CODENAME}"
  info "Docker repository: ${DOCKER_REPO_URL}"

  if need_cmd docker && docker --version >/dev/null 2>&1; then
    ok "Docker already installed: $(docker --version | head -n1)"
    if docker compose version >/dev/null 2>&1; then
      ok "Docker Compose plugin preserved: $(docker compose version | head -n1)"
    else
      warn "Docker present, but docker compose plugin not detected. Installing plugin package."
      run "apt update"
      run "apt $(apt_yes_flag) install docker-compose-plugin"
    fi
    return 0
  fi

  bold "Installing Docker (official repo)..."
  run "apt update"
  run "apt $(apt_yes_flag) install ca-certificates curl gnupg lsb-release"
  run "install -m 0755 -d /etc/apt/keyrings"
  run "curl -fsSL '${DOCKER_REPO_URL}/gpg' | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
  run "chmod a+r /etc/apt/keyrings/docker.gpg"
  run "echo 'deb [arch='\"\$(dpkg --print-architecture)\"' signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_REPO_URL} ${OS_CODENAME} stable' > /etc/apt/sources.list.d/docker.list"
  run "apt update"
  run "apt $(apt_yes_flag) install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

  if need_cmd docker; then ok "Docker installed: $(docker --version | head -n1)"; fi
  if need_cmd docker && docker compose version >/dev/null 2>&1; then ok "Docker Compose plugin: $(docker compose version | head -n1)"; fi
}

ensure_docker_running() {
  bold "Checking Docker daemon..."
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
  if [ -S /var/run/docker.sock ]; then ok "Docker socket exists: /var/run/docker.sock"; else warn "Docker socket not found yet."; fi
  if docker info >/dev/null 2>&1; then ok "Docker daemon responding correctly."; else warn "Docker daemon not responding for current user."; fi
}

maybe_add_user_to_docker_group() {
  local target_user="${SUDO_USER:-${USER:-}}"
  [ -n "$target_user" ] || return 0
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
  local key_path_expanded
  key_path_expanded="$(eval printf '%s' \"$SSH_KEY_PATH\")"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf "Would run: mkdir -p %s\n" "$(shell_quote "$(dirname "$key_path_expanded")")"
    printf "Would run: chmod 700 %s\n" "$(shell_quote "$(dirname "$key_path_expanded")")"
  else
    mkdir -p "$(dirname "$key_path_expanded")"
    chmod 700 "$(dirname "$key_path_expanded")"
  fi

  if [ -f "$key_path_expanded" ]; then
    ok "SSH key already exists: $key_path_expanded"
  else
    run_user "ssh-keygen -t ed25519 -C $(shell_quote "$SSH_KEY_COMMENT") -f $(shell_quote "$key_path_expanded") -N ''"
    if [ "$DRY_RUN" -eq 1 ]; then
      info "SSH key would be created: $key_path_expanded"
    else
      ok "SSH key created: $key_path_expanded"
    fi
  fi

  if [ "$DRY_RUN" -eq 0 ] && need_cmd ssh-agent; then eval "$(ssh-agent -s)" >/dev/null 2>&1 || true; fi
  if [ "$DRY_RUN" -eq 0 ] && need_cmd ssh-add; then ssh-add "$key_path_expanded" >/dev/null 2>&1 || true; fi

  bold "Public key (add this in GitHub → Settings → SSH and GPG keys):"
  echo "----------------------------------------------------------------"
  if [ -f "${key_path_expanded}.pub" ]; then cat "${key_path_expanded}.pub"; else warn "Public key not present yet (dry-run or key generation failed)."; fi
  echo "----------------------------------------------------------------"
  warn "After adding the key in GitHub, run: ssh -T git@github.com"
}

configure_git_identity() {
  bold "Configure global git identity (user.name / user.email)"
  need_cmd git || { err "git is not installed. Run --all or install git first."; exit 1; }

  local current_name current_email name email
  current_name="$(git config --global user.name || true)"
  current_email="$(git config --global user.email || true)"
  name="${GIT_NAME:-$current_name}"
  email="${GIT_EMAIL:-$current_email}"

  if [ -z "$name" ] && [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then read -r -p "Enter git user.name: " name; fi
  if [ -z "$email" ] && [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then read -r -p "Enter git user.email: " email; fi

  if [ -z "$name" ] || [ -z "$email" ]; then
    warn "Skipped git identity (missing name or email). Use --git-name/--git-email or GIT_NAME/GIT_EMAIL."
    return 0
  fi

  run_user "git config --global user.name $(shell_quote "$name")"
  run_user "git config --global user.email $(shell_quote "$email")"
  if [ "$DRY_RUN" -eq 1 ]; then
    info "Git identity would be configured:"
  else
    ok "Git identity configured:"
  fi
  echo "  user.name  = $name"
  echo "  user.email = $email"
}

configure_firewall() {
  bold "Configuring UFW firewall..."
  require_root_or_sudo
  ensure_apt
  run "apt update"
  run "apt $(apt_yes_flag) install ufw"
  run "ufw allow OpenSSH || ufw allow ssh"
  if [ "$ALLOW_HTTP" -eq 1 ]; then run "ufw allow 80/tcp"; fi
  if [ "$ALLOW_HTTPS" -eq 1 ]; then run "ufw allow 443/tcp"; fi
  local port
  for port in "${ALLOW_PORTS[@]}"; do run "ufw allow $(shell_quote "$port")"; done
  run "ufw --force enable"
  run "ufw status verbose"
}

configure_security() {
  bold "Installing security packages..."
  require_root_or_sudo
  ensure_apt
  run "apt update"
  run "apt $(apt_yes_flag) install fail2ban unattended-upgrades needrestart"
  if need_cmd systemctl; then
    run "systemctl enable --now fail2ban"
  else
    warn "systemctl not found. Skipping fail2ban service enable/start."
  fi
  run "service fail2ban status || systemctl status fail2ban --no-pager -n 5 || true"
}

check_item() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else warn "$label"; fi
}

check_mode() {
  bold "System check"
  load_os_release
  if [ -r /etc/os-release ]; then ok "OS: ${OS_NAME} (${OS_ID:-unknown} ${OS_CODENAME:-unknown})"; else warn "OS: /etc/os-release not found"; fi
  check_item "apt: available" need_cmd apt
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then ok "root/sudo: running as root"; elif need_cmd sudo; then ok "root/sudo: sudo available"; else warn "root/sudo: not root and sudo unavailable"; fi
  if need_cmd git; then ok "git: $(git --version)"; else warn "git: not found"; fi
  if need_cmd docker; then ok "Docker: $(docker --version | head -n1)"; else warn "Docker: not found"; fi
  if need_cmd docker && docker compose version >/dev/null 2>&1; then ok "Docker Compose: $(docker compose version | head -n1)"; else warn "Docker Compose: not found"; fi
  if need_cmd systemctl; then check_item "Docker service: active" systemctl is-active --quiet docker; else warn "Docker service: systemctl not found"; fi
  local git_name git_email
  git_name="$(git config --global user.name 2>/dev/null || true)"
  git_email="$(git config --global user.email 2>/dev/null || true)"
  if [ -n "$git_name" ] && [ -n "$git_email" ]; then ok "Git identity: ${git_name} <${git_email}>"; else warn "Git identity: incomplete or missing"; fi
  local key_path_expanded
  key_path_expanded="$(eval printf '%s' \"$SSH_KEY_PATH\")"
  if [ -f "${key_path_expanded}.pub" ]; then ok "SSH public key: ${key_path_expanded}.pub"; else warn "SSH public key: missing (${key_path_expanded}.pub)"; fi
  if need_cmd ufw; then ok "UFW: $(ufw status 2>/dev/null | head -n1)"; else warn "UFW: not installed"; fi
  if need_cmd fail2ban-client; then ok "fail2ban: installed"; else warn "fail2ban: not installed"; fi
}

validate_port_rule() {
  if [[ ! "$1" =~ ^[0-9]+/(tcp|udp)$ ]]; then
    err "--allow-port must use PORT/PROTO, for example 8080/tcp or 53/udp"
    exit 1
  fi
}

parse_args() {
  if [ "$#" -eq 0 ]; then
    usage
    exit 0
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help) usage; exit 0 ;;
      --dry-run) DRY_RUN=1 ;;
      --yes|-y) ASSUME_YES=1 ;;
      --skip-upgrade) SKIP_UPGRADE=1 ;;
      --all) RUN_ALL=1 ;;
      --check) RUN_CHECK=1 ;;
      --docker) RUN_DOCKER=1 ;;
      --git) RUN_GIT=1 ;;
      --ssh-key) RUN_SSH_KEY=1 ;;
      --firewall) RUN_FIREWALL=1 ;;
      --security) RUN_SECURITY=1 ;;
      --git-name) shift; [ "$#" -gt 0 ] || { err "--git-name requires a value"; exit 1; }; GIT_NAME="$1" ;;
      --git-email) shift; [ "$#" -gt 0 ] || { err "--git-email requires a value"; exit 1; }; GIT_EMAIL="$1" ;;
      --ssh-key-path) shift; [ "$#" -gt 0 ] || { err "--ssh-key-path requires a value"; exit 1; }; SSH_KEY_PATH="$1" ;;
      --ssh-key-comment) shift; [ "$#" -gt 0 ] || { err "--ssh-key-comment requires a value"; exit 1; }; SSH_KEY_COMMENT="$1" ;;
      --allow-http) ALLOW_HTTP=1 ;;
      --allow-https) ALLOW_HTTPS=1 ;;
      --allow-port) shift; [ "$#" -gt 0 ] || { err "--allow-port requires PORT/PROTO"; exit 1; }; validate_port_rule "$1"; ALLOW_PORTS+=("$1") ;;
      *) err "Unknown option: $1"; echo; usage; exit 1 ;;
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
    configure_firewall
    configure_security
    check_mode
    bold "Done."
    return 0
  fi

  if [ "$RUN_DOCKER" -eq 1 ]; then require_root_or_sudo; ensure_apt; install_docker; ensure_docker_running; maybe_add_user_to_docker_group; fi
  if [ "$RUN_SSH_KEY" -eq 1 ]; then setup_github_ssh_key; fi
  if [ "$RUN_GIT" -eq 1 ]; then configure_git_identity; fi
  if [ "$RUN_FIREWALL" -eq 1 ]; then configure_firewall; fi
  if [ "$RUN_SECURITY" -eq 1 ]; then configure_security; fi
  if [ "$RUN_CHECK" -eq 1 ]; then check_mode; fi
  bold "Done."
}

parse_args "$@"
main
