# Init — VPS bootstrap tool

`init` is a modular Bash tool for preparing Ubuntu/Debian VPS hosts. It can be used as a normal CLI (`check`, `plan`, `apply`, `modules`, `config`) or through an interactive menu.

## Quick start

```bash
./init menu
./init menu --lang ru
./init menu --lang en
INIT_LANG=ru ./init
LANG=ru_RU.UTF-8 ./init
NO_COLOR=1 ./init
INIT_ASCII_ONLY=1 ./init
```

## Language and localization

The interactive menu supports English and Russian without `gettext` or external UI dependencies.

Language sources are applied in this order:

1. default `auto`;
2. environment `INIT_LANG`;
3. config key `language`;
4. CLI flag `--lang`;
5. language selected during the current menu session.

Supported values are:

```bash
--lang en
--lang ru
--lang auto
```

`auto` checks `LC_ALL`, then `LC_MESSAGES`, then `LANG`. Locales beginning with `ru` select Russian; everything else selects English. For example, `ru_RU.UTF-8` and `ru_UA.UTF-8` render the Russian menu, while `C.UTF-8` and `en_US.UTF-8` render English.

A saved config can include:

```ini
language=ru
```

The menu language can also be changed at runtime from **Language / Язык** and applies immediately.

## Interactive menu structure

The main menu is visually divided into sections:

```text
CHECK AND APPLY
  1) Check server
  2) Show plan
  3) Apply configuration

CONFIGURATION
  4) Select modules
  5) Edit configuration
  6) Show current configuration

PROJECT
  7) Available modules
  8) Help
  9) Save configuration
 10) Load configuration
 11) Language
 12) Exit
```

Russian mode uses the same structure:

```text
ПРОВЕРКА И ПРИМЕНЕНИЕ
  1) Проверить сервер
  2) Показать план
  3) Применить конфигурацию

НАСТРОЙКА
  4) Выбрать модули
  5) Изменить конфигурацию
  6) Показать текущую конфигурацию

ПРОЕКТ
  7) Доступные модули
  8) Справка
  9) Сохранить конфигурацию
 10) Загрузить конфигурацию
 11) Язык
 12) Выход
```

Each standalone menu screen clears before rendering when stdout is a TTY. Set `INIT_NO_CLEAR=1` to disable all screen clearing.

## UI behavior

- Common UI helpers centralize headers, sections, separators, menu rows, key/value rows, hints, and statuses.
- Menu rows and tables use `printf` field widths rather than tab-based alignment.
- The main screen shows a compact status summary: target user, selected module count, language, color mode, and module list.
- Flash messages show short success/warning/error/info notices once on the next screen.
- Invalid menu input no longer relies on short sleeps; it renders a readable flash error on redraw.

## Colors

The menu uses semantic colors when stdout is an interactive TTY:

- title: bold blue;
- section: bold;
- numbers: blue;
- success/configured/applied: green;
- warning/needs changes: yellow;
- failed/blocked: red;
- muted hints: gray.

Colors are disabled automatically for non-TTY output and JSON output, and manually by:

```bash
NO_COLOR=1 ./init menu
INIT_NO_COLOR=1 ./init menu
./init --no-color menu
```

ANSI color codes are never written to saved config files or JSON output.

## ASCII and Unicode

By default, the menu can use lightweight Unicode frames when the terminal supports them. For ASCII-only environments:

```bash
INIT_ASCII_ONLY=1 ./init menu
```

ASCII mode avoids Unicode box characters and uses plain `+`, `-`, and `|` style frames.

## Configuration examples

Save from the menu with **Save configuration** or create a file manually:

```ini
language=auto
target_user=deploy
git_name=Deploy User
git_email=deploy@example.com
ssh_key_path=~/.ssh/id_ed25519
upgrade=0
assume_yes=0
allow_http=1
allow_https=1
repair_permissions=0
force=0
modules=system,packages,docker,git,ssh_key,firewall,security
```

Then run:

```bash
./init plan --config server.conf
sudo ./init apply --config server.conf
```

`--lang` overrides the config language:

```bash
./init menu --config server.conf --lang en
```

## Temporary files and safety

Module execution output is captured through `mktemp` under `${TMPDIR:-/tmp}` and removed after use. The tool no longer uses predictable paths such as `/tmp/init_module_out`, `/tmp/init_pre`, `/tmp/init_apply`, or `/tmp/init_post`, so parallel runs do not overwrite one another.

## Development checks

```bash
bash -n init lib/*.sh modules/*.sh tests.sh tests_i18n.sh
shellcheck init lib/*.sh modules/*.sh tests.sh tests_i18n.sh
./tests.sh
./tests_i18n.sh
```
