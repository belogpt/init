#!/usr/bin/env bash
set -u
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MOCK="$TMP/bin"; mkdir -p "$MOCK"
export PATH="$MOCK:$PATH" INIT_NO_COLOR=1 HOME=/root SUDO_USER=alice USER=root MOCK_LOG="$TMP/log" MOCK_DPKG_ALL=1
: > "$MOCK_LOG"
cat > "$MOCK/getent" <<'M'
#!/usr/bin/env bash
if [ "$1" = passwd ]; then case "$2" in alice) echo 'alice:x:1000:1000:Alice:/tmp/alice:/bin/bash';; root) echo 'root:x:0:0:root:/root:/bin/bash';; *) exit 2;; esac
elif [ "$1" = group ]; then [ "$2" = docker ] && echo 'docker:x:999:alice' || exit 2; fi
M
cat > "$MOCK/id" <<'M'
#!/usr/bin/env bash
case "$*" in '-u') echo 0;; '-un') echo root;; '-gn alice') echo alice;; '-nG alice') echo 'alice docker';; *) /usr/bin/id "$@";; esac
M
cat > "$MOCK/dpkg-query" <<'M'
#!/usr/bin/env bash
[ "${MOCK_DPKG_ALL:-0}" = 1 ] && { echo 'install ok installed'; exit 0; }
exit 1
M
cat > "$MOCK/git" <<'M'
#!/usr/bin/env bash
echo "git $*" >> "$MOCK_LOG"
case "$*" in 'config --global user.name') echo "${MOCK_GIT_NAME:-Old User}";; 'config --global user.email') echo "${MOCK_GIT_EMAIL:-old@example.com}";; esac
M
cat > "$MOCK/runuser" <<'M'
#!/usr/bin/env bash
echo "runuser $*" >> "$MOCK_LOG"
shift 3; HOME=/tmp/alice "$@"
M
for c in apt ufw systemctl docker ssh-keygen sudo curl gpg tee install chmod chown usermod groupadd dpkg stat awk; do [ "$c" = awk ] && continue; cat > "$MOCK/$c" <<'M'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$MOCK_LOG"
case "$(basename "$0") $*" in
  'dpkg --print-architecture') echo amd64;;
  'docker compose version') exit 0;;
  'systemctl is-active --quiet docker.service'|'systemctl is-enabled --quiet docker.service'|'systemctl is-active --quiet fail2ban'|'systemctl is-enabled --quiet fail2ban') exit 0;;
  'ufw status numbered') echo 'Status: active'; echo '22/tcp ALLOW Anywhere'; echo '80/tcp ALLOW Anywhere';;
esac
[ "$(basename "$0")" = curl ] && [ "${MOCK_CURL_FAIL:-0}" = 1 ] && exit 22
[ "$(basename "$0")" = gpg ] && [ "${MOCK_GPG_BAD:-0}" = 1 ] && { echo fpr:::::::::BAD:; exit 0; }
exit 0
M
chmod +x "$MOCK/$c"; done
chmod +x "$MOCK"/*
pass=0; fail=0
run(){ local name="$1" exp="$2"; shift 2; : > "$MOCK_LOG"; "$@" >"$TMP/out" 2>"$TMP/err"; rc=$?; if [ "$rc" = "$exp" ]; then echo "ok - $name"; pass=$((pass+1)); else echo "not ok - $name rc=$rc exp=$exp"; cat "$TMP/out" "$TMP/err"; fail=$((fail+1)); fi; }
contains(){ local name="$1" pat="$2" file="$3"; if grep -qE "$pat" "$file"; then echo "ok - $name"; pass=$((pass+1)); else echo "not ok - $name"; cat "$file"; fail=$((fail+1)); fi; }
run "dependency blocks dependent module" 2 env MOCK_DPKG_ALL=0 "$ROOT/init" apply docker
contains "docker not executed when packages failed" '^apt ' "$MOCK_LOG"
run "apply skips configured module" 0 "$ROOT/init" apply packages
if ! grep -q 'apt update' "$MOCK_LOG"; then echo 'ok - no apt update for configured packages'; pass=$((pass+1)); else echo 'not ok - apt update called'; fail=$((fail+1)); fi
run "post-check after apply fails when desired absent" 2 env MOCK_DPKG_ALL=0 "$ROOT/init" apply packages
run "git compares desired" 1 "$ROOT/init" check git --git-name 'Deploy User' --git-email deploy@example.com
run "ssh reports missing files" 1 "$ROOT/init" check ssh_key --target-user alice
run "ssh wrong permissions not repaired without flag" 2 "$ROOT/init" apply ssh_key --target-user alice
run "repair-permissions flag accepted" 2 "$ROOT/init" apply ssh_key --target-user alice --repair-permissions
run "packages no apt update when unchanged" 0 "$ROOT/init" apply packages
run "docker keyring curl failure returns error" 2 env MOCK_CURL_FAIL=1 bash -c '. ./config/default.conf; . ./lib/logging.sh; . ./lib/common.sh; . ./lib/platform.sh; . ./lib/state.sh; . ./modules/docker.sh; OS_ID=ubuntu OS_CODENAME=noble; docker_install_keyring'
run "docker keyring fingerprint mismatch returns error" 2 env MOCK_GPG_BAD=1 bash -c '. ./config/default.conf; . ./lib/logging.sh; . ./lib/common.sh; . ./lib/platform.sh; . ./lib/state.sh; . ./modules/docker.sh; OS_ID=ubuntu OS_CODENAME=noble; docker_install_keyring'
run "firewall protects ssh" 0 "$ROOT/init" plan firewall --allow-http
run "ufw rules not duplicated in plan" 0 "$ROOT/init" plan firewall --allow-http
run "security start failure is error" 2 env MOCK_DPKG_ALL=1 bash -c 'PATH="$PATH"; . ./config/default.conf; . ./lib/logging.sh; . ./lib/common.sh; . ./modules/security.sh; systemctl(){ return 1; }; security_module_apply'
CFG="$TMP/server.conf"; echo 'git_name=$(touch /tmp/pwned)' > "$CFG"; run "config does not execute command substitution" 0 "$ROOT/init" config --config "$CFG"; [ ! -e /tmp/pwned ] && echo 'ok - no command execution' && pass=$((pass+1)) || fail=$((fail+1))
echo 'bad_key=x' > "$CFG"; run "unknown config key rejected" 2 "$ROOT/init" config --config "$CFG"
printf 'git_name=Config Name\nallow_port=8080/tcp\nallow_port=53/udp\nmodules=git,firewall\n' > "$CFG"; run "cli overrides config" 0 "$ROOT/init" config --config "$CFG" --git-name CLI
contains "repeated allow_port parsed" '8080/tcp.*53/udp' "$TMP/out"
run "init config no mutation" 0 "$ROOT/init" config --config "$CFG"
if [ ! -s "$MOCK_LOG" ]; then echo 'ok - config did not mutate'; pass=$((pass+1)); else echo 'not ok - config mutated'; cat "$MOCK_LOG"; fail=$((fail+1)); fi
run "json output valid" 0 bash -c '"$0" check packages --format json | python3 -m json.tool >/dev/null' "$ROOT/init"
run "check text no mutation" 0 "$ROOT/init" check packages
run "plan json no mutation" 0 bash -c '"$0" plan packages --format json | python3 -m json.tool >/dev/null' "$ROOT/init"
run "menu exits with zero" 0 bash -c "printf '0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu"
run "no args non tty shows help" 0 bash -c "'$ROOT/init' < /dev/null"
run "menu rejects json" 2 "$ROOT/init" menu --format json
run "invalid menu number continues" 0 bash -c "printf '99\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu"
run "menu EOF exits" 0 bash -c "printf '' | INIT_NO_CLEAR=1 '$ROOT/init' menu"
run "menu modules generated from registry" 0 bash -c "printf '4\\n0\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu"
contains "module menu includes docker" 'docker - Install Docker' "$TMP/out"
run "select docker adds dependencies" 0 bash -c "printf '4\\nn\\n3\\nc\\n\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu"
contains "dependency selected automatically" 'dependencies were selected automatically' "$TMP/out"
run "cancel module selection returns" 0 bash -c "printf '4\\nn\\n0\\n\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu"
run "edit target user updates config" 0 bash -c "printf '5\\n1\\nbob\\n0\\n6\\n\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu"
contains "target user is bob" 'Target user:[[:space:]]+bob' "$TMP/out"
run "root target needs confirmation" 0 bash -c "printf '5\\n1\\nroot\\nn\\n0\\n6\\n\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu"
contains "root not selected" 'Root not selected' "$TMP/out"
run "invalid port rejected" 0 bash -c "printf '5\\n8\\na\\nbad\\n0\\n0\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu"
contains "invalid port message" 'Invalid or duplicate port' "$TMP/out"
run "duplicate port rejected" 0 bash -c "printf '5\\n8\\na\\n8080/tcp\\na\\n8080/tcp\\n0\\n0\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu"
contains "duplicate port message" 'Invalid or duplicate port' "$TMP/out"
run "port can be removed" 0 bash -c "printf '5\\n8\\na\\n8080/tcp\\nr\\n1\\n0\\n0\\n6\\n\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu"
run "plan from menu no mutation" 0 bash -c "printf '2\\n4\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu packages"
run "apply negative confirmation cancels" 0 bash -c "printf '3\\nn\\n\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu packages"
contains "apply cancelled" 'Apply cancelled' "$TMP/out"
if ! grep -q '^apt update' "$MOCK_LOG"; then echo 'ok - negative apply did not mutate'; pass=$((pass+1)); else echo 'not ok - negative apply mutated'; fail=$((fail+1)); fi
SAVED="$TMP/saved.conf"; run "save config creates file" 0 bash -c "printf '9\\n$SAVED\\n\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' --target-user alice --allow-port 8080/tcp menu"
[ -f "$SAVED" ] && echo 'ok - saved config file exists' && pass=$((pass+1)) || { echo 'not ok - saved config missing'; fail=$((fail+1)); }
contains "saved config has repair" '^repair_permissions=' "$SAVED"
run "save config no overwrite" 0 bash -c "printf '9\\n$SAVED\\nn\\n\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu"
LOAD="$TMP/load.conf"; printf 'target_user=alice\nmodules=git\nrepair_permissions=true\nforce=true\n' > "$LOAD"; run "load config uses parser" 0 bash -c "printf '10\\n$LOAD\\n\\n6\\n\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu"
contains "loaded config target" 'Target user:[[:space:]]+alice' "$TMP/out"
BAD="$TMP/bad.conf"; echo 'bad_key=x' > "$BAD"; run "bad load restores" 0 bash -c "printf '10\\n$BAD\\n\\n6\\n\\n0\\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu --target-user alice"
contains "load restored" 'previous menu state restored' "$TMP/out"
run "ascii menu has no unicode dash" 0 bash -c "printf '0\\n' | INIT_ASCII_ONLY=1 INIT_NO_CLEAR=1 '$ROOT/init' menu"
if LC_ALL=C grep -q $'—' "$TMP/out"; then echo 'not ok - unicode dash emitted'; fail=$((fail+1)); else echo 'ok - ascii has no unicode dash'; pass=$((pass+1)); fi
run "NO_COLOR menu has no ansi" 0 bash -c "printf '0\\n' | NO_COLOR=1 INIT_NO_CLEAR=1 '$ROOT/init' menu"
if grep -q $'\\033' "$TMP/out"; then echo 'not ok - ansi emitted'; fail=$((fail+1)); else echo 'ok - no ansi emitted'; pass=$((pass+1)); fi

echo "Passed: $pass Failed: $fail"; [ "$fail" -eq 0 ]
