#!/usr/bin/env bash
# fm-away-notify.sh - the away-mode phone alert: tell the captain, through a
# command they configured, that something now waits for them, so they can
# connect and answer instead of finding it only at their return.
#
# Usage:
#   fm-away-notify.sh send --summary <text>
#     Alert for one new captain outcome. Exits 0 whether or not anything was
#     sent; every refusal or failure is a warning on stderr, so a caller in the
#     supervision path is never broken or delayed beyond the bound below.
#   fm-away-notify.sh configured
#     Exit 0 when config/away-notify enables at least one channel, 1 otherwise.
#     The away entry announcement (bin/fm-afk-contract.sh) reads it.
#
# WHEN IT FIRES. `send` fires only while an away record stands
# (fm_afk_contract_away_present): an attended session and quiet mode, where the
# captain is present, never notify. Its callers are the two places a captain
# outcome is recorded while away, each calling once per new outcome:
#   - bin/fm-branch-outcome.sh append, for a non-silent captain-verdict row.
#     Every supervision branch (the Pi branch and the supervision host) records
#     its captain outcomes there, and the hook runs at append rather than at
#     presentation, so a drain re-presenting an unacknowledged row never
#     re-sends it.
#   - bin/fm-captain-hold.sh hold, for a new captain hold set outside the
#     supervision branch. Behind the away daemon the away session is main
#     itself, and a hold is how it records anything that waits for the
#     captain; the branch's own holds already carry a captain outcome row.
# Routine outcomes have no caller here, so they never notify.
#
# CONFIG. config/away-notify (local, gitignored) lists channel directives, one
# per non-empty line, `#` comments allowed (bin/fm-notify-lib.sh owns the
# parsing). `command:<cmd>` runs <cmd> through `sh -c` with the alert text as
# $1 and on stdin, the same channel config/wedge-alarm offers. `off` anywhere
# disables every channel. An absent file, or one with no command, is off.
# Every listed command fires, best-effort, each bounded by
# FM_AWAY_NOTIFY_TIMEOUT_SECS (default 10) in its own process group, so a hung
# command is terminated rather than holding up its caller.
#
# RATE LIMIT. At most one alert per FM_AWAY_NOTIFY_MIN_SECS (default 600; 0
# sends every outcome). An outcome inside that window is not sent; it is
# counted in $STATE/.away-notify, and the next alert carries the count, so
# nothing is dropped silently. The record also names the away window it
# belongs to (the away record's entered_epoch), so a new away window starts
# with no carried count and no window in force. Updates run under
# $STATE/.away-notify.lock; a lock that cannot be taken within 5 seconds sends
# without the rate limit rather than losing the alert.
set -u

FM_AWAY_NOTIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fm-wake-lib.sh
. "$FM_AWAY_NOTIFY_DIR/fm-wake-lib.sh"
# shellcheck source=bin/fm-afk-contract.sh
. "$FM_AWAY_NOTIFY_DIR/fm-afk-contract.sh"
# shellcheck source=bin/fm-notify-lib.sh
. "$FM_AWAY_NOTIFY_DIR/fm-notify-lib.sh"

AWAY_NOTIFY_CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}/away-notify"
AWAY_NOTIFY_RECORD="$STATE/.away-notify"
AWAY_NOTIFY_LOCK="$STATE/.away-notify.lock"
AWAY_NOTIFY_MIN_SECS_DEFAULT=600
AWAY_NOTIFY_SUMMARY_MAX=280
AWAY_NOTIFY_PID=

usage() {
  echo "usage: fm-away-notify.sh send --summary <text> | configured" >&2
  exit 2
}

warn() { printf 'fm-away-notify: warning: %s\n' "$*" >&2; }

# Print each configured command, one per line; nothing when the file is
# absent, names no command, or holds `off`.
configured_commands() {
  local directive
  local -a commands=()
  while IFS= read -r directive; do
    case "$directive" in
      off) return 0 ;;
      command:*)
        if [ -n "${directive#command:}" ]; then
          commands+=("${directive#command:}")
        else
          warn "an empty command: directive in config/away-notify is ignored"
        fi ;;
      *) warn "an unrecognized directive in config/away-notify is ignored (redacted)" ;;
    esac
  done < <(fm_notify_directives "$AWAY_NOTIFY_CONFIG")
  [ "${#commands[@]}" -gt 0 ] || return 0
  printf '%s\n' "${commands[@]}"
}

min_secs() {
  case "${FM_AWAY_NOTIFY_MIN_SECS:-}" in
    ''|*[!0-9]*) printf '%s\n' "$AWAY_NOTIFY_MIN_SECS_DEFAULT" ;;
    *) printf '%s\n' "$FM_AWAY_NOTIFY_MIN_SECS" ;;
  esac
}

# One line, bounded, so a phone banner shows it whole.
one_line() {  # <text>
  local text
  text=$(printf '%s' "$1" | tr '\n\r\t' '   ' | sed 's/  */ /g; s/^ //; s/ $//')
  if [ "${#text}" -gt "$AWAY_NOTIFY_SUMMARY_MAX" ]; then
    text="${text:0:$((AWAY_NOTIFY_SUMMARY_MAX - 3))}..."
  fi
  printf '%s' "$text"
}

# Decide under the lock whether this outcome sends now or folds into the next
# alert. Prints the number of earlier folded outcomes the alert must carry, or
# nothing when this outcome folded.
reserve_alert() {  # <window> <now> <min-secs>
  local window=$1 now=$2 min=$3 record_window='' last=0 folded=0 tmp
  if ! fm_lock_acquire_wait_max "$AWAY_NOTIFY_LOCK" 5; then
    warn "could not take the alert lock; sending without the rate limit"
    printf '0\n'
    return 0
  fi
  if [ -f "$AWAY_NOTIFY_RECORD" ]; then
    read -r record_window last folded < "$AWAY_NOTIFY_RECORD" || true
  fi
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  case "$folded" in ''|*[!0-9]*) folded=0 ;; esac
  if [ "$record_window" != "$window" ]; then
    last=0
    folded=0
  fi
  tmp="$AWAY_NOTIFY_RECORD.tmp.$$"
  if [ "$last" -gt 0 ] && [ $((now - last)) -lt "$min" ]; then
    folded=$((folded + 1))
    if ! { printf '%s %s %s\n' "$window" "$last" "$folded" > "$tmp" && mv -f "$tmp" "$AWAY_NOTIFY_RECORD"; }; then
      warn "could not record a rate-limited alert; it is listed in the return brief"
    fi
    fm_lock_release "$AWAY_NOTIFY_LOCK"
    printf 'fm-away-notify: rate-limited; %s outcome(s) will be counted in the next alert\n' "$folded" >&2
    return 0
  fi
  if ! { printf '%s %s 0\n' "$window" "$now" > "$tmp" && mv -f "$tmp" "$AWAY_NOTIFY_RECORD"; }; then
    warn "could not record this alert's time; the rate limit may not apply to the next one"
  fi
  fm_lock_release "$AWAY_NOTIFY_LOCK"
  printf '%s\n' "$folded"
}

cmd_send() {
  local summary='' record window now folded message cmd rc timeout
  local -a commands=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --summary) summary=${2:-}; shift 2 || usage ;;
      *) usage ;;
    esac
  done
  [ -n "$summary" ] || usage
  fm_afk_contract_away_present "$STATE" || return 0
  while IFS= read -r cmd; do
    commands+=("$cmd")
  done < <(configured_commands)
  [ "${#commands[@]}" -gt 0 ] || return 0
  record=$(fm_afk_contract_path "$STATE")
  window=$(fm_afk_contract_read_field "$record" entered_epoch 2>/dev/null || true)
  now=$(date +%s)
  folded=$(reserve_alert "${window:-unknown}" "$now" "$(min_secs)")
  [ -n "$folded" ] || return 0
  message="Firstmate: $(one_line "$summary")"
  [ "$folded" -eq 0 ] || message="$message (+$folded more waiting since the last alert)"
  timeout=$(fm_notify_timeout "${FM_AWAY_NOTIFY_TIMEOUT_SECS:-}")
  for cmd in "${commands[@]}"; do
    fm_notify_run_bounded "$timeout" AWAY_NOTIFY_PID fm_notify_command "$cmd" fm-away-notify "$message" \
      >/dev/null 2>&1
    rc=$?
    case "$FM_NOTIFY_BOUND" in
      timeout) warn "a phone alert command timed out (limit ${timeout}s; command redacted)" ;;
      no-watchdog) warn "a phone alert command was skipped because its watchdog could not start" ;;
      *) [ "$rc" -eq 0 ] || warn "a phone alert command exited $rc (command redacted)" ;;
    esac
  done
  return 0
}

trap 'fm_notify_stop_group "$AWAY_NOTIFY_PID"; exit 143' TERM INT HUP

CMD=${1:-}
shift 2>/dev/null || true
case "$CMD" in
  send) cmd_send "$@" ;;
  configured)
    [ "$#" -eq 0 ] || usage
    [ -n "$(configured_commands 2>/dev/null)" ]
    ;;
  *) usage ;;
esac
