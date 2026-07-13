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

LANG_CHOICE="${BOOTSTRAP_LANG:-${BOOTSTRAP_LANGUAGE:-auto}}"
LANG_RESOLVED="en"

resolve_language() {
  case "${LANG_CHOICE,,}" in
    ru|rus|russian) LANG_RESOLVED="ru" ;;
    en|eng|english) LANG_RESOLVED="en" ;;
    auto|"")
      case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
        ru*|RU*) LANG_RESOLVED="ru" ;;
        *) LANG_RESOLVED="en" ;;
      esac
      ;;
    *)
      printf "❌ Unsupported language: %s (use ru or en)\n" "$LANG_CHOICE" >&2
      exit 1
      ;;
  esac
}

preselect_language_from_args() {
  local arg
  while [ "$#" -gt 0 ]; do
    arg="$1"
    shift
    if [ "$arg" = "--lang" ]; then
      [ "$#" -gt 0 ] || { err "--lang requires ru or en"; exit 1; }
      LANG_CHOICE="$1"
      return 0
    fi
  done
}

msg() {
  local key="$1"
  case "$LANG_RESOLVED:$key" in
    ru:need_root) printf "Нужен запуск от root или установленный sudo." ;;
    ru:apt_required) printf "Для работы скрипта нужен apt (Ubuntu/Debian)." ;;
    ru:skip_upgrade) printf "Пропускаю apt upgrade, потому что передан --skip-upgrade." ;;
    ru:base_installing) printf "Обновление системы и установка базовых пакетов..." ;;
    ru:base_installed) printf "Базовые пакеты установлены." ;;
    ru:unsupported_distro) printf "Неподдерживаемый дистрибутив для Docker repo: %s (%s)." "$2" "$3" ;;
    ru:ubuntu_debian_only) printf "Скрипт поддерживает только Ubuntu и Debian." ;;
    ru:no_codename) printf "Не удалось определить codename дистрибутива через /etc/os-release или lsb_release." ;;
    ru:distro) printf "Дистрибутив: %s" "$2" ;;
    ru:codename) printf "Codename: %s" "$2" ;;
    ru:docker_repo) printf "Docker repository: %s" "$2" ;;
    ru:docker_installed) printf "Docker уже установлен: %s" "$2" ;;
    ru:compose_preserved) printf "Docker Compose plugin сохранён: %s" "$2" ;;
    ru:compose_missing) printf "Docker установлен, но docker compose plugin не найден. Устанавливаю plugin package." ;;
    ru:docker_installing) printf "Установка Docker из официального репозитория..." ;;
    ru:docker_daemon_check) printf "Проверка Docker daemon..." ;;
    ru:no_systemctl_docker) printf "systemctl не найден. Пропускаю управление Docker service." ;;
    ru:docker_running) printf "Docker service запущен." ;;
    ru:docker_starting) printf "Docker service не запущен. Запускаю..." ;;
    ru:docker_socket_ok) printf "Docker socket существует: /var/run/docker.sock" ;;
    ru:docker_socket_missing) printf "Docker socket пока не найден." ;;
    ru:docker_responding) printf "Docker daemon отвечает корректно." ;;
    ru:docker_not_responding) printf "Docker daemon не отвечает для текущего пользователя." ;;
    ru:user_in_group) printf "Пользователь '%s' уже в группе docker." "$2" ;;
    ru:add_user_group) printf "Добавление пользователя '%s' в группу docker..." "$2" ;;
    ru:relogin_required) printf "Добавлено. Для применения группы может потребоваться перелогиниться." ;;
    ru:ssh_setup) printf "Настройка GitHub SSH key (ed25519)..." ;;
    ru:ssh_exists) printf "SSH key уже существует: %s" "$2" ;;
    ru:ssh_would_create) printf "SSH key был бы создан: %s" "$2" ;;
    ru:ssh_created) printf "SSH key создан: %s" "$2" ;;
    ru:public_key_title) printf "Public key (добавьте в GitHub → Settings → SSH and GPG keys):" ;;
    ru:public_key_missing) printf "Public key пока отсутствует (dry-run или ошибка генерации)." ;;
    ru:ssh_after) printf "После добавления ключа в GitHub выполните: ssh -T git@github.com" ;;
    ru:git_config_title) printf "Настройка глобальной Git identity (user.name / user.email)" ;;
    ru:git_missing) printf "git не установлен. Запустите --all или установите git." ;;
    ru:git_prompt_name) printf "Введите git user.name: " ;;
    ru:git_prompt_email) printf "Введите git user.email: " ;;
    ru:git_skipped) printf "Git identity пропущена (нет name или email). Используйте --git-name/--git-email или GIT_NAME/GIT_EMAIL." ;;
    ru:git_would_configure) printf "Git identity была бы настроена:" ;;
    ru:git_configured) printf "Git identity настроена:" ;;
    ru:firewall_config) printf "Настройка UFW firewall..." ;;
    ru:security_install) printf "Установка security-пакетов..." ;;
    ru:no_systemctl_fail2ban) printf "systemctl не найден. Пропускаю enable/start для fail2ban." ;;
    ru:system_check) printf "Проверка системы" ;;
    ru:unknown_option) printf "Неизвестная опция: %s" "$2" ;;
    ru:done) printf "Готово." ;;
    *)
      case "$key" in
        need_root) printf "Need root or sudo installed." ;;
        apt_required) printf "This script requires apt (Ubuntu/Debian)." ;;
        skip_upgrade) printf "Skipping apt upgrade because --skip-upgrade was provided." ;;
        base_installing) printf "Updating system & installing base packages..." ;;
        base_installed) printf "Base packages installed." ;;
        unsupported_distro) printf "Unsupported distribution for Docker repo: %s (%s)." "$2" "$3" ;;
        ubuntu_debian_only) printf "Only Ubuntu and Debian are supported by this script." ;;
        no_codename) printf "Cannot determine distro codename from /etc/os-release or lsb_release." ;;
        distro) printf "Distro: %s" "$2" ;;
        codename) printf "Codename: %s" "$2" ;;
        docker_repo) printf "Docker repository: %s" "$2" ;;
        docker_installed) printf "Docker already installed: %s" "$2" ;;
        compose_preserved) printf "Docker Compose plugin preserved: %s" "$2" ;;
        compose_missing) printf "Docker present, but docker compose plugin not detected. Installing plugin package." ;;
        docker_installing) printf "Installing Docker (official repo)..." ;;
        docker_daemon_check) printf "Checking Docker daemon..." ;;
        no_systemctl_docker) printf "systemctl not found. Skipping docker service management." ;;
        docker_running) printf "Docker service is running." ;;
        docker_starting) printf "Docker service not running. Starting..." ;;
        docker_socket_ok) printf "Docker socket exists: /var/run/docker.sock" ;;
        docker_socket_missing) printf "Docker socket not found yet." ;;
        docker_responding) printf "Docker daemon responding correctly." ;;
        docker_not_responding) printf "Docker daemon not responding for current user." ;;
        user_in_group) printf "User '%s' already in docker group." "$2" ;;
        add_user_group) printf "Adding user '%s' to docker group..." "$2" ;;
        relogin_required) printf "Added. Re-login may be required for group changes to take effect." ;;
        ssh_setup) printf "GitHub SSH key setup (ed25519)..." ;;
        ssh_exists) printf "SSH key already exists: %s" "$2" ;;
        ssh_would_create) printf "SSH key would be created: %s" "$2" ;;
        ssh_created) printf "SSH key created: %s" "$2" ;;
        public_key_title) printf "Public key (add this in GitHub → Settings → SSH and GPG keys):" ;;
        public_key_missing) printf "Public key not present yet (dry-run or key generation failed)." ;;
        ssh_after) printf "After adding the key in GitHub, run: ssh -T git@github.com" ;;
        git_config_title) printf "Configure global git identity (user.name / user.email)" ;;
        git_missing) printf "git is not installed. Run --all or install git first." ;;
        git_prompt_name) printf "Enter git user.name: " ;;
        git_prompt_email) printf "Enter git user.email: " ;;
        git_skipped) printf "Skipped git identity (missing name or email). Use --git-name/--git-email or GIT_NAME/GIT_EMAIL." ;;
        git_would_configure) printf "Git identity would be configured:" ;;
        git_configured) printf "Git identity configured:" ;;
        firewall_config) printf "Configuring UFW firewall..." ;;
        security_install) printf "Installing security packages..." ;;
        no_systemctl_fail2ban) printf "systemctl not found. Skipping fail2ban service enable/start." ;;
        system_check) printf "System check" ;;
        unknown_option) printf "Unknown option: %s" "$2" ;;
        done) printf "Done." ;;
      esac
      ;;
  esac
}

tr_line() { msg "$@"; printf '\n'; }

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
  if [ "$LANG_RESOLVED" = "ru" ]; then
    cat <<'USAGE_RU'
Использование: ./bootstrap.sh [КОМАНДЫ] [ГЛОБАЛЬНЫЕ ФЛАГИ] [ОПЦИИ]

Bootstrap-helper для Ubuntu/Debian. Запускайте одну или несколько команд явно.
Запуск без аргументов показывает эту справку и завершается без изменений.

Команды:
  --all                 Выполнить base packages, Docker, SSH key, Git identity,
                        firewall, security hardening и check mode.
  --check               Проверить ОС, apt, root/sudo, git, Docker, Docker Compose,
                        Docker service, Git identity, SSH public key, UFW и fail2ban.
  --docker              Установить/настроить Docker из официального репозитория.
  --git                 Настроить global git user.name и user.email.
  --ssh-key             Создать или показать ed25519 SSH public key.
  --firewall            Установить и включить UFW с разрешённым SSH.
  --security            Установить fail2ban, unattended-upgrades и needrestart.

Глобальные флаги:
  --dry-run             Показать команды без выполнения.
  --yes, -y             Автоматически подтверждать package manager prompts.
  --skip-upgrade        Пропустить apt upgrade при установке base packages.
  --lang ru|en          Выбрать язык CLI-сообщений и help.
  --help                Показать справку и выйти без изменений.

Переменные окружения:
  BOOTSTRAP_LANG=ru|en  Язык по умолчанию для CLI-сообщений и help.
  GIT_NAME, GIT_EMAIL   Значения для Git identity.

Git options:
  --git-name NAME       Установить git config --global user.name.
  --git-email EMAIL     Установить git config --global user.email.

SSH key options:
  --ssh-key-path PATH   Путь приватного SSH key (default: ~/.ssh/id_ed25519).
  --ssh-key-comment TXT Комментарий SSH key (default: server-<hostname>).

Firewall options:
  --allow-http          Разрешить TCP port 80 в UFW.
  --allow-https         Разрешить TCP port 443 в UFW.
  --allow-port PORT/PROTO
                        Разрешить custom UFW port rule, можно повторять.
                        Примеры: 8080/tcp, 53/udp.

Примеры:
  ./bootstrap.sh --help
  ./bootstrap.sh --lang ru --check
  BOOTSTRAP_LANG=en ./bootstrap.sh --all --yes
  ./bootstrap.sh --firewall --allow-http --allow-https --allow-port 8080/tcp
  ./bootstrap.sh --all --dry-run --allow-http
USAGE_RU
  else
    cat <<'USAGE_EN'
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
  --lang ru|en          Select CLI output/help language.
  --help                Show this help and exit without changes.

Environment variables:
  BOOTSTRAP_LANG=ru|en  Default CLI output/help language.
  GIT_NAME, GIT_EMAIL   Values for Git identity.

Git options:
  --git-name NAME       Set git config --global user.name.
  --git-email EMAIL     Set git config --global user.email.

SSH key options:
  --ssh-key-path PATH   SSH private key path (default: ~/.ssh/id_ed25519).
  --ssh-key-comment TXT SSH key comment (default: server-<hostname>).

Firewall options:
  --allow-http          Allow TCP port 80 in UFW.
  --allow-https         Allow TCP port 443 in UFW.
  --allow-port PORT/PROTO
                        Allow a custom UFW port rule, repeatable. Examples:
                        8080/tcp, 53/udp.

Examples:
  ./bootstrap.sh --help
  ./bootstrap.sh --lang ru --check
  BOOTSTRAP_LANG=en ./bootstrap.sh --all --yes
  ./bootstrap.sh --firewall --allow-http --allow-https --allow-port 8080/tcp
  ./bootstrap.sh --all --dry-run --allow-http
USAGE_EN
  fi
}

require_root_or_sudo() {
  if [ "${EUID:-$(id -u)}" -ne 0 ] && ! need_cmd sudo; then
    err "$(tr_line need_root)"
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
  need_cmd apt || { err "$(tr_line apt_required)"; exit 1; }
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
      err "$(tr_line unsupported_distro "$OS_NAME" "${OS_ID:-unknown}")"
      err "$(tr_line ubuntu_debian_only)"
      exit 1
      ;;
  esac

  if [ -z "$OS_CODENAME" ]; then
    OS_CODENAME="$(lsb_release -cs 2>/dev/null || true)"
  fi
  if [ -z "$OS_CODENAME" ]; then
    err "$(tr_line no_codename)"
    exit 1
  fi

  DOCKER_REPO_URL="https://download.docker.com/linux/${DOCKER_REPO_OS}"
}

install_base_packages() {
  bold "$(tr_line base_installing)"
  run "apt update"
  if [ "$SKIP_UPGRADE" -eq 1 ]; then
    warn "$(tr_line skip_upgrade)"
  else
    run "apt $(apt_yes_flag) upgrade"
  fi
  run "apt $(apt_yes_flag) install git ca-certificates curl gnupg lsb-release openssh-client"
  ok "$(tr_line base_installed)"
}

install_docker() {
  get_docker_repo_info
  info "$(tr_line distro "$OS_NAME")"
  info "$(tr_line codename "$OS_CODENAME")"
  info "$(tr_line docker_repo "$DOCKER_REPO_URL")"

  if need_cmd docker && docker --version >/dev/null 2>&1; then
    ok "$(tr_line docker_installed "$(docker --version | head -n1)")"
    if docker compose version >/dev/null 2>&1; then
      ok "$(tr_line compose_preserved "$(docker compose version | head -n1)")"
    else
      warn "$(tr_line compose_missing)"
      run "apt update"
      run "apt $(apt_yes_flag) install docker-compose-plugin"
    fi
    return 0
  fi

  bold "$(tr_line docker_installing)"
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
  bold "$(tr_line docker_daemon_check)"
  if ! need_cmd systemctl; then
    warn "$(tr_line no_systemctl_docker)"
    return 0
  fi
  run "systemctl status docker --no-pager -n 5 || true"
  if run "systemctl is-active --quiet docker"; then
    ok "$(tr_line docker_running)"
  else
    warn "$(tr_line docker_starting)"
    run "systemctl start docker"
  fi
  run "systemctl enable docker"
  if [ -S /var/run/docker.sock ]; then ok "$(tr_line docker_socket_ok)"; else warn "$(tr_line docker_socket_missing)"; fi
  if docker info >/dev/null 2>&1; then ok "$(tr_line docker_responding)"; else warn "$(tr_line docker_not_responding)"; fi
}

maybe_add_user_to_docker_group() {
  local target_user="${SUDO_USER:-${USER:-}}"
  [ -n "$target_user" ] || return 0
  if id -nG "$target_user" 2>/dev/null | grep -qw docker; then
    ok "$(tr_line user_in_group "$target_user")"
    return 0
  fi
  bold "$(tr_line add_user_group "$target_user")"
  run "usermod -aG docker '$target_user'"
  ok "$(tr_line relogin_required)"
}

setup_github_ssh_key() {
  bold "$(tr_line ssh_setup)"
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
    ok "$(tr_line ssh_exists "$key_path_expanded")"
  else
    run_user "ssh-keygen -t ed25519 -C $(shell_quote "$SSH_KEY_COMMENT") -f $(shell_quote "$key_path_expanded") -N ''"
    if [ "$DRY_RUN" -eq 1 ]; then
      info "$(tr_line ssh_would_create "$key_path_expanded")"
    else
      ok "$(tr_line ssh_created "$key_path_expanded")"
    fi
  fi

  if [ "$DRY_RUN" -eq 0 ] && need_cmd ssh-agent; then eval "$(ssh-agent -s)" >/dev/null 2>&1 || true; fi
  if [ "$DRY_RUN" -eq 0 ] && need_cmd ssh-add; then ssh-add "$key_path_expanded" >/dev/null 2>&1 || true; fi

  bold "$(tr_line public_key_title)"
  echo "----------------------------------------------------------------"
  if [ -f "${key_path_expanded}.pub" ]; then cat "${key_path_expanded}.pub"; else warn "$(tr_line public_key_missing)"; fi
  echo "----------------------------------------------------------------"
  warn "$(tr_line ssh_after)"
}

configure_git_identity() {
  bold "$(tr_line git_config_title)"
  need_cmd git || { err "$(tr_line git_missing)"; exit 1; }

  local current_name current_email name email
  current_name="$(git config --global user.name || true)"
  current_email="$(git config --global user.email || true)"
  name="${GIT_NAME:-$current_name}"
  email="${GIT_EMAIL:-$current_email}"

  if [ -z "$name" ] && [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then read -r -p "$(msg git_prompt_name)" name; fi
  if [ -z "$email" ] && [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then read -r -p "$(msg git_prompt_email)" email; fi

  if [ -z "$name" ] || [ -z "$email" ]; then
    warn "$(tr_line git_skipped)"
    return 0
  fi

  run_user "git config --global user.name $(shell_quote "$name")"
  run_user "git config --global user.email $(shell_quote "$email")"
  if [ "$DRY_RUN" -eq 1 ]; then
    info "$(tr_line git_would_configure)"
  else
    ok "$(tr_line git_configured)"
  fi
  echo "  user.name  = $name"
  echo "  user.email = $email"
}

configure_firewall() {
  bold "$(tr_line firewall_config)"
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
  bold "$(tr_line security_install)"
  require_root_or_sudo
  ensure_apt
  run "apt update"
  run "apt $(apt_yes_flag) install fail2ban unattended-upgrades needrestart"
  if need_cmd systemctl; then
    run "systemctl enable --now fail2ban"
  else
    warn "$(tr_line no_systemctl_fail2ban)"
  fi
  run "service fail2ban status || systemctl status fail2ban --no-pager -n 5 || true"
}

check_item() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else warn "$label"; fi
}

check_mode() {
  bold "$(tr_line system_check)"
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
      --lang) shift; [ "$#" -gt 0 ] || { err "--lang requires ru or en"; exit 1; }; LANG_CHOICE="$1"; resolve_language ;;
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
      *) err "$(tr_line unknown_option "$1")"; echo; usage; exit 1 ;;
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
    bold "$(tr_line done)"
    return 0
  fi

  if [ "$RUN_DOCKER" -eq 1 ]; then require_root_or_sudo; ensure_apt; install_docker; ensure_docker_running; maybe_add_user_to_docker_group; fi
  if [ "$RUN_SSH_KEY" -eq 1 ]; then setup_github_ssh_key; fi
  if [ "$RUN_GIT" -eq 1 ]; then configure_git_identity; fi
  if [ "$RUN_FIREWALL" -eq 1 ]; then configure_firewall; fi
  if [ "$RUN_SECURITY" -eq 1 ]; then configure_security; fi
  if [ "$RUN_CHECK" -eq 1 ]; then check_mode; fi
  bold "$(tr_line done)"
}

preselect_language_from_args "$@"
resolve_language
parse_args "$@"
main
