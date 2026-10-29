#!/usr/bin/env bash
# fm-notify-lib.sh - shared mechanics of the captain-configured alert channels:
# the away-mode wedge alarm (bin/fm-supervise-daemon.sh, docs/wedge-alarm.md)
# and the away-mode phone alert (bin/fm-away-notify.sh). Sourced, never
# executed. Each consumer owns which directives it accepts and what it logs.
#
#   fm_notify_directives <file>
#       Print each directive of a channel file, one per line: every non-empty
#       line with surrounding whitespace trimmed, skipping lines that start
#       with `#`. An absent file prints nothing.
#
#   fm_notify_timeout <value>
#       Print <value> when it is a positive integer, else the default
#       FM_NOTIFY_TIMEOUT_SECS_DEFAULT (10).
#
#   fm_notify_run_bounded <timeout-secs> <pid-var> <command> [args...]
#       Run the command in the background in its own process group and wait
#       at most <timeout-secs> for it. The named variable holds the group
#       leader's pid while it runs, so a caller's shutdown can stop it with
#       fm_notify_stop_group. FM_NOTIFY_BOUND tells a caller what happened,
#       independent of the command's own exit status: `ran` (the status is the
#       command's own), `timeout` (the whole group was terminated; status 124),
#       or `no-watchdog` (job control could not start, so nothing ran; status
#       125).
#
#   fm_notify_stop_group <pid>
#       TERM, then KILL, the process group led by <pid>, and reap it.
#
#   fm_notify_command <cmd> <argv0> <summary>
#       The `command:<cmd>` channel: run <cmd> through `sh -c` with the summary
#       as $1 and on stdin, so the summary can never become shell source.

FM_NOTIFY_TIMEOUT_SECS_DEFAULT=10
FM_NOTIFY_BOUND=ran

fm_notify_directives() {  # <file>
  local line
  [ -f "$1" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] || continue
    case "$line" in '#'*) continue ;; esac
    printf '%s\n' "$line"
  done < "$1"
}

fm_notify_timeout() {  # <value>
  case "${1:-}" in
    ''|*[!0-9]*) printf '%s\n' "$FM_NOTIFY_TIMEOUT_SECS_DEFAULT" ;;
    *) if [ "$1" -gt 0 ] 2>/dev/null; then printf '%s\n' "$1"; else printf '%s\n' "$FM_NOTIFY_TIMEOUT_SECS_DEFAULT"; fi ;;
  esac
}

# shellcheck disable=SC2034  # FM_NOTIFY_BOUND is read by the callers.
fm_notify_run_bounded() {  # <timeout-secs> <pid-var> <command> [args...]
  local timeout=$1 pid_var=$2 monitor_was_on=0 pid start rc
  shift 2
  FM_NOTIFY_BOUND=ran
  case $- in *m*) monitor_was_on=1 ;; esac
  set -m 2>/dev/null || true
  case $- in
    *m*) ;;
    *) FM_NOTIFY_BOUND=no-watchdog; return 125 ;;
  esac
  "$@" &
  pid=$!
  printf -v "$pid_var" '%s' "$pid"
  start=$SECONDS
  while kill -0 "-$pid" 2>/dev/null; do
    if [ $((SECONDS - start)) -ge "$timeout" ]; then
      printf -v "$pid_var" '%s' ''
      fm_notify_stop_group "$pid"
      [ "$monitor_was_on" -eq 1 ] || set +m 2>/dev/null || true
      FM_NOTIFY_BOUND=timeout
      return 124
    fi
    sleep 0.1
  done
  if wait "$pid"; then rc=0; else rc=$?; fi
  printf -v "$pid_var" '%s' ''
  [ "$monitor_was_on" -eq 1 ] || set +m 2>/dev/null || true
  return "$rc"
}

fm_notify_stop_group() {  # <pid>
  local pid=${1:-}
  [ -n "$pid" ] || return 0
  kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  sleep 0.2
  kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

fm_notify_command() {  # <cmd> <argv0> <summary>
  sh -c "$1" "$2" "$3" <<< "$3"
}
