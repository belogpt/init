# Modular VPS Init

`init` is a Bash-first, modular initial setup tool for Ubuntu/Debian VPS hosts. It is declarative: every module compares the current state with an explicit desired state, prints an exact plan, and applies only the missing changes.

## Command mode and menu mode

The ordinary CLI remains the best interface for automation, CI, and repeatable server bootstrap scripts:

```bash
./init help
./init version
./init modules
./init config
./init check [module...]
./init plan [module...]
sudo ./init apply [module...]
```

Interactive menu mode is an additional shell around the same engine. It calls the existing module resolver, config renderer, check/plan runner, and apply runner instead of duplicating module logic.

Start it explicitly:

```bash
./init menu
```

Or run the tool with no arguments from a real terminal:

```bash
./init
```

When `./init` has no arguments in a non-interactive environment, it does not read stdin or hang; it prints short help and exits. `menu` is text-only and intentionally does not support JSON output, so `./init menu --format json` is rejected with exit code `2`.

## Menu items

The main menu provides:

1. **Check server** — run checks for the selected modules without changing the system.
2. **Show plan** — print the exact plan for the selected modules without changing the system.
3. **Apply configuration** — resolve dependencies, show a plan, warn about dangerous changes, and ask for explicit confirmation.
4. **Select modules** — toggle modules from the registry and automatically include dependencies.
5. **Edit configuration** — edit target user, Git identity, SSH key settings, firewall flags/ports, upgrade, assume-yes, repair-permissions, and force.
6. **Show effective configuration** — call the same config renderer as command mode.
7. **Show available modules** — call the same modules renderer as command mode.
8. **Help** — explain check, plan, apply, dependencies, target user, sudo use, and CLI equivalents.
9. **Save configuration** — write a safe `KEY=VALUE` config file, defaulting to `./server.conf`.
10. **Load configuration** — load a config file through the safe parser and restore the previous menu state if parsing fails.
0. **Exit**.

After informational screens, press Enter to return to the menu; the application is not restarted.

## Module selection

The module picker is generated from `INIT_REGISTERED_MODULES`, `INIT_MODULE_DESCRIPTIONS`, `INIT_MODULE_DEFAULTS`, and `INIT_MODULE_DEPS` in `config/default.conf`; modules are not hard-coded in the menu. Actions include selecting all, selecting none, restoring defaults, confirming, and canceling.

On confirmation, dependencies are resolved with the same `resolve_modules` function used by command mode. Added dependencies are shown to the user, duplicate modules are avoided, and dependencies cannot be effectively excluded while a dependent module remains selected.

## Configuration editing, saving, and loading

The editor shows the current effective value of every supported menu setting:

```text
target_user
git_name
git_email
ssh_key_path
ssh_key_comment
upgrade
assume_yes
allow_http
allow_https
repair_permissions
force
allow_port
modules
```

String prompts keep the current value on empty input and clear it only when `*` is entered. Boolean values toggle between yes and no. Additional firewall ports are validated through the existing `validate_port_rule` function and duplicates are rejected.

Saving creates the destination via a temporary file and `mv`, uses mode `600`, rejects newline-containing values, and produces a config compatible with `--config`. Loading uses the existing safe `parse_config_file`; if parsing fails, the previous interactive state is restored.

Example automation with a saved config:

```bash
./init plan --config server.conf
sudo ./init apply --config server.conf
```

## Target user and privilege model

The menu attempts to detect a target user through `get_target_user` on startup. If no user is available, it displays `Target user: not selected`. Before user-scoped modules such as `git` or `ssh_key` run, the menu asks for an explicit target user. Root is never silently selected; choosing `root` requires an additional confirmation.

Do not run the whole menu with sudo by default. Start it as a normal user:

```bash
./init
```

System operations continue to use existing module code and `run_root`, so privilege elevation happens only where apply logic needs it.

## Safety prompts

Before apply, menu mode always resolves dependencies, prints selected modules, shows the plan, and asks:

```text
Apply these changes? [y/N]:
```

The default is no. `ASSUME_YES` does not automatically confirm entry into interactive apply. Extra warnings are shown when the plan touches firewall, Docker, package upgrades, or SSH permission repair.

## Text, JSON, colors, and ASCII mode

Command mode supports text and machine-readable JSON for `modules`, `config`, `check`, `plan`, and `apply`:

```bash
./init check --config server.conf --format json
```

Menu mode is text-only. Colors obey `NO_COLOR` and `--no-color`. The menu has no mandatory TUI dependencies: no `gum`, `dialog`, `whiptail`, `fzf`, `ncurses`, or Python are required.

Useful menu environment flags:

```bash
INIT_ASCII_ONLY=1 ./init menu
INIT_NO_CLEAR=1 ./init menu
```

`INIT_ASCII_ONLY=1` avoids Unicode-only UI characters. `INIT_NO_CLEAR=1` disables screen clearing, which is useful for testing and logs.

## Modules and dependencies

The registry lives in `config/default.conf` and currently contains only existing modules: `system`, `packages`, `docker`, `git`, `ssh_key`, `firewall`, and `security`. Dependencies are resolved before execution and each module runs once.

If a dependency fails, is blocked, or cannot be checked, dependent modules are not executed and receive `blocked` with a reason. For example, if `packages` fails, `docker` will not run `apt`, `curl`, `gpg`, or `systemctl`.

## Result model

`check` statuses:

* `configured` — desired state already matches.
* `needs changes` — safe changes are required.
* `check failed` — the state could not be checked.
* `blocked` — a prerequisite/dependency failed.

`apply` statuses:

* `unchanged` — pre-check was already configured and `--force` was not used.
* `applied` — changes were applied and post-check confirmed desired state.
* `failed` — apply or post-check failed.
* `blocked` — a dependency or pre-check prevented execution.
* `skipped` — a non-fatal step was unavailable, such as service management without `systemctl`.

Process exit codes are intentionally simple: `0` for success/configured, `1` when `check` finds required changes, and `2` for errors or blocked/failed operations.

## Desired state and plan output

Plans use a uniform diff format:

* `*` value/action will be added.
* `~` value will be changed.
* `-` value will be removed.
* `=` state already matches.
* `!` warning or check limitation.

Colors obey `--no-color` and `NO_COLOR`. `--format json` disables colors automatically and sends informational logs to stderr.

## Configuration files

Use `--config FILE` for an untrusted user config. It is parsed as `KEY=VALUE` and is never sourced or executed as Bash. Unknown keys, invalid booleans, invalid module names, invalid ports, malformed lines, and NUL bytes are rejected. Command substitution, backticks, shell escaping, and environment variables are treated as literal text.

Supported keys include:

```text
target_user=deploy
git_name=Deploy User
git_email=deploy@example.com
ssh_key_path=~/.ssh/id_ed25519
ssh_key_comment=deploy key
upgrade=false
assume_yes=true
allow_http=true
allow_https=true
repair_permissions=false
force=false
allow_port=8080/tcp
allow_port=53/udp
modules=system,packages,docker,firewall
```

Configuration priority is:

1. Built-in defaults.
2. User config from `--config`.
3. CLI flags and module arguments.

Show the effective configuration without changing the system:

```bash
./init config --config server.conf
```

## Apply safety

Before `apply`, the tool runs `check` for each module. If the module is already configured, its apply function is skipped and the status is `unchanged`. If changes are needed, apply runs and then check runs again. A successful command is not enough: the module is `applied` only when post-check confirms the desired state. Use `--force` to run apply even when pre-check says `configured`.

`packages` does not run `apt update` when all required packages are already installed and `--upgrade` is not set. `apt upgrade` is opt-in with `--upgrade` and appears as a separate plan action.

The Docker repository setup downloads the GPG key to a temporary file, verifies curl and gpg results, checks the built-in Docker key fingerprint, writes the dearmored keyring atomically, and does not use a `curl | gpg` pipeline.

The firewall module reads UFW status without changing policy, adds only missing rules, avoids duplicate rules, and refuses to enable UFW unless an SSH rule is confirmed to protect the current SSH access path.

## Examples

```bash
./init
./init menu
INIT_ASCII_ONLY=1 ./init menu
INIT_NO_CLEAR=1 ./init menu
./init config --config server.conf
./init plan --config server.conf
sudo ./init apply --config server.conf
./init check --config server.conf --format json
```

## Development checks

```bash
bash -n init bootstrap.sh lib/*.sh modules/*.sh tests.sh
shellcheck init bootstrap.sh lib/*.sh modules/*.sh tests.sh
./tests.sh
```
