# VPS Init Bootstrap

`init` is a modular Bash bootstrap tool for the first setup of an empty VPS. The repository keeps `bootstrap.sh` as a tiny entry point, while the real CLI, shared libraries, and server setup modules are split into separate files.

> Test this on a disposable VPS before using it on a production server. The `apply` command installs packages and changes system services, firewall rules, Git settings, and SSH keys.

## Supported operating systems

The tool is intended for apt-based Linux distributions already supported by the previous script:

- Ubuntu;
- Debian.

Docker repository setup is selected from `/etc/os-release` and uses the official Docker apt repository for Ubuntu or Debian.

## Project structure

```text
init/
├── bootstrap.sh          # Minimal compatibility entry point; delegates to ./init.
├── init                  # Main CLI dispatcher.
├── config/
│   └── default.conf      # Defaults for modules and package lists.
├── lib/
│   ├── common.sh         # Shared command, root/sudo, apt, and error helpers.
│   ├── logging.sh        # Unified color-aware logging functions.
│   ├── platform.sh       # OS detection and Ubuntu/Debian validation.
│   └── state.sh          # Small state/path helpers.
├── modules/
│   └── system.sh         # Current server bootstrap module.
└── tests/                # Reserved for future automated tests.
```

## Commands

| Command | Purpose | Changes system? |
| --- | --- | --- |
| `./init help` | Show help. | No |
| `./init version` | Print version. | No |
| `./init check` | Inspect OS, packages, Git, SSH key, Docker, UFW, and fail2ban state. | No |
| `./init plan` | Show the actions that `apply` would perform. | No |
| `./init apply` | Apply the bootstrap plan idempotently. | Yes |

Global flags:

- `--no-color` disables colors. Colors are also disabled automatically when stdout is not a TTY or when `NO_COLOR` is set.
- `--debug` enables debug logs.
- `--yes` / `-y` passes non-interactive confirmation to apt where appropriate.
- `--skip-upgrade` skips `apt upgrade` during `apply`.

Apply options retained from the previous bootstrap flow:

- `--git-name NAME`
- `--git-email EMAIL`
- `--ssh-key-path PATH`
- `--ssh-key-comment TEXT`
- `--allow-http`
- `--allow-https`
- `--allow-port PORT/PROTO`

## Module contract

Each module must implement three functions:

```bash
<module>_module_check
<module>_module_plan
<module>_module_apply
```

The CLI loads modules listed in `config/default.conf` and calls the requested operation. Adding another independent module should only require adding its file under `modules/` and including its module name in `INIT_MODULES`.

## Example usage

```bash
chmod +x bootstrap.sh init
./init help
./init check
./init plan
sudo ./init apply --yes --git-name "Your Name" --git-email you@example.com
```

Compatibility entry point:

```bash
./bootstrap.sh help
./bootstrap.sh --check
./bootstrap.sh --all --yes
```

## Safety notes

- `check` and `plan` are read-only by design.
- `apply` skips work that is already complete where practical: installed package sets, existing Docker/Compose, existing SSH key, existing Git identity, and existing docker group membership.
- The scripts do not use `eval` and quote variables deliberately.
- Remote code is not executed directly. The Docker GPG key is downloaded from the official Docker repository and stored as an apt keyring before packages are installed through apt.

## Local verification

Recommended checks before committing changes:

```bash
bash -n bootstrap.sh init lib/*.sh modules/*.sh
shellcheck bootstrap.sh init lib/*.sh modules/*.sh
./init help
./init check
./init plan
```
