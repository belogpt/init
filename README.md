# Server Bootstrap

`bootstrap.sh` — Bash-скрипт для первичной настройки Ubuntu/Debian-сервера через явные CLI-команды. Скрипт помогает установить базовые пакеты, Docker, Docker Compose plugin, настроить Git identity, создать SSH-ключ для GitHub, включить UFW firewall и установить базовые security-пакеты.

> Запуск без аргументов безопасен: скрипт открывает интерактивное меню, сначала предлагает выбрать язык, а затем позволяет запускать отдельные функции или весь bootstrap. Системные действия требуют отдельного подтверждения.


## Что умеет приложение

Это приложение — CLI-помощник для быстрого и контролируемого bootstrap Ubuntu/Debian-сервера. Его можно запускать как интерактивно через меню, так и командами с флагами для автоматизации.

Основные возможности:

- **Интерактивное меню**: при запуске `./bootstrap.sh` без аргументов приложение показывает выбор языка и меню действий, где можно включать `dry-run`, `--yes`, `skip-upgrade`, HTTP/HTTPS и запускать отдельные сценарии.
- **Двухъязычный интерфейс**: поддерживает русский и английский язык для меню, справки и CLI-сообщений; язык выбирается через `--lang ru|en` или переменные `BOOTSTRAP_LANG`/`BOOTSTRAP_LANGUAGE`.
- **Безопасный предварительный просмотр**: режим `--dry-run` печатает системные команды, которые были бы выполнены, но не меняет сервер.
- **Полный bootstrap пустого сервера**: команда `--all` последовательно устанавливает базовые пакеты, Docker, SSH-ключ, Git identity, firewall, security-пакеты и запускает проверку.
- **Проверка состояния сервера**: команда `--check` показывает статус ОС, `apt`, root/sudo, Git, Docker, Docker Compose plugin, Docker service, Git identity, SSH public key, UFW и fail2ban.
- **Установка Docker из официального репозитория**: приложение определяет Ubuntu/Debian и codename, подключает официальный Docker apt repository, устанавливает Docker Engine, Buildx и Docker Compose plugin, запускает/включает Docker service и добавляет пользователя в группу `docker`.
- **Настройка Git identity**: команда `--git` задаёт глобальные `git config --global user.name` и `user.email` из флагов, переменных окружения, текущих настроек Git или интерактивного ввода.
- **SSH-ключ для GitHub**: команда `--ssh-key` создаёт или показывает ed25519-ключ, добавляет его в `ssh-agent` при возможности и печатает публичный ключ для GitHub.
- **Firewall через UFW**: команда `--firewall` устанавливает и включает UFW, разрешает SSH, а также опционально открывает HTTP, HTTPS и пользовательские порты через `--allow-port PORT/PROTO`.
- **Базовое security hardening**: команда `--security` устанавливает `fail2ban`, `unattended-upgrades`, `needrestart` и включает `fail2ban`, если доступен `systemctl`.
- **Гибкая автоматизация**: команды можно комбинировать, например `--docker --git --ssh-key`, а флаги `--yes` и `--skip-upgrade` помогают запускать сценарии в неинтерактивных средах.

## Quick start

```bash
chmod +x bootstrap.sh
./bootstrap.sh          # интерактивное меню с выбором языка
./bootstrap.sh --help
./bootstrap.sh --check
./bootstrap.sh --all --yes
```

Для предварительного просмотра действий используйте dry-run:

```bash
./bootstrap.sh --all --dry-run --allow-http --allow-https
```

## Language / Язык интерфейса

CLI поддерживает русский и английский язык. Выбор доступен двумя способами:

```bash
./bootstrap.sh --lang ru --help
./bootstrap.sh --lang en --check
BOOTSTRAP_LANG=ru ./bootstrap.sh --check
BOOTSTRAP_LANG=en ./bootstrap.sh --all --dry-run
```

Если язык не указан, скрипт пытается выбрать русский для `ru*` locale (`LANG`, `LC_ALL`, `LC_MESSAGES`) и английский во всех остальных случаях. Значение `--lang` имеет приоритет над `BOOTSTRAP_LANG`/`BOOTSTRAP_LANGUAGE`.

The CLI supports Russian and English. Use `--lang ru|en` for a one-off run or `BOOTSTRAP_LANG=ru|en` as the default environment setting.


## Интерактивный интерфейс

Запустите скрипт без аргументов, чтобы открыть человекочитаемое меню:

```bash
./bootstrap.sh
```

В самом начале меню предлагает выбрать язык интерфейса: русский или английский. После этого можно выбрать действие цифрой:

- запустить всё для пустого сервера;
- проверить систему;
- установить/настроить Docker;
- настроить Git identity;
- создать или показать SSH-ключ для GitHub;
- настроить UFW firewall;
- установить security-пакеты.

В меню также есть переключатели `dry-run`, `--yes`, `skip-upgrade`, разрешение HTTP и HTTPS. Перед действиями, которые меняют систему, скрипт дополнительно спрашивает подтверждение.

Командный режим с флагами продолжает работать как раньше, например `./bootstrap.sh --check` или `./bootstrap.sh --all --yes`.

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
| `--lang ru\|en` | Выбрать язык CLI-сообщений и help для текущего запуска. |

## Git options

Git identity можно передать флагами:

```bash
./bootstrap.sh --git --git-name "Your Name" --git-email "you@example.com"
```

Или переменными окружения (`BOOTSTRAP_LANG` также можно использовать независимо для языка интерфейса):

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
BOOTSTRAP_LANG=ru ./bootstrap.sh --check
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

### Запуск без аргументов открывает меню

Это ожидаемое поведение. Запуск:

```bash
./bootstrap.sh
```

показывает выбор языка и интерактивное меню. Если нужен только текст справки без меню, используйте:

```bash
./bootstrap.sh --help
```

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
