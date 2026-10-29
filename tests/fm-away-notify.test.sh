#!/usr/bin/env bash
# tests/fm-away-notify.test.sh - the away-mode phone alert
# (bin/fm-away-notify.sh, config/away-notify): one alert per captain outcome
# recorded while away, through the outcome store's public append; silence when
# attended, in quiet mode, and for routine outcomes; no re-send when the drain
# re-presents an unacknowledged outcome; rate-limit folding into the next
# alert, reset per away window; and a failing or hung command never breaking or
# stalling the caller. The captain-hold caller is covered in
# tests/fm-captain-hold-lifecycle.test.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }

OUTCOMES="$ROOT/bin/fm-branch-outcome.sh"
NOTIFY="$ROOT/bin/fm-away-notify.sh"
CONTRACT="$ROOT/bin/fm-afk-contract.sh"
TMP_ROOT=$(fm_test_tmproot fm-away-notify-tests)

# A home whose config/away-notify records each alert's $1 and stdin.
make_home() {  # <name> -> prints the home dir
  local home="$TMP_ROOT/$1"
  mkdir -p "$home/state" "$home/config"
  cat > "$home/config/away-notify" <<EOF
# the captain's phone
command:printf '%s\n' "\$1" >> '$home/alerts'; cat >> '$home/stdin'
EOF
  printf '%s\n' "$home"
}

in_home() {  # <home> <command> [args...]
  local home=$1
  shift
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" FM_CONFIG_OVERRIDE="$home/config" "$@"
}

go_away() {  # <home>
  in_home "$1" "$CONTRACT" enter --words 'keep the fleet moving' >/dev/null 2>&1 \
    || fail "could not enter away mode"
}

append() {  # <home> <verdict> <summary>
  in_home "$1" "$OUTCOMES" append --task fm-alpha --verdict "$2" --summary "$3"
}

alert_count() {  # <home>
  if [ -f "$1/alerts" ]; then wc -l < "$1/alerts" | tr -d ' '; else printf '0\n'; fi
}

test_each_captain_outcome_while_away_alerts_once() {
  local home seq
  home=$(make_home away)
  go_away "$home"
  seq=$(FM_AWAY_NOTIFY_MIN_SECS=0 append "$home" captain 'the alpha fix needs your merge decision') \
    || fail "captain append failed"
  [ "$seq" = 1 ] || fail "append did not print its sequence (got '$seq')"
  [ "$(cat "$home/alerts")" = 'Firstmate: the alpha fix needs your merge decision' ] \
    || fail "the alert text was not passed as \$1: $(cat "$home/alerts")"
  [ "$(cat "$home/stdin")" = 'Firstmate: the alpha fix needs your merge decision' ] \
    || fail "the alert text was not passed on stdin: $(cat "$home/stdin")"
  FM_AWAY_NOTIFY_MIN_SECS=0 append "$home" captain $'a credential\nis needed' >/dev/null \
    || fail "second captain append failed"
  [ "$(alert_count "$home")" = 2 ] || fail "two captain outcomes did not alert twice: $(cat "$home/alerts")"
  assert_contains "$(cat "$home/alerts")" 'Firstmate: a credential is needed' \
    "a multi-line summary was not sent as one line"
  pass "each captain outcome recorded while away alerts once, with the text as \$1 and on stdin"
}

test_drain_re_presentation_never_re_sends() {
  local home
  home=$(make_home drain)
  go_away "$home"
  FM_AWAY_NOTIFY_MIN_SECS=0 append "$home" captain 'the beta scout found a product call' >/dev/null \
    || fail "captain append failed"
  in_home "$home" "$OUTCOMES" present >/dev/null || fail "present failed"
  in_home "$home" "$OUTCOMES" present >/dev/null || fail "second present failed"
  in_home "$home" "$OUTCOMES" mark-read --through 1 || fail "mark-read failed"
  in_home "$home" "$OUTCOMES" unprocessed >/dev/null || fail "unprocessed failed"
  [ "$(alert_count "$home")" = 1 ] \
    || fail "re-presenting an unacknowledged outcome re-sent its alert: $(cat "$home/alerts")"
  pass "presenting an unacknowledged captain outcome again never re-sends its alert"
}

test_attended_quiet_and_routine_never_alert() {
  local home
  home=$(make_home attended)
  FM_AWAY_NOTIFY_MIN_SECS=0 append "$home" captain 'attended captain outcome' >/dev/null \
    || fail "attended captain append failed"
  [ "$(alert_count "$home")" = 0 ] || fail "an attended session alerted the phone"

  home=$(make_home quiet)
  FM_AFK_MODE=quiet in_home "$home" "$CONTRACT" enter >/dev/null 2>&1 || fail "could not enter quiet mode"
  [ "$(in_home "$home" "$CONTRACT" mode)" = quiet ] || fail "the fixture is not in quiet mode"
  FM_AWAY_NOTIFY_MIN_SECS=0 append "$home" captain 'quiet captain outcome' >/dev/null \
    || fail "quiet captain append failed"
  [ "$(alert_count "$home")" = 0 ] || fail "quiet mode alerted the phone"

  home=$(make_home routine)
  go_away "$home"
  FM_AWAY_NOTIFY_MIN_SECS=0 append "$home" routine 'merged the gamma fix' >/dev/null \
    || fail "routine append failed"
  [ "$(alert_count "$home")" = 0 ] || fail "a routine outcome alerted the phone"
  FM_AWAY_NOTIFY_MIN_SECS=0 append "$home" captain 'the delta fix needs you' >/dev/null \
    || fail "captain append failed"
  [ "$(alert_count "$home")" = 1 ] || fail "the away home did not alert for its captain outcome"
  pass "attended sessions, quiet mode, and routine outcomes never alert"
}

test_absent_or_off_config_is_silent() {
  local home
  home=$(make_home absent)
  rm -f "$home/config/away-notify"
  go_away "$home"
  in_home "$home" "$NOTIFY" configured && fail "an absent config read as configured"
  FM_AWAY_NOTIFY_MIN_SECS=0 append "$home" captain 'nobody listens' >/dev/null || fail "append failed"
  [ ! -e "$home/state/.away-notify" ] || fail "an absent config still recorded an alert"

  home=$(make_home off)
  printf 'off\n' >> "$home/config/away-notify"
  go_away "$home"
  in_home "$home" "$NOTIFY" configured && fail "a config holding off read as configured"
  FM_AWAY_NOTIFY_MIN_SECS=0 append "$home" captain 'switched off' >/dev/null || fail "append failed"
  [ "$(alert_count "$home")" = 0 ] || fail "an off directive did not silence the command above it"
  pass "an absent config, or one holding off, sends nothing"
}

test_rate_limit_folds_outcomes_into_the_next_alert() {
  local home last
  home=$(make_home ratelimit)
  go_away "$home"
  FM_AWAY_NOTIFY_MIN_SECS=600 append "$home" captain 'first call' >/dev/null || fail "append 1 failed"
  FM_AWAY_NOTIFY_MIN_SECS=600 append "$home" captain 'second call' >/dev/null 2>&1 || fail "append 2 failed"
  FM_AWAY_NOTIFY_MIN_SECS=600 append "$home" captain 'third call' >/dev/null 2>&1 || fail "append 3 failed"
  [ "$(alert_count "$home")" = 1 ] || fail "outcomes inside the window were sent: $(cat "$home/alerts")"
  FM_AWAY_NOTIFY_MIN_SECS=0 append "$home" captain 'fourth call' >/dev/null || fail "append 4 failed"
  [ "$(alert_count "$home")" = 2 ] || fail "the next alert after the window was not sent"
  last=$(tail -n 1 "$home/alerts")
  [ "$last" = 'Firstmate: fourth call (+2 more waiting since the last alert)' ] \
    || fail "the next alert did not carry the folded count: $last"
  FM_AWAY_NOTIFY_MIN_SECS=0 append "$home" captain 'fifth call' >/dev/null || fail "append 5 failed"
  [ "$(tail -n 1 "$home/alerts")" = 'Firstmate: fifth call' ] \
    || fail "a carried count was sent twice: $(tail -n 1 "$home/alerts")"
  pass "outcomes inside the rate-limit window are counted into the next alert, never dropped"
}

test_a_new_away_window_starts_without_a_carried_count() {
  local home
  home=$(make_home window)
  go_away "$home"
  FM_AWAY_NOTIFY_MIN_SECS=600 append "$home" captain 'old window call' >/dev/null || fail "append 1 failed"
  FM_AWAY_NOTIFY_MIN_SECS=600 append "$home" captain 'old folded call' >/dev/null 2>&1 || fail "append 2 failed"
  in_home "$home" "$CONTRACT" archive >/dev/null 2>&1 || fail "could not archive the away record"
  sleep 1
  go_away "$home"
  FM_AWAY_NOTIFY_MIN_SECS=600 append "$home" captain 'new window call' >/dev/null || fail "append 3 failed"
  [ "$(alert_count "$home")" = 2 ] || fail "the new away window inherited the old window's limit"
  [ "$(tail -n 1 "$home/alerts")" = 'Firstmate: new window call' ] \
    || fail "the new away window carried the old window's count: $(tail -n 1 "$home/alerts")"
  pass "a new away window starts with no rate-limit window and no carried count"
}

test_failing_or_hung_commands_never_break_the_caller() {
  local home seq start elapsed err
  home=$(make_home failing)
  cat > "$home/config/away-notify" <<EOF
command:exit 7
command:sleep 30
command:printf '%s\n' "\$1" >> '$home/alerts'
command:/nonexistent/phone-tool "\$1"
EOF
  go_away "$home"
  err="$home/append.err"
  start=$SECONDS
  seq=$(FM_AWAY_NOTIFY_MIN_SECS=0 FM_AWAY_NOTIFY_TIMEOUT_SECS=1 \
    append "$home" captain 'the epsilon fix needs you' 2> "$err") \
    || fail "a failing alert command broke the append: $(cat "$err")"
  elapsed=$((SECONDS - start))
  [ "$seq" = 1 ] || fail "the append did not report its sequence (got '$seq')"
  [ "$elapsed" -lt 8 ] || fail "a hung alert command held the append for ${elapsed}s"
  assert_contains "$(cat "$err")" 'exited 7' "a failing command was not logged"
  assert_contains "$(cat "$err")" 'timed out' "a hung command was not logged"
  assert_contains "$(cat "$err")" 'exited 127' "a missing command was not logged"
  assert_not_contains "$(cat "$err")" 'sleep 30' "a warning revealed the configured command"
  [ "$(alert_count "$home")" = 1 ] || fail "a failing command stopped the next channel"
  [ "$(in_home "$home" "$OUTCOMES" list | jq -r '.summary')" = 'the epsilon fix needs you' ] \
    || fail "the outcome was not stored"
  pass "a failing, hung, or missing command logs a warning and never breaks or stalls the caller"
}

fm_test_run \
  test_each_captain_outcome_while_away_alerts_once \
  test_drain_re_presentation_never_re_sends \
  test_attended_quiet_and_routine_never_alert \
  test_absent_or_off_config_is_silent \
  test_rate_limit_folds_outcomes_into_the_next_alert \
  test_a_new_away_window_starts_without_a_carried_count \
  test_failing_or_hung_commands_never_break_the_caller
