#!/usr/bin/env bash
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok(){ echo "ok - $1"; pass=$((pass+1)); }
not_ok(){ echo "not ok - $1"; fail=$((fail+1)); }

runner_code="$(sed -n '/^run_check_like() {/,/^print_results() {/p' "$ROOT/init" | sed '$d')"
eval "$runner_code"
eval "$(grep '^menu_current_uid()' "$ROOT/lib/menu.sh")"
menu_target_code="$(sed -n '/^menu_need_target_for_user_modules() {/,/^menu_run_check()/p' "$ROOT/lib/menu.sh" | sed '$d')"
eval "$menu_target_code"

declare -A INIT_MODULE_DEPS=([test]="")
RESULT_MODULES=()
RESULT_STATUSES=()
RESULT_DETAILS=()
RESOLVED_MODULES=()
TMPDIR="$TMP"
FORCE_APPLY=0

resolve_modules(){ RESOLVED_MODULES=(test); }
record_result(){ RESULT_MODULES+=("$1"); RESULT_STATUSES+=("$2"); RESULT_DETAILS+=("$3"); }
module_status_text(){ case "$1" in 0) printf configured;; 1) printf 'needs changes';; 3) printf blocked;; *) printf 'check failed';; esac; }
print_results(){ :; }
init_error_trap(){ return 1; }

test_module_check(){ echo "test configured"; return 0; }
test_module_plan(){ echo "= test configured"; return 0; }
rc=0
run_check_like plan || rc=$?
if [ "$rc" -eq 0 ] && [ "${RESULT_STATUSES[0]}" = configured ]; then
  ok "plan reports configured module as configured"
else
  not_ok "plan reports configured module as configured"
fi

test_module_check(){ echo "needs update"; return 1; }
test_module_plan(){ echo "* update test"; return 0; }
rc=0
run_check_like plan || rc=$?
if [ "$rc" -eq 1 ] && [ "${RESULT_STATUSES[0]}" = "needs changes" ]; then
  ok "plan reports changing module as needs changes"
else
  not_ok "plan reports changing module as needs changes"
fi

CHECK_CALLS=0
test_module_check(){
  CHECK_CALLS=$((CHECK_CALLS+1))
  if [ "$CHECK_CALLS" -eq 1 ]; then
    echo "needs update"
    return 1
  fi
  echo "test configured"
  return 0
}
test_module_apply(){ echo "WARNING: noisy apt transcript"; echo "lots of output"; return 0; }
rc=0
run_apply || rc=$?
if [ "$rc" -eq 0 ] && [ "${RESULT_STATUSES[0]}" = applied ] && [ "${RESULT_DETAILS[0]}" = "test configured" ]; then
  ok "successful apply uses post-check detail"
else
  not_ok "successful apply uses post-check detail"
  printf 'status=%s details=%s\n' "${RESULT_STATUSES[0]:-}" "${RESULT_DETAILS[0]:-}"
fi

# Root target detection: simulate a direct root shell while keeping explicit confirmation.
unset INIT_MODULE_DEPS
declare -A INIT_MODULE_DEPS=([git]="" [ssh_key]="")
TARGET_USER=""
ROOT_CONFIRM=0
ROOT_PROMPT=0
resolve_modules(){ RESOLVED_MODULES=(git ssh_key); }
get_target_user(){ [ -n "${TARGET_USER:-}" ] || return 1; printf '%s\n' "$TARGET_USER"; }
menu_current_uid(){ printf '0\n'; }
ui_key_value(){ :; }
i18n_get(){ case "$1" in main.target_user) printf 'Target user';; config.root_confirm) printf 'Root selected. Continue? [y/N]: ';; config.root_not_selected) printf 'Root not selected';; common.not_selected) printf 'not selected';; *) printf '%s' "$1";; esac; }
menu_confirm(){ ROOT_CONFIRM=$((ROOT_CONFIRM+1)); return 0; }
menu_select_target_user(){ ROOT_PROMPT=$((ROOT_PROMPT+1)); return 0; }

if menu_need_target_for_user_modules && [ "$TARGET_USER" = root ] && [ "$ROOT_CONFIRM" -eq 1 ] && [ "$ROOT_PROMPT" -eq 0 ]; then
  ok "root is detected without manual user prompt and still confirmed"
else
  not_ok "root is detected without manual user prompt and still confirmed"
fi

echo "Runner/UX regressions: Passed: $pass Failed: $fail"
[ "$fail" -eq 0 ]
