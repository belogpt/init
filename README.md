# Server Init CLI

CLI для первичной настройки Ubuntu/Debian-сервера. Скрипт помогает подготовить сервер к работе с Git, Docker, GitHub SSH-ключами, UFW firewall и базовыми security-пакетами.

## Возможности

- Установка Git и базовых apt-пакетов.
- Установка Docker из официального Docker repository для Ubuntu/Debian.
- Установка Docker Compose plugin.
- Запуск и включение Docker service.
- Добавление текущего пользователя в группу `docker`.
- Создание GitHub SSH-ключа `ed25519`.
- Настройка глобального `git user.name` и `git user.email`.
- Диагностика готовности сервера через `--check`.
- Настройка UFW firewall.
- Установка базовых security-пакетов: `fail2ban`, `unattended-upgrades`, `needrestart`.
- Dry-run режим для просмотра действий без изменения системы.

## Быстрый старт

```bash
chmod +x bootstrap.sh
./bootstrap.sh --help
./bootstrap.sh --check
./bootstrap.sh --dry-run --all
./bootstrap.sh --all --skip-upgrade
```

## Команды

```bash
./bootstrap.sh --all
./bootstrap.sh --check
./bootstrap.sh --docker
./bootstrap.sh --git
./bootstrap.sh --ssh-key
./bootstrap.sh --firewall
./bootstrap.sh --security
```

### `--all`

Запускает рекомендуемый полный сценарий:

1. Установка базовых пакетов.
2. Установка Docker и Docker Compose plugin.
3. Запуск Docker service.
4. Добавление пользователя в группу `docker`.
5. Создание GitHub SSH-ключа.
6. Настройка Git identity.
7. Настройка UFW firewall.
8. Установка базовых security-пакетов.
9. Финальная диагностика.

### `--check`

Показывает отчет о состоянии сервера и ничего не меняет:

- ОС;
- наличие `apt`, `sudo`, `git`, `curl`;
- Docker и Docker Compose;
- статус Docker service;
- Git identity;
- наличие SSH public key;
- членство пользователя в группе `docker`;
- UFW/fail2ban status.

### `--docker`

Устанавливает Docker из официального репозитория Docker. Скрипт автоматически выбирает корректный repository URL для Ubuntu или Debian.

### `--git`

Настраивает глобальную Git identity.

```bash
./bootstrap.sh --git --git-name "Admin" --git-email "admin@example.com"
```

Также можно использовать переменные окружения:

```bash
GIT_NAME="Admin" GIT_EMAIL="admin@example.com" ./bootstrap.sh --git
```

### `--ssh-key`

Создает или показывает существующий SSH-ключ для GitHub.

```bash
./bootstrap.sh --ssh-key
./bootstrap.sh --ssh-key --ssh-key-comment "deploy@app-01"
./bootstrap.sh --ssh-key --ssh-key-path ~/.ssh/id_ed25519_github
```

### `--firewall`

Устанавливает и включает UFW. SSH разрешается всегда перед включением firewall.

```bash
./bootstrap.sh --firewall
./bootstrap.sh --firewall --allow-http --allow-https
./bootstrap.sh --firewall --allow-port 8080/tcp
```

### `--security`

Устанавливает базовые security-пакеты:

- `fail2ban`;
- `unattended-upgrades`;
- `needrestart`.

SSH hardening намеренно не выполняется этой командой, чтобы случайно не потерять доступ к серверу.

## Глобальные опции

```bash
-y, --yes
--dry-run
--skip-upgrade
-h, --help
```

### `--dry-run`

Показывает, какие команды были бы выполнены, но не меняет систему.

```bash
./bootstrap.sh --dry-run --all
./bootstrap.sh --dry-run --firewall --allow-http --allow-https
```

### `--skip-upgrade`

Выполняет `apt update`, но пропускает `apt upgrade`.

```bash
./bootstrap.sh --all --skip-upgrade
```

## Рекомендуемый порядок запуска на новом сервере

```bash
./bootstrap.sh --check
./bootstrap.sh --dry-run --all --skip-upgrade
./bootstrap.sh --all --skip-upgrade
```

После установки Docker и добавления пользователя в группу `docker` может потребоваться перелогиниться или выполнить:

```bash
newgrp docker
```

## Troubleshooting

### Docker permission denied

Если Docker установлен, но текущий пользователь не может выполнять `docker ps`, перелогиньтесь или выполните:

```bash
newgrp docker
```

### SSH key already exists

Скрипт не перезаписывает существующий ключ. Если ключ уже есть, он будет показан как существующий.

### Unsupported distro

Установка Docker поддерживает Ubuntu и Debian. Для других дистрибутивов скрипт завершится с понятной ошибкой.

### Docker service is not running

Проверьте статус:

```bash
sudo systemctl status docker --no-pager
sudo systemctl restart docker
```

## Проверки разработки

```bash
bash -n bootstrap.sh
shellcheck bootstrap.sh
```
