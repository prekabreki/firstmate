#!/usr/bin/env bash
# Drives the away-mode phone alert through the real firstmate entrypoints in a
# disposable, marked lab home. Run from the gate worktree.
set -u
W=$PWD
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
rmdir "$LAB"; "$W/bin/fm-lab-home.sh" create "$LAB" >/dev/null
trap 'rm -rf "$LAB"' EXIT
cat > "$LAB/.tasks.toml" <<'TOML'
backend = "markdown"

[markdown]
path = "data/backlog.md"
archive = "data/done-archive.md"
done_keep = 10
TOML
printf '## In flight\n\n## Queued\n\n## Done\n' > "$LAB/data/backlog.md"
mkdir -p "$LAB/phone"
run() { env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" "$@"; }
phone() { if [ -f "$LAB/phone/inbox" ]; then cat "$LAB/phone/inbox"; else echo '(phone inbox empty)'; fi; }
count() { [ -f "$LAB/phone/inbox" ] && wc -l < "$LAB/phone/inbox" | tr -d ' ' || echo 0; }
hdr() { printf '\n===== %s =====\n' "$*"; }
# A stand-in phone channel in the gitignored config: same shape as the kdeconnect line,
# but appends $1 to an inbox and stdin to a second file.
write_cfg() { cat > "$LAB/config/away-notify" <<EOF
# the captain's phone (lab stand-in for kdeconnect-cli -d <id> --ping-msg "\$1")
command:printf '%s\n' "\$1" >> '$LAB/phone/inbox'; cat >> '$LAB/phone/stdin'
EOF
}

hdr "S1 announcement WITHOUT config/away-notify (fm-afk-launch.sh enter)"
run "$W/bin/fm-afk-launch.sh" enter --words 'keep the fleet moving' 2>&1 | head -3
run "$W/bin/fm-afk-contract.sh" field reach_channels
run "$W/bin/fm-afk-launch.sh" stop >/dev/null 2>&1 || run "$W/bin/fm-afk-contract.sh" archive >/dev/null 2>&1
sleep 1

hdr "S2 announcement WITH config/away-notify"
write_cfg
run "$W/bin/fm-afk-launch.sh" enter --words 'keep the fleet moving' 2>&1 | head -3
run "$W/bin/fm-afk-contract.sh" field reach_channels
echo "session-start away line:"; run "$W/bin/fm-session-start.sh" 2>/dev/null | grep -i 'away posture' | head -2

hdr "S3 captain outcome while away -> one alert, \$1 and stdin"
FM_AWAY_NOTIFY_MIN_SECS=0 run "$W/bin/fm-branch-outcome.sh" append --task fm-alpha --verdict captain --summary $'PR #12 for alpha is green and needs your merge call\n(merge is captain-only)'; echo "append rc=$?"
echo "phone \$1:"; phone; echo "phone stdin:"; cat "$LAB/phone/stdin"

hdr "S4 routine outcome while away -> no alert"
FM_AWAY_NOTIFY_MIN_SECS=0 run "$W/bin/fm-branch-outcome.sh" append --task fm-beta --verdict routine --summary 'merged beta docs fix'; echo "append rc=$? alerts=$(count)"

hdr "S5 drain re-presents the unacknowledged captain outcome -> no re-send"
for i in 1 2; do run "$W/bin/fm-branch-outcome.sh" present >/dev/null 2>&1; done
run "$W/bin/fm-branch-outcome.sh" unprocessed 2>/dev/null | head -3
run "$W/bin/fm-wake-drain.sh" 2>&1 | grep -i -A3 'BRANCH OUTCOMES' | head -6
run "$W/bin/fm-wake-drain.sh" >/dev/null 2>&1
echo "alerts after repeated presentation/drain: $(count)"

hdr "S6 rate limit (default 600s): three outcomes in the window, then window passes"
rm -f "$LAB/state/.away-notify"
run "$W/bin/fm-branch-outcome.sh" append --task fm-g1 --verdict captain --summary 'gamma needs a product call' >/dev/null
run "$W/bin/fm-branch-outcome.sh" append --task fm-g2 --verdict captain --summary 'delta needs a credential' >/dev/null
run "$W/bin/fm-branch-outcome.sh" append --task fm-g3 --verdict captain --summary 'epsilon is blocked on you' >/dev/null
echo "rate record: $(cat "$LAB/state/.away-notify")"
# simulate the window elapsing by aging the recorded last-send epoch by 601s
read -r win last folded < "$LAB/state/.away-notify"; printf '%s %s %s\n' "$win" $((last-601)) "$folded" > "$LAB/state/.away-notify"
run "$W/bin/fm-branch-outcome.sh" append --task fm-g4 --verdict captain --summary 'zeta needs your answer' >/dev/null
echo "last 2 phone lines:"; tail -n 2 "$LAB/phone/inbox"

hdr "S7 failing / missing / hung command never breaks or stalls append"
cat > "$LAB/config/away-notify" <<EOF
command:exit 7
command:sleep 60
command:/nonexistent/kdeconnect-cli --ping-msg "\$1"
command:printf '%s\n' "\$1" >> '$LAB/phone/inbox'
EOF
s=$SECONDS
seq=$(FM_AWAY_NOTIFY_MIN_SECS=0 FM_AWAY_NOTIFY_TIMEOUT_SECS=2 run "$W/bin/fm-branch-outcome.sh" append --task fm-eta --verdict captain --summary 'eta needs your decision' 2>"$LAB/err"); rc=$?
echo "append rc=$rc seq=$seq elapsed=$((SECONDS-s))s"; cat "$LAB/err"; echo "last phone line: $(tail -n1 "$LAB/phone/inbox")"
echo "hung sleeps left running: $(pgrep -f 'sleep 60' -c || true)"
write_cfg

hdr "S8 away-daemon shape: new captain hold by main while away -> one alert; repeat/branch/--until do not"
before=$(count)
FM_AWAY_NOTIFY_MIN_SECS=0 run "$W/bin/fm-captain-hold.sh" hold lab-cut --title 'Pick the release cut' --reason 'two candidate cuts, captain decides' --repo sample; echo "hold rc=$?"
FM_AWAY_NOTIFY_MIN_SECS=0 run "$W/bin/fm-captain-hold.sh" hold lab-cut --reason 'two candidate cuts, captain decides' >/dev/null; echo "repeat hold rc=$?"
FM_AWAY_NOTIFY_MIN_SECS=0 FM_SUPERVISION_ACTOR=branch run "$W/bin/fm-captain-hold.sh" hold lab-branch --title 'Branch-held call' --reason 'branch held' --repo sample >/dev/null; echo "branch hold rc=$?"
FM_AWAY_NOTIFY_MIN_SECS=0 run "$W/bin/fm-captain-hold.sh" hold lab-later --title 'Revisit later' --reason 'deferred' --repo sample --until 2099-01-01 >/dev/null; echo "until hold rc=$?"
echo "new alerts from holds: $(( $(count) - before ))"; tail -n1 "$LAB/phone/inbox"

hdr "S9 quiet mode -> no alert"
run "$W/bin/fm-afk-launch.sh" stop >/dev/null 2>&1 || run "$W/bin/fm-afk-contract.sh" archive >/dev/null 2>&1
before=$(count)
FM_AFK_MODE=quiet run "$W/bin/fm-afk-contract.sh" enter >/dev/null 2>&1; echo "mode: $(run "$W/bin/fm-afk-contract.sh" mode)"
FM_AWAY_NOTIFY_MIN_SECS=0 run "$W/bin/fm-branch-outcome.sh" append --task fm-q --verdict captain --summary 'quiet captain outcome' >/dev/null
FM_AWAY_NOTIFY_MIN_SECS=0 run "$W/bin/fm-captain-hold.sh" hold lab-quiet --title 'Quiet hold' --reason 'q' --repo sample >/dev/null
echo "new alerts in quiet mode: $(( $(count) - before ))"
run "$W/bin/fm-afk-contract.sh" archive >/dev/null 2>&1

hdr "S10 attended (no away record) -> no alert"
before=$(count)
echo "away record present: $([ -f "$LAB/state/.afk-contract" ] && echo yes || echo no)"
FM_AWAY_NOTIFY_MIN_SECS=0 run "$W/bin/fm-branch-outcome.sh" append --task fm-att --verdict captain --summary 'attended captain outcome' >/dev/null
FM_AWAY_NOTIFY_MIN_SECS=0 run "$W/bin/fm-captain-hold.sh" hold lab-att --title 'Attended hold' --reason 'a' --repo sample >/dev/null
echo "new alerts while attended: $(( $(count) - before ))"

hdr "Full phone inbox"
phone
