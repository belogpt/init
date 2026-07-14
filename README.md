# Modular VPS Init

A Bash-first initial VPS setup tool for Ubuntu and Debian. `bootstrap.sh` is a minimal compatibility entry point; `init` is the main CLI.

## Structure

```text
config/default.conf      defaults and explicit module registry
lib/                     logging, platform, common, state/target-user helpers
modules/system.sh        platform preflight only
modules/packages.sh      base apt packages and optional upgrade
modules/docker.sh        Docker Engine and Compose plugin
modules/git.sh           target-user Git identity
modules/ssh_key.sh       target-user SSH key
modules/firewall.sh      UFW rules
modules/security.sh      security packages
```

## Module registry and selection

List registered modules, descriptions, defaults, and dependencies:

```bash
./init modules
```

`check`, `plan`, and `apply` accept optional module names. If no module is specified, every module enabled by default is selected. Dependencies are resolved deterministically and each module is run once even if requested repeatedly.

```bash
./init check docker
./init plan packages docker
./init apply packages docker
```

Unknown modules fail with exit code `2`.

## Target user

User-context modules (`git` and `ssh_key`) act on a **target user**, selected in this order:

1. `--target-user USER`.
2. `SUDO_USER` when running through `sudo`.
3. Current user when not running as root.
4. No implicit target when running directly as root.

This prevents `sudo ./init apply git ssh_key` from silently modifying `/root` when the intended user is a normal account. Configuring root is allowed only explicitly:

```bash
sudo ./init apply git ssh_key --target-user root
```

Home directories are read from system account data (`getent passwd`), not from the caller's `HOME`.

## Upgrade behavior

`apt upgrade` is disabled by default. Use `--upgrade` to make `packages` plan and apply a full upgrade. The deprecated `--skip-upgrade` flag is accepted as a no-op warning for compatibility.

## Safe examples

```bash
./init plan packages docker
./init apply packages docker --upgrade
sudo ./init apply git ssh_key --target-user deploy \
  --git-name "Deploy User" \
  --git-email deploy@example.com
```

Check and plan do not require root and do not call mutating system commands. Apply uses privilege escalation only around system-changing commands.

## Development checks

```bash
bash -n init lib/*.sh modules/*.sh tests.sh
shellcheck init bootstrap.sh lib/*.sh modules/*.sh tests.sh
./tests.sh
```
