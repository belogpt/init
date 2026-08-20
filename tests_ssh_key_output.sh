#!/usr/bin/env bash
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/i18n.sh
. "$ROOT/lib/i18n.sh"
# shellcheck source=lib/menu.sh
. "$ROOT/lib/menu.sh"

PASS=0
FAIL=0

ok() { printf 'ok - %s\n' "$1"; PASS=$((PASS+1)); }
not_ok() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL+1)); }
assert_contains() { case "$1" in *"$2"*) return 0;; *) return 1;; esac; }
assert_not_contains() { case "$1" in *"$2"*) return 1;; *) return 0;; esac; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' 'PRIVATE-KEY-MUST-NOT-APPEAR' > "$tmp/id_ed25519"
printf '%s\n' 'ssh-ed25519 AAAATESTPUBLICKEY vps@example' > "$tmp/id_ed25519.pub"

SSH_KEY_PATH='~/.ssh/id_ed25519'
target_path() { printf '%s\n' "$tmp/id_ed25519"; }
ui_section() { printf 'SECTION:%s\n' "$1"; }
ui_hint() { printf 'HINT:%s\n' "$1"; }

RESULT_MODULES=(ssh_key)
RESULT_STATUSES=(applied)
INIT_EFFECTIVE_LANG=ru
out="$(menu_show_ssh_public_key)"
if assert_contains "$out" 'Публичный SSH-ключ для GitHub' \
  && assert_contains "$out" 'ssh-ed25519 AAAATESTPUBLICKEY vps@example' \
  && assert_not_contains "$out" 'PRIVATE-KEY-MUST-NOT-APPEAR'; then
  ok 'applied SSH key prints only the public key'
else
  not_ok 'applied SSH key prints only the public key'
fi

RESULT_STATUSES=(unchanged)
out="$(menu_show_ssh_public_key)"
if assert_contains "$out" 'ssh-ed25519 AAAATESTPUBLICKEY vps@example'; then
  ok 'unchanged SSH key remains available for GitHub setup'
else
  not_ok 'unchanged SSH key remains available for GitHub setup'
fi

RESULT_STATUSES=(failed)
out="$(menu_show_ssh_public_key)"
if [ -z "$out" ]; then
  ok 'failed SSH module does not advertise a key'
else
  not_ok 'failed SSH module does not advertise a key'
fi

INIT_EFFECTIVE_LANG=ru
if [ "$(i18n_get apply.confirm)" = 'Применить эти изменения? [y/N]: ' ] \
  && [ "$(i18n_get results.summary)" = 'Сводка' ] \
  && [ "$(i18n_get apply.github_ssh_key)" = 'Публичный SSH-ключ для GitHub' ]; then
  ok 'Russian apply workflow translations are complete'
else
  not_ok 'Russian apply workflow translations are complete'
fi

printf 'Passed: %d Failed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
