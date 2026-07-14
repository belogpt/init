# Modular VPS Init

`init` is a Bash-first, modular initial setup tool for Ubuntu/Debian VPS hosts. It is declarative: every module compares the current state with an explicit desired state, prints an exact plan, and applies only the missing changes.

## Commands

```bash
./init help
./init version
./init modules
./init config
./init check [module...]
./init plan [module...]
sudo ./init apply [module...]
```

`bootstrap.sh` is a compatibility entry point that delegates to `init`.

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

## Text and JSON formats

The global format flag supports text and machine-readable JSON for `modules`, `config`, `check`, `plan`, and `apply`:

```bash
./init check --config server.conf --format json
```

JSON is emitted to stdout and is valid without requiring `jq`.

## Apply safety

Before `apply`, the tool runs `check` for each module. If the module is already configured, its apply function is skipped and the status is `unchanged`. If changes are needed, apply runs and then check runs again. A successful command is not enough: the module is `applied` only when post-check confirms the desired state. Use `--force` to run apply even when pre-check says `configured`.

`packages` does not run `apt update` when all required packages are already installed and `--upgrade` is not set. `apt upgrade` is opt-in with `--upgrade` and appears as a separate plan action.

The Docker repository setup downloads the GPG key to a temporary file, verifies curl and gpg results, checks the built-in Docker key fingerprint, writes the dearmored keyring atomically, and does not use a `curl | gpg` pipeline.

The firewall module reads UFW status without changing policy, adds only missing rules, avoids duplicate rules, and refuses to enable UFW unless an SSH rule is confirmed to protect the current SSH access path.

## Examples

```bash
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
