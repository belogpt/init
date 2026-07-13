# Server Bootstrap

`bootstrap.sh` — Bash-скрипт для первичной настройки Ubuntu/Debian-сервера через явные CLI-команды. Скрипт помогает установить базовые пакеты, Docker, Docker Compose plugin, настроить Git identity, создать SSH-ключ для GitHub, включить UFW firewall и установить базовые security-пакеты.

> Запуск без аргументов безопасен: скрипт показывает help и завершает работу без изменений в системе.

## Quick start

```bash
chmod +x bootstrap.sh
./bootstrap.sh --help
./bootstrap.sh --check
./bootstrap.sh --all --yes
```

Для предварительного просмотра действий используйте dry-run:

```bash
./bootstrap.sh --all --dry-run --allow-http --allow-https
```

## Поддерживаемые системы

Скрипт рассчитан на системы с `apt`:

- Ubuntu;
- Debian.

Docker устанавливается из официального репозитория Docker. Дистрибутив и codename определяются через `/etc/os-release`, после чего выбирается один из URL:

- `https://download.docker.com/linux/ubuntu`;
- `https://download.docker.com/linux/debian`.

## Требования

- Bash;
- `root` или установленный `sudo` для системных операций;
- `apt`;
- интернет-доступ для загрузки пакетов и GPG-ключа Docker.

## Команды

| Команда | Назначение |
| --- | --- |
| `--help` | Показать справку и выйти без изменений. |
| `--all` | Выполнить полный сценарий: base packages, Docker, SSH key, Git identity, firewall, security и check. |
| `--check` | Проверить ОС, `apt`, root/sudo, Git, Docker, Docker Compose, Docker service, Git identity, SSH public key, UFW и fail2ban. |
| `--docker` | Установить/настроить Docker и сохранить текущую установку Docker Compose plugin, если она уже есть. |
| `--git` | Настроить глобальные `git config --global user.name` и `user.email`. |
| `--ssh-key` | Создать или показать ed25519 SSH-ключ. |
| `--firewall` | Установить и включить UFW, разрешив SSH. |
| `--security` | Установить `fail2ban`, `unattended-upgrades`, `needrestart` и включить `fail2ban` при наличии `systemctl`. |

Команды можно комбинировать:

```bash
./bootstrap.sh --docker --git --ssh-key
./bootstrap.sh --firewall --security --check
```

## Глобальные флаги

| Флаг | Назначение |
| --- | --- |
| `--dry-run` | Печатать команды без выполнения. |
| `--yes`, `-y` | Использовать неинтерактивный режим для пакетного менеджера. |
| `--skip-upgrade` | Выполнить `apt update`, но пропустить `apt upgrade`. |

## Git options

Git identity можно передать флагами:

```bash
./bootstrap.sh --git --git-name "Your Name" --git-email "you@example.com"
```

Или переменными окружения:

```bash
GIT_NAME="Your Name" GIT_EMAIL="you@example.com" ./bootstrap.sh --git
```

Если значения уже настроены, скрипт использует текущие `git config --global` значения. В неинтерактивной среде без имени или email настройка Git будет пропущена с предупреждением.

## SSH key options

По умолчанию ключ создаётся в `~/.ssh/id_ed25519` с комментарием `server-<hostname>`.

```bash
./bootstrap.sh --ssh-key
./bootstrap.sh --ssh-key --ssh-key-path ~/.ssh/deploy_key --ssh-key-comment deploy@example
```

После генерации добавьте публичный ключ (`*.pub`) в GitHub → Settings → SSH and GPG keys и проверьте доступ:

```bash
ssh -T git@github.com
```

## Docker

Команда:

```bash
./bootstrap.sh --docker
```

Делает следующее:

1. определяет Ubuntu/Debian через `/etc/os-release`;
2. выбирает корректный Docker repository URL;
3. выводит distro, codename и repo URL;
4. добавляет официальный Docker apt repository;
5. устанавливает `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`;
6. если Docker уже установлен, не переустанавливает его и сохраняет текущую установку Docker Compose plugin;
7. проверяет/запускает Docker service через `systemctl`, если он доступен;
8. добавляет пользователя в группу `docker`, если нужно.

После добавления пользователя в группу `docker` может потребоваться выйти из SSH-сессии и войти снова или выполнить:

```bash
newgrp docker
```

## Firewall

Команда firewall устанавливает `ufw`, разрешает SSH и включает firewall:

```bash
./bootstrap.sh --firewall
```

Дополнительные правила:

```bash
./bootstrap.sh --firewall --allow-http
./bootstrap.sh --firewall --allow-https
./bootstrap.sh --firewall --allow-port 8080/tcp --allow-port 53/udp
```

`--allow-port` можно повторять несколько раз. Формат значения: `PORT/PROTO`, например `3000/tcp` или `1194/udp`.

## Security

Команда:

```bash
./bootstrap.sh --security
```

Устанавливает:

- `fail2ban`;
- `unattended-upgrades`;
- `needrestart`.

Если доступен `systemctl`, скрипт выполняет `systemctl enable --now fail2ban`, затем выводит статус сервиса.

## Check mode

```bash
./bootstrap.sh --check
```

Проверяет:

- ОС и данные из `/etc/os-release`;
- наличие `apt`;
- запуск от root или наличие `sudo`;
- наличие `git`;
- наличие Docker;
- наличие Docker Compose plugin;
- статус Docker service;
- Git identity;
- наличие SSH public key;
- наличие и статус UFW;
- наличие fail2ban.

## Dry-run examples

Dry-run полезен перед запуском на production-сервере:

```bash
./bootstrap.sh --docker --dry-run
./bootstrap.sh --firewall --dry-run --allow-http --allow-https --allow-port 8080/tcp
./bootstrap.sh --security --dry-run
./bootstrap.sh --all --dry-run --skip-upgrade
```

Dry-run не выполняет системные команды, но показывает, что именно было бы запущено.

## Примеры

Полный bootstrap без upgrade:

```bash
./bootstrap.sh --all --yes --skip-upgrade
```

Только Git и SSH key:

```bash
./bootstrap.sh --git --git-name "Your Name" --git-email "you@example.com" --ssh-key
```

Docker + проверка:

```bash
./bootstrap.sh --docker --check
```

Firewall для web-сервера:

```bash
./bootstrap.sh --firewall --allow-http --allow-https
```

## Troubleshooting

### Запуск без аргументов ничего не делает

Это ожидаемое поведение. Запуск:

```bash
./bootstrap.sh
```

показывает help и завершает работу без изменений. Выберите явную команду, например `--check` или `--all`.

### `Need root or sudo installed.`

Системные операции требуют root-доступ. Запустите скрипт от `root` или установите `sudo`.

### `This script requires apt (Ubuntu/Debian).`

Скрипт предназначен для Ubuntu/Debian и совместимых систем с `apt`. Alpine, Fedora, CentOS, Arch Linux и другие системы без `apt` не поддерживаются.

### Docker repository не определяется

Проверьте наличие `/etc/os-release` и поля `VERSION_CODENAME`. Для Docker поддерживаются только `ID=ubuntu` и `ID=debian`.

### Docker установлен, но `docker info` не работает

Чаще всего текущий пользователь ещё не получил права группы `docker`. Выйдите из сессии и войдите снова или выполните:

```bash
newgrp docker
```

Также можно проверить сервис:

```bash
sudo systemctl status docker --no-pager
sudo systemctl restart docker
```

### `systemctl not found`

Такое бывает в минимальных контейнерах или окружениях без systemd. Скрипт пропустит управление сервисами Docker/fail2ban и выведет предупреждение.

### UFW может разорвать SSH-доступ

Скрипт перед включением UFW разрешает SSH через `ufw allow OpenSSH || ufw allow ssh`. На нестандартных SSH-портах заранее добавьте правило:

```bash
./bootstrap.sh --firewall --allow-port 2222/tcp
```

### Git identity не настроилась

Передайте значения явно:

```bash
./bootstrap.sh --git --git-name "Your Name" --git-email "you@example.com"
```

или через окружение:

```bash
GIT_NAME="Your Name" GIT_EMAIL="you@example.com" ./bootstrap.sh --git
```

## Проверка разработки

Перед коммитом полезно выполнить:

```bash
bash -n bootstrap.sh
shellcheck bootstrap.sh
```

`shellcheck` является опциональным: если он не установлен, достаточно зафиксировать это как ограничение окружения.
