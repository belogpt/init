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
echo "Passed: $pass Failed: $fail"; [ "$fail" -eq 0 ]
