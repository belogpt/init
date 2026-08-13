#!/usr/bin/env bash
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok() { echo "ok - $1"; pass=$((pass+1)); }
not_ok() { echo "not ok - $1"; fail=$((fail+1)); }

# shellcheck source=config/default.conf
. "$ROOT/config/default.conf"
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=lib/platform.sh
. "$ROOT/lib/platform.sh"
# shellcheck source=lib/state.sh
. "$ROOT/lib/state.sh"
# shellcheck source=modules/docker.sh
. "$ROOT/modules/docker.sh"
# shellcheck source=modules/packages.sh
. "$ROOT/modules/packages.sh"
# shellcheck source=modules/git.sh
. "$ROOT/modules/git.sh"

# Docker keyring regressions: gpg output must not exist before --dearmor runs,
# conversion must be non-interactive, and the RETURN cleanup trap must not leak
# into the caller where set -u would later abort on out-of-scope local variables.
ensure_supported_platform() { OS_ID=ubuntu; OS_CODENAME=noble; return 0; }
curl() {
  local out=""
  while [ "$#" -gt 0 ]; do
    case "$1" in -o) out="$2"; shift 2;; *) shift;; esac
  done
  printf 'mock docker signing key\n' > "$out"
}
gpg() {
  if [ "${1:-}" = --show-keys ]; then
    printf 'fpr:::::::::%s:\n' "$DOCKER_GPG_FINGERPRINT"
    return 0
  fi
  local out="" saw_batch=0 saw_yes=0
  while [ "$#" -gt 0 ]; do
    case "$1" in --batch) saw_batch=1;; --yes) saw_yes=1;; -o) out="$2"; shift;; esac
    shift
  done
  [ "$saw_batch$saw_yes" = 11 ] || return 97
  [ -n "$out" ] || return 98
  [ ! -e "$out" ] || return 99
  printf 'mock dearmored key\n' > "$out"
}
run_root() {
  if [ "${1:-}" = install ] && [ "${2:-}" = -m ] && [ "${3:-}" = 0644 ]; then
    cp "$4" "$TMP/installed-docker.gpg"
    return 0
  fi
  return 96
}
set +e
docker_install_keyring >"$TMP/docker.out" 2>&1
docker_rc=$?
set -e
if [ "$docker_rc" -eq 0 ] && [ -s "$TMP/installed-docker.gpg" ]; then
  ok "docker keyring dearmor is non-interactive and uses a fresh output path"
else
  not_ok "docker keyring dearmor is non-interactive and uses a fresh output path"
  cat "$TMP/docker.out"
fi
if [ -z "$(trap -p RETURN)" ]; then
  ok "docker keyring cleanup RETURN trap does not leak into callers"
else
  not_ok "docker keyring cleanup RETURN trap does not leak into callers"
  trap -p RETURN
  trap - RETURN
fi

# Menu confirmation regression: apt is non-interactive only inside the confirmed
# menu apply call stack (or when --yes/ASSUME_YES is explicitly enabled).
ASSUME_YES=0
if apt_assume_yes; then not_ok "direct apt keeps interactive behavior"; else ok "direct apt keeps interactive behavior"; fi
menu_run_apply_probe() { apt_assume_yes; }
menu_run_apply() { menu_run_apply_probe; }
if menu_run_apply; then ok "menu apply confirmation enables apt assume-yes"; else not_ok "menu apply confirmation enables apt assume-yes"; fi
ASSUME_YES=1
if apt_assume_yes; then ok "explicit assume-yes remains supported"; else not_ok "explicit assume-yes remains supported"; fi
ASSUME_YES=0

: > "$TMP/apt.log"
run_root() { printf '%s\n' "$*" >> "$TMP/apt.log"; }
menu_install_probe() { run_apt_install example-package; }
menu_run_apply() { menu_install_probe; }
menu_run_apply
if grep -qx 'apt -y install example-package' "$TMP/apt.log"; then ok "menu package install passes -y to apt"; else not_ok "menu package install passes -y to apt"; cat "$TMP/apt.log"; fi

: > "$TMP/apt.log"
packages_collect_missing() { packages_missing=(); }
UPGRADE=1
menu_upgrade_probe() { packages_module_apply; }
menu_run_apply() { menu_upgrade_probe; }
menu_run_apply >"$TMP/packages.out" 2>&1
if grep -qx 'apt -y upgrade' "$TMP/apt.log"; then ok "menu package upgrade passes -y to apt"; else not_ok "menu package upgrade passes -y to apt"; cat "$TMP/apt.log"; fi
UPGRADE=0

# Git regression: missing desired identity must not pretend that an update was made.
git_needs() { GIT_NEED_NAME=1; GIT_NEED_EMAIL=1; return 0; }
GIT_NAME=""
GIT_EMAIL=""
GIT_WRITES=0
run_as_target_user() { GIT_WRITES=$((GIT_WRITES+1)); return 0; }
set +e
git_module_apply >"$TMP/git.out" 2>&1
git_rc=$?
set -e
if [ "$git_rc" -eq 3 ] && [ "$GIT_WRITES" -eq 0 ]; then
  ok "git apply skips when desired identity is missing"
else
  not_ok "git apply skips when desired identity is missing"
  cat "$TMP/git.out"
fi

GIT_NAME="Deploy User"
GIT_EMAIL=""
GIT_WRITES=0
set +e
git_module_apply >"$TMP/git-partial.out" 2>&1
git_partial_rc=$?
set -e
if [ "$git_partial_rc" -eq 3 ] && [ "$GIT_WRITES" -eq 0 ]; then
  ok "git apply does not partially mutate an incomplete identity"
else
  not_ok "git apply does not partially mutate an incomplete identity"
  cat "$TMP/git-partial.out"
fi

echo "Regression tests: Passed: $pass Failed: $fail"
[ "$fail" -eq 0 ]
