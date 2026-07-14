#!/usr/bin/env bash
set -u
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MOCK="$TMP/bin"; mkdir -p "$MOCK"
export PATH="$MOCK:$PATH"
export INIT_NO_COLOR=1 HOME=/root SUDO_USER=alice USER=root

cat > "$MOCK/getent" <<'M'
#!/usr/bin/env bash
if [ "$1" = passwd ]; then
  case "$2" in alice) echo 'alice:x:1000:1000:Alice:/home/alice:/bin/bash';; root) echo 'root:x:0:0:root:/root:/bin/bash';; *) exit 2;; esac
elif [ "$1" = group ]; then [ "$2" = docker ] && echo 'docker:x:999:alice' || exit 2
fi
M
cat > "$MOCK/id" <<'M'
#!/usr/bin/env bash
case "$*" in '-u') echo 0;; '-un') echo root;; '-gn alice') echo alice;; '-nG alice') echo 'alice docker';; *) /usr/bin/id "$@";; esac
M
for c in apt ufw systemctl docker ssh-keygen runuser sudo curl gpg tee install chmod chown usermod groupadd dpkg; do cat > "$MOCK/$c" <<'M'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$MOCK_LOG"
case "$(basename "$0") $*" in
  'docker compose version') exit 1;;
  'docker --version') echo 'Docker mock';;
  'dpkg --print-architecture') echo amd64;;
esac
exit 0
M
chmod +x "$MOCK/$c"; done
cat > "$MOCK/dpkg-query" <<'M'
#!/usr/bin/env bash
exit 1
M
cat > "$MOCK/git" <<'M'
#!/usr/bin/env bash
echo "git $* HOME=$HOME" >> "$MOCK_LOG"
case "$*" in 'config --global user.name'|'config --global user.email') exit 1;; '--version') echo 'git version mock';; esac
M
chmod +x "$MOCK/getent" "$MOCK/id" "$MOCK/dpkg-query" "$MOCK/git"

pass=0; fail=0
run() { local name="$1" exp="$2"; shift 2; export MOCK_LOG="$TMP/log"; : > "$MOCK_LOG"; "$@" >/tmp/out 2>/tmp/err; rc=$?; if [ "$rc" = "$exp" ]; then echo "ok - $name"; pass=$((pass+1)); else echo "not ok - $name rc=$rc exp=$exp"; cat /tmp/out /tmp/err; fail=$((fail+1)); fi; }

run help 0 "$ROOT/init" help
run version 0 "$ROOT/init" version
run unknown_cmd 2 "$ROOT/init" nonsense
run unknown_module 2 "$ROOT/init" check nosuch
run multi_commands 2 "$ROOT/init" check plan
run port_zero 2 "$ROOT/init" plan --allow-port 0/tcp
run port_high 2 "$ROOT/init" plan --allow-port 65536/tcp
run port_valid 0 "$ROOT/init" plan firewall --allow-port 443/tcp
run no_mutation_check_plan 0 "$ROOT/init" plan git ssh_key --git-name A --git-email a@b
if grep -Eq 'apt|ufw|systemctl|docker |ssh-keygen' "$MOCK_LOG"; then echo 'not ok - check/plan mutated'; fail=$((fail+1)); else echo 'ok - check/plan no mutation'; pass=$((pass+1)); fi
run sudo_user 1 "$ROOT/init" check git
if grep -q 'alice' /tmp/out /tmp/err; then echo 'ok - target user from SUDO_USER'; pass=$((pass+1)); else echo 'not ok - target user'; cat /tmp/out /tmp/err; fail=$((fail+1)); fi
run target_home 0 "$ROOT/init" plan ssh_key
if grep -q '/home/alice/.ssh/id_ed25519' /tmp/out /tmp/err; then echo 'ok - target home via getent'; pass=$((pass+1)); else echo 'not ok - target home'; fail=$((fail+1)); fi
run git_ssh_target 0 "$ROOT/init" apply git ssh_key --git-name Alice --git-email alice@example.com
if grep -q 'runuser -u alice' "$MOCK_LOG" && grep -q '/home/alice/.ssh/id_ed25519' "$MOCK_LOG"; then echo 'ok - git/ssh target user'; pass=$((pass+1)); else echo 'not ok - git/ssh target user'; cat "$MOCK_LOG"; fail=$((fail+1)); fi
run dedupe 0 "$ROOT/init" plan docker docker packages
if [ "$(awk '/^packages[[:space:]]+done/{c++} END{print c+0}' /tmp/out)" = 1 ]; then echo 'ok - module dedupe'; pass=$((pass+1)); else echo 'not ok - dedupe'; cat /tmp/out; fail=$((fail+1)); fi
if awk '/^packages[[:space:]]+done/{p=NR} /^docker[[:space:]]+done/{d=NR} END{exit !(p && d && p<d)}' /tmp/out; then echo 'ok - dependency order'; pass=$((pass+1)); else echo 'not ok - dependency order'; fail=$((fail+1)); fi

echo "Passed: $pass Failed: $fail"
[ "$fail" -eq 0 ]
