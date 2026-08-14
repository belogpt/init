#!/usr/bin/env bash
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok() { printf 'ok - %s\n' "$1"; pass=$((pass+1)); }
not_ok() { printf 'not ok - %s\n' "$1"; fail=$((fail+1)); }

# shellcheck source=config/default.conf
. "$ROOT/config/default.conf"
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=modules/security.sh
. "$ROOT/modules/security.sh"
# shellcheck source=modules/firewall.sh
. "$ROOT/modules/firewall.sh"
# shellcheck source=modules/ssh_key.sh
. "$ROOT/modules/ssh_key.sh"

# Security regression: internal state text "package X missing" must never be
# passed to apt as the package name "X missing".
security_state() {
  SEC_NEEDS=(
    "package fail2ban missing"
    "package unattended-upgrades missing"
    "package needrestart missing"
    "fail2ban disabled"
    "fail2ban inactive"
  )
}
ensure_apt() { return 0; }
need_cmd() { [ "$1" = systemctl ]; }
: > "$TMP/security-apt.log"
run_root() {
  case "$*" in
    'apt update'|'systemctl enable fail2ban'|'systemctl start fail2ban') return 0;;
  esac
  return 0
}
run_apt_install() { printf '%s\n' "$@" >> "$TMP/security-apt.log"; }
if security_module_apply >/dev/null 2>&1 &&
   grep -qx 'fail2ban' "$TMP/security-apt.log" &&
   grep -qx 'unattended-upgrades' "$TMP/security-apt.log" &&
   grep -qx 'needrestart' "$TMP/security-apt.log" &&
   ! grep -q ' missing$' "$TMP/security-apt.log"; then
  ok "security passes real package names to apt"
else
  not_ok "security passes real package names to apt"
  cat "$TMP/security-apt.log"
fi

# Firewall regression: before UFW is enabled, `ufw status` may only say
# inactive. Pending rules from `ufw show added` must still confirm SSH safety.
need_cmd() { [ "$1" = ufw ]; }
ensure_apt() { return 0; }
ALLOW_HTTP=0
ALLOW_HTTPS=0
ALLOW_PORTS=()
: > "$TMP/ufw.log"
run_root() {
  case "$*" in
    'ufw status numbered') printf 'Status: inactive\n';;
    'ufw show added') printf "Added user rules:\nufw allow 'OpenSSH'\n";;
    'ufw --force enable') printf '%s\n' "$*" >> "$TMP/ufw.log";;
    'ufw allow '*) printf '%s\n' "$*" >> "$TMP/ufw.log";;
    *) return 0;;
  esac
}
if firewall_module_apply >"$TMP/firewall.out" 2>&1 &&
   grep -qx 'ufw --force enable' "$TMP/ufw.log" &&
   ! grep -q 'refusing to enable UFW' "$TMP/firewall.out"; then
  ok "firewall recognizes pending OpenSSH rule before enable"
else
  not_ok "firewall recognizes pending OpenSSH rule before enable"
  cat "$TMP/firewall.out" "$TMP/ufw.log"
fi

# SSH regression: `ssh-keygen -y` may include a trailing comment. Comparison
# must use only public key type + key material, matching the .pub key fields.
SSH_DIR_TEST="$TMP/.ssh"
mkdir -p "$SSH_DIR_TEST"
chmod 700 "$SSH_DIR_TEST"
printf '%s\n' 'dummy private key' > "$SSH_DIR_TEST/id_ed25519"
printf '%s\n' 'ssh-ed25519 AAAATEST server-comment' > "$SSH_DIR_TEST/id_ed25519.pub"
chmod 600 "$SSH_DIR_TEST/id_ed25519"
chmod 644 "$SSH_DIR_TEST/id_ed25519.pub"
validate_target_user() { return 0; }
get_target_user() { printf 'root\n'; }
target_path() { printf '%s\n' "$SSH_DIR_TEST/id_ed25519"; }
need_cmd() { [ "$1" = ssh-keygen ]; }
ssh-keygen() { printf '%s\n' 'ssh-ed25519 AAAATEST server-comment'; }
ssh_key_state
if [ "${#SSH_PROBLEMS[@]}" -eq 0 ]; then
  ok "ssh key comparison ignores matching public-key comment"
else
  not_ok "ssh key comparison ignores matching public-key comment"
  printf '%s\n' "${SSH_PROBLEMS[@]}"
fi

echo "Install regressions: Passed: $pass Failed: $fail"
[ "$fail" -eq 0 ]
