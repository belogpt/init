#!/usr/bin/env bash
set -u
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
run(){ local name="$1" exp="$2"; shift 2; "$@" >"$TMP/out" 2>"$TMP/err"; local rc=$?; if [ "$rc" = "$exp" ]; then echo "ok - $name"; pass=$((pass+1)); else echo "not ok - $name rc=$rc exp=$exp"; cat "$TMP/out" "$TMP/err"; fail=$((fail+1)); fi; }
contains(){ local name="$1" pat="$2" file="${3:-$TMP/out}"; if grep -qE "$pat" "$file"; then echo "ok - $name"; pass=$((pass+1)); else echo "not ok - $name"; cat "$file"; fail=$((fail+1)); fi; }
not_contains(){ local name="$1" pat="$2" file="${3:-$TMP/out}"; if grep -qE "$pat" "$file"; then echo "not ok - $name"; cat "$file"; fail=$((fail+1)); else echo "ok - $name"; pass=$((pass+1)); fi; }

run "Russian language via --lang ru" 0 bash -c "printf '0\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu --lang ru"
contains "Russian menu contains Check server" 'Проверить сервер'
run "English language via --lang en" 0 bash -c "printf '0\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu --lang en"
contains "English menu contains Check server" 'Check server'
run "auto selects ru for ru_RU" 0 bash -c "printf '0\n' | LC_ALL= LANG=ru_RU.UTF-8 INIT_NO_CLEAR=1 '$ROOT/init' menu --lang auto"
contains "auto ru renders Russian" 'Проверить сервер'
run "auto selects en for C" 0 bash -c "printf '0\n' | LC_ALL= LANG=C.UTF-8 INIT_NO_CLEAR=1 '$ROOT/init' menu --lang auto"
contains "auto C renders English" 'Check server'
run "unsupported language falls back" 0 bash -c "printf '0\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu --lang zz"
contains "unsupported language warning" 'Unsupported language'
run "language switching applies immediately" 0 bash -c "printf '11\n2\n4\n12\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu --lang en"
contains "switched screen is Russian" 'Главное меню'
SAVE="$TMP/lang.conf"; run "language saved in config" 0 bash -c "printf '9\n$SAVE\n12\n' | INIT_NO_CLEAR=1 '$ROOT/init' menu --lang ru"
contains "config has language" '^language=ru$' "$SAVE"
printf 'language=ru\nmodules=system\n' > "$TMP/load.conf"; run "language loads from config" 0 bash -c "printf '0\n' | INIT_NO_CLEAR=1 '$ROOT/init' --config '$TMP/load.conf' menu"
contains "loaded language ru" 'Проверить сервер'
printf 'language=ru\nmodules=system\n' > "$TMP/load.conf"; run "CLI lang overrides config" 0 bash -c "printf '0\n' | INIT_NO_CLEAR=1 '$ROOT/init' --config '$TMP/load.conf' menu --lang en"
contains "override to English" 'Check server'
run "missing ru fallback and unknown key safe" 0 bash -c '. "$0/lib/i18n.sh"; i18n_set_lang ru; echo "$(i18n_get help.text)"; i18n_get 'x.$(touch /tmp/init_i18n_pwn)'' "$ROOT" "$TMP"
not_contains "unknown key did not execute shell" 'pwned'
[ ! -e "$TMP/pwn" ] && echo 'ok - unknown key no execution' && pass=$((pass+1)) || { echo 'not ok - unknown key executed'; fail=$((fail+1)); }
run "ASCII mode no unicode frame" 0 bash -c "printf '0\n' | INIT_ASCII_ONLY=1 INIT_NO_CLEAR=1 '$ROOT/init' menu"
not_contains "ascii has no unicode frame" '[┌┐└┘─│]'
run "NO_COLOR disables ansi" 0 bash -c "printf '0\n' | NO_COLOR=1 INIT_NO_CLEAR=1 '$ROOT/init' menu"
if grep -q $'\033' "$TMP/out"; then echo 'not ok - ansi present'; fail=$((fail+1)); else echo 'ok - ansi absent'; pass=$((pass+1)); fi
contains "main menu sections" 'CHECK AND APPLY'
contains "configuration section" 'CONFIGURATION'
contains "project section" 'PROJECT'
not_contains "no predictable tmp init_module_out" '/tmp/init_module_out' "$ROOT/init"
not_contains "no predictable tmp init_pre" '/tmp/init_pre' "$ROOT/init"
run "JSON statuses remain machine readable" 0 bash -c "'$ROOT/init' check system --format json | python3 -m json.tool"
contains "json status configured" '"status": "configured"'

echo "Passed: $pass Failed: $fail"; [ "$fail" -eq 0 ]
