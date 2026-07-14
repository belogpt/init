#!/usr/bin/env bash

MENU_INTERRUPTED=0
MENU_LEVEL=0
MENU_OLD_INT_TRAP=""

menu_on_int() { MENU_INTERRUPTED=1; printf '\nInterrupted.\n' >&2; }
menu_enter() { MENU_OLD_INT_TRAP="$(trap -p INT || true)"; trap menu_on_int INT; }
menu_leave() { trap - INT; }
menu_clear_screen() { [ "${INIT_NO_CLEAR:-0}" = 1 ] && return 0; [ -t 1 ] || return 0; need_cmd clear && clear; }
menu_mark() { [ "${INIT_ASCII_ONLY:-0}" = 1 ] && printf '%s' "$1" || printf '%s' "$2"; }
menu_pause() { printf '\nPress Enter to return to the menu... '; IFS= read -r _ || return 0; }
menu_read() { local __var="$1" prompt="${2:-}"; MENU_INTERRUPTED=0; [ -n "$prompt" ] && printf '%s' "$prompt"; IFS= read -r "$__var" || return 1; [ "$MENU_INTERRUPTED" = 1 ] && return 130; return 0; }
menu_confirm() { local ans; menu_read ans "$1" || return 1; case "$ans" in y|Y|yes|YES) return 0;; *) return 1;; esac; }
menu_join() { local IFS="$1"; shift; printf '%s' "$*"; }
menu_has() { local n="$1" x; shift; for x in "$@"; do [ "$x" = "$n" ] && return 0; done; return 1; }
menu_requested_or_default() { MENU_SELECTED=(); local m; if [ "${#REQUESTED_MODULES[@]}" -gt 0 ]; then MENU_SELECTED=("${REQUESTED_MODULES[@]}"); else for m in "${INIT_REGISTERED_MODULES[@]}"; do [ "${INIT_MODULE_DEFAULTS[$m]}" = 1 ] && MENU_SELECTED+=("$m"); done; fi; }
menu_set_requested() { REQUESTED_MODULES=("$@"); }
menu_resolve_selection() { local before=("$@"); REQUESTED_MODULES=("$@"); resolve_modules || return 2; MENU_ADDED_DEPS=(); local m; for m in "${RESOLVED_MODULES[@]}"; do menu_has "$m" "${before[@]}" || MENU_ADDED_DEPS+=("$m"); done; REQUESTED_MODULES=("${RESOLVED_MODULES[@]}"); }
menu_status_summary() { local c=0 n=0 f=0 b=0 s; for s in "${RESULT_STATUSES[@]:-}"; do case "$s" in configured) c=$((c+1));; 'needs changes'|needs_changes|planned) n=$((n+1));; failed|'check failed') f=$((f+1));; blocked) b=$((b+1));; esac; done; printf '\nSummary:\nConfigured:     %s\nNeeds changes:  %s\nFailed:         %s\nBlocked:        %s\n' "$c" "$n" "$f" "$b"; }
menu_apply_summary() { local a=0 u=0 f=0 b=0 s=0 x; for x in "${RESULT_STATUSES[@]:-}"; do case "$x" in applied) a=$((a+1));; unchanged) u=$((u+1));; failed) f=$((f+1));; blocked) b=$((b+1));; skipped) s=$((s+1));; esac; done; printf '\nSummary:\nApplied:   %s\nUnchanged: %s\nFailed:    %s\nBlocked:   %s\nSkipped:   %s\n' "$a" "$u" "$f" "$b" "$s"; }

menu_show_main() {
  menu_clear_screen
  printf 'Init - VPS bootstrap tool\n\n'
  printf 'Target user: %s\n' "${TARGET_USER:-not selected}"
  printf 'Modules: %s\n\n' "${REQUESTED_MODULES[*]:-(defaults)}"
  cat <<'EOM'
1. Check server
2. Show plan
3. Apply configuration
4. Select modules
5. Edit configuration
6. Show effective configuration
7. Show available modules
8. Help
9. Save configuration
10. Load configuration
0. Exit
EOM
}

menu_select_modules() { local tmp=() choice i m mark; menu_requested_or_default; tmp=("${MENU_SELECTED[@]}"); while :; do menu_clear_screen; printf 'Select modules\n\n'; i=1; for m in "${INIT_REGISTERED_MODULES[@]}"; do mark=' '; menu_has "$m" "${tmp[@]}" && mark=x; printf '%d. [%s] %s - %s\n' "$i" "$mark" "$m" "${INIT_MODULE_DESCRIPTIONS[$m]}"; i=$((i+1)); done; printf '\na) Select all  n) Select none  d) Defaults  c) Confirm  0) Cancel\n'; menu_read choice 'Choice: ' || return 0; case "$choice" in 0) printf 'Selection cancelled.\n'; menu_pause; return 0;; a) tmp=("${INIT_REGISTERED_MODULES[@]}");; n) tmp=();; d) tmp=(); for m in "${INIT_REGISTERED_MODULES[@]}"; do [ "${INIT_MODULE_DEFAULTS[$m]}" = 1 ] && tmp+=("$m"); done;; c) menu_resolve_selection "${tmp[@]}" || { menu_pause; return 2; }; if [ "${#MENU_ADDED_DEPS[@]}" -gt 0 ]; then printf '\nThese dependencies were selected automatically:\n'; printf '%s\n' "${MENU_ADDED_DEPS[@]}"; fi; menu_pause; return 0;; ''|*[!0-9]*) printf 'Invalid choice.\n'; sleep 0.1;; *) if [ "$choice" -ge 1 ] && [ "$choice" -le "${#INIT_REGISTERED_MODULES[@]}" ]; then m="${INIT_REGISTERED_MODULES[$((choice-1))]}"; if menu_has "$m" "${tmp[@]}"; then local nt=() x; for x in "${tmp[@]}"; do [ "$x" = "$m" ] || nt+=("$x"); done; tmp=("${nt[@]}"); else tmp+=("$m"); fi; else printf 'Invalid choice.\n'; fi;; esac; done; }

menu_prompt_value() { local var="$1" label="$2" cur val; cur="${!var:-}"; printf '%s current: %s\n' "$label" "${cur:-<empty>}"; menu_read val 'New value (empty keep, * clear): ' || return 1; [ -z "$val" ] && return 0; [ "$val" = '*' ] && printf -v "$var" '' || printf -v "$var" '%s' "$val"; }
menu_toggle() { local var="$1"; [ "${!var:-0}" = 1 ] && printf -v "$var" 0 || printf -v "$var" 1; }
menu_select_target_user() { local ans confirm; printf 'Enter target user (empty keeps current). Type root only if you really want root.\n'; menu_read ans 'User: ' || return 1; [ -z "$ans" ] && return 0; if [ "$ans" = root ]; then menu_confirm 'Root selected. Continue? [y/N]: ' || { printf 'Root not selected.\n'; return 0; }; fi; TARGET_USER="$ans"; }
menu_manage_ports() { local c p idx n=0 new=(); while :; do printf '\nAdditional firewall ports\n'; idx=1; for p in "${ALLOW_PORTS[@]}"; do printf '%d. %s\n' "$idx" "$p"; idx=$((idx+1)); done; printf '\na) Add port  r) Remove port  c) Clear all  0) Back\n'; menu_read c 'Choice: ' || return 0; case "$c" in 0) return 0;; a) menu_read p 'Port (PORT/tcp or PORT/udp): ' || return 0; if validate_port_rule "$p" && ! menu_has "$p" "${ALLOW_PORTS[@]}"; then ALLOW_PORTS+=("$p"); else printf 'Invalid or duplicate port.\n'; fi;; r) menu_read n 'Remove number: ' || return 0; if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#ALLOW_PORTS[@]}" ]; then new=(); idx=1; for p in "${ALLOW_PORTS[@]}"; do [ "$idx" -eq "$n" ] || new+=("$p"); idx=$((idx+1)); done; ALLOW_PORTS=("${new[@]}"); else printf 'Invalid number.\n'; fi;; c) ALLOW_PORTS=();; *) printf 'Invalid choice.\n';; esac; done; }
menu_edit_config() { local c; while :; do menu_clear_screen; printf 'Edit configuration\n\n1. Target user: %s\n2. Git name: %s\n3. Git email: %s\n4. SSH key path: %s\n5. SSH key comment: %s\n6. Allow HTTP: %s\n7. Allow HTTPS: %s\n8. Additional allow-port: %s\n9. Upgrade: %s\n10. Assume yes: %s\n11. Repair permissions: %s\n12. Force apply: %s\n0. Back\n' "${TARGET_USER:-not selected}" "${GIT_NAME:-}" "${GIT_EMAIL:-}" "$SSH_KEY_PATH" "$SSH_KEY_COMMENT" "$([ "$ALLOW_HTTP" = 1 ] && echo yes || echo no)" "$([ "$ALLOW_HTTPS" = 1 ] && echo yes || echo no)" "${ALLOW_PORTS[*]:-}" "$([ "$UPGRADE" = 1 ] && echo yes || echo no)" "$([ "$ASSUME_YES" = 1 ] && echo yes || echo no)" "$([ "$REPAIR_PERMISSIONS" = 1 ] && echo yes || echo no)" "$([ "$FORCE_APPLY" = 1 ] && echo yes || echo no)"; menu_read c 'Choice: ' || return 0; case "$c" in 0) return 0;; 1) menu_select_target_user;; 2) menu_prompt_value GIT_NAME 'Git name';; 3) menu_prompt_value GIT_EMAIL 'Git email';; 4) menu_prompt_value SSH_KEY_PATH 'SSH key path';; 5) menu_prompt_value SSH_KEY_COMMENT 'SSH key comment';; 6) menu_toggle ALLOW_HTTP;; 7) menu_toggle ALLOW_HTTPS;; 8) menu_manage_ports;; 9) menu_toggle UPGRADE;; 10) menu_toggle ASSUME_YES;; 11) menu_toggle REPAIR_PERMISSIONS;; 12) menu_toggle FORCE_APPLY;; *) printf 'Invalid choice.\n'; sleep 0.1;; esac; done; }
menu_run_check() { run_check_like check; local rc=$?; menu_status_summary; menu_pause; return "$rc"; }
menu_plan_warnings() { local m; printf 'Target user: %s\n' "${TARGET_USER:-not selected}"; for m in "${RESOLVED_MODULES[@]:-}"; do case "$m" in firewall) printf 'Warning: Firewall configuration may affect the current SSH session.\n';; docker) printf 'Warning: Docker installation may change repositories and groups.\n';; packages) [ "$UPGRADE" = 1 ] && printf 'Warning: System packages may be upgraded and services may restart.\n';; esac; done; }
menu_run_plan() { resolve_modules; menu_plan_warnings; run_check_like plan; local rc=$?; printf '\n1. Apply this plan\n2. Change modules\n3. Change configuration\n4. Back\n'; local c; menu_read c 'Choice: ' || return "$rc"; case "$c" in 1) menu_run_apply;; 2) menu_select_modules;; 3) menu_edit_config;; esac; return "$rc"; }
menu_need_target_for_user_modules() { local m; resolve_modules; for m in "${RESOLVED_MODULES[@]}"; do case "$m" in git|ssh_key) if ! get_target_user >/dev/null 2>&1; then printf 'Target user: not selected\n'; menu_select_target_user; fi;; esac; done; }
menu_run_apply() { menu_need_target_for_user_modules; resolve_modules; printf 'Selected modules: %s\n' "${RESOLVED_MODULES[*]}"; menu_plan_warnings; run_check_like plan || true; [ "$UPGRADE" = 1 ] && printf 'System packages may be upgraded and services may restart.\n'; [ "$REPAIR_PERMISSIONS" = 1 ] && printf 'Existing SSH file ownership or permissions may be changed.\n'; menu_confirm 'Apply these changes? [y/N]: ' || { printf 'Apply cancelled.\n'; menu_pause; return 0; }; run_apply; local rc=$?; menu_apply_summary; menu_pause; return "$rc"; }
menu_save_config() { local path tmp p mods; menu_read path 'Save path [./server.conf]: ' || return 0; [ -n "$path" ] || path='./server.conf'; if [ -e "$path" ]; then menu_confirm 'File exists. Overwrite? [y/N]: ' || { printf 'Not overwritten.\n'; menu_pause; return 0; }; fi; for p in "$TARGET_USER" "$GIT_NAME" "$GIT_EMAIL" "$SSH_KEY_PATH" "$SSH_KEY_COMMENT"; do [[ "$p" == *$'\n'* ]] && { printf 'Values with newlines cannot be saved.\n'; menu_pause; return 2; }; done; tmp="${path}.$$tmp"; mods="$(menu_join , "${REQUESTED_MODULES[@]}")"; { printf 'target_user=%s\n' "$TARGET_USER"; printf 'git_name=%s\n' "$GIT_NAME"; printf 'git_email=%s\n' "$GIT_EMAIL"; printf 'ssh_key_path=%s\n' "$SSH_KEY_PATH"; printf 'ssh_key_comment=%s\n' "$SSH_KEY_COMMENT"; printf 'upgrade=%s\nassume_yes=%s\nallow_http=%s\nallow_https=%s\nrepair_permissions=%s\nforce=%s\n' "$UPGRADE" "$ASSUME_YES" "$ALLOW_HTTP" "$ALLOW_HTTPS" "$REPAIR_PERMISSIONS" "$FORCE_APPLY"; for p in "${ALLOW_PORTS[@]}"; do printf 'allow_port=%s\n' "$p"; done; printf 'modules=%s\n' "$mods"; } > "$tmp" && chmod 600 "$tmp" && mv "$tmp" "$path"; printf 'Saved to %s\n' "$path"; menu_pause; }
menu_snapshot() { MENU_SNAPSHOT=("$TARGET_USER" "$GIT_NAME" "$GIT_EMAIL" "$SSH_KEY_PATH" "$SSH_KEY_COMMENT" "$UPGRADE" "$ASSUME_YES" "$ALLOW_HTTP" "$ALLOW_HTTPS" "$REPAIR_PERMISSIONS" "$FORCE_APPLY" "${REQUESTED_MODULES[*]}" "${ALLOW_PORTS[*]}"); }
menu_restore() { TARGET_USER="${MENU_SNAPSHOT[0]}"; GIT_NAME="${MENU_SNAPSHOT[1]}"; GIT_EMAIL="${MENU_SNAPSHOT[2]}"; SSH_KEY_PATH="${MENU_SNAPSHOT[3]}"; SSH_KEY_COMMENT="${MENU_SNAPSHOT[4]}"; UPGRADE="${MENU_SNAPSHOT[5]}"; ASSUME_YES="${MENU_SNAPSHOT[6]}"; ALLOW_HTTP="${MENU_SNAPSHOT[7]}"; ALLOW_HTTPS="${MENU_SNAPSHOT[8]}"; REPAIR_PERMISSIONS="${MENU_SNAPSHOT[9]}"; FORCE_APPLY="${MENU_SNAPSHOT[10]}"; read -r -a REQUESTED_MODULES <<< "${MENU_SNAPSHOT[11]}"; read -r -a ALLOW_PORTS <<< "${MENU_SNAPSHOT[12]}"; }
menu_load_config() { local path; menu_read path 'Config path: ' || return 0; [ -n "$path" ] || { printf 'No path entered.\n'; menu_pause; return 0; }; menu_snapshot; if parse_config_file "$path"; then printf 'Configuration loaded from %s\n' "$path"; else menu_restore; printf 'Load failed; previous menu state restored.\n'; fi; menu_pause; }
menu_help() { cat <<'EOFH'
Interactive help

Check compares selected modules with the current server and does not change the system.
Plan prints the exact changes that selected modules would make without changing the system.
Apply shows a plan, asks for explicit confirmation, runs the existing apply engine, and post-checks results.
Modules are selected from the registry; dependencies are resolved automatically and run once.
Target user is used by user-scoped modules such as git and ssh_key. Root is never assumed silently.
Prefer starting the menu as a regular user; system modules use sudo only when their apply code needs it.
Use command mode for automation:

Menu: Check server
CLI:  ./init check

Menu: Apply Docker
CLI:  sudo ./init apply docker

Menu: Load config
CLI:  ./init plan --config server.conf
EOFH
menu_pause; }
menu_main() { menu_enter; if get_target_user >/dev/null 2>&1; then TARGET_USER="$(get_target_user)"; fi; local c; while :; do menu_show_main; menu_read c 'Choice: ' || { printf '\nExiting.\n'; menu_leave; return 0; }; case "$c" in 0) menu_leave; return 0;; 1) menu_run_check || true;; 2) menu_run_plan || true;; 3) menu_run_apply || true;; 4) menu_select_modules || true;; 5) menu_edit_config || true;; 6) cmd_config; menu_pause;; 7) cmd_modules; menu_pause;; 8) menu_help;; 9) menu_save_config;; 10) menu_load_config;; ''|*[!0-9]*) printf 'Invalid choice.\n'; sleep 0.1;; *) printf 'Invalid choice.\n'; sleep 0.1;; esac; done; }
