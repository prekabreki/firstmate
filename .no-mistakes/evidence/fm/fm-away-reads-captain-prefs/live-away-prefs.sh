#!/usr/bin/env bash
# Live driver: real supervision host + real Claude engine in a disposable lab copy
# of the change's checkout. Usage: live-away-prefs.sh <label> <prefs:yes|no> <decision-text>
set -u
ROOT=/home/prekabreki/.no-mistakes/worktrees/4046fed7c36e/01M63TDBXBTRYCFQ7Z2TEXN815
EV=/home/prekabreki/.no-mistakes/evidence/01M63TDBXBTRYCFQ7Z2TEXN815
LABEL=$1 PREFS=$2 DECISION=$3
OUT="$EV/$LABEL"; mkdir -p "$OUT"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); LAB=$(cd -P "$LAB" && pwd -P)
FM="$LAB/fm"
mkdir -p "$LAB/harness" "$FM" "$LAB/tmuxbin"
ln -s /bin/bash "$LAB/harness/claude"
stop_lab() {
  local pid
  if [ -f "$FM/state/.supervision-host" ]; then
    pid=$(awk -F '\t' '$1 == "host" { print $2; exit }' "$FM/state/.supervision-host")
    [ -z "$pid" ] || kill -TERM "$pid" 2>/dev/null || true; sleep 2
  fi
  pid=$(cat "$FM/state/.watch.lock/pid" 2>/dev/null || true)
  [ -z "$pid" ] || kill -TERM "$pid" 2>/dev/null || true
  while IFS= read -r pid; do [ -z "$pid" ] || kill -TERM "$pid" 2>/dev/null || true; done < "$LAB/claude-pids" 2>/dev/null || true
  sleep 1; rm -rf "$LAB"
}
trap stop_lab EXIT
if [ -n "${SRC_REV:-}" ]; then git -C "$ROOT" archive "$SRC_REV" | tar -x -C "$FM"; else git -C "$ROOT" ls-files -z -co --exclude-standard | (cd "$ROOT" && tar --null -T - -cf -) | (cd "$FM" && tar -xf -); fi
git -C "$FM" init -q -b main; git -C "$FM" add -A >/dev/null
git -C "$FM" -c user.name=fmtest -c user.email=fmtest@example.invalid commit -q -m lab
mkdir -p "$FM/state" "$FM/config" "$FM/data"
: > "$FM/config/supervision-host"
printf '#!/usr/bin/env bash\nexit 1\n' > "$LAB/tmuxbin/tmux"; chmod +x "$LAB/tmuxbin/tmux"
printf 'project=zero-parades\nwindow=fm-zp-story\nharness=claude\nkind=ship\n' > "$FM/state/zp-story.meta"
if [ "$PREFS" = yes ]; then
  cat > "$FM/data/captain.md" <<'P'
# Captain preferences

- Zero Parades: Story calls that would need plot detail are firstmate's to decide under the Capable Cop rule (the cop is always competent; pick the option where she acts capably and keeps momentum). Do not hold them for the captain.
- Never spend money or accept terms on the captain's behalf.
P
  cp "$FM/data/captain.md" "$OUT/captain.md"
fi
FM_HOME="$FM" "$FM/bin/fm-afk-contract.sh" enter --words 'Going to bed. Keep pushing Zero Parades.' > "$OUT/afk-enter.txt" 2>&1 || { echo "contract failed"; exit 1; }
export FM_POLL=1 FM_SIGNAL_GRACE=0 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999
unset FM_SUPERVISION_ENGINE_CLAUDE_BIN FM_SUPERVISION_ACTOR FM_BRANCH_REPORT_TURN FM_LEASE_HOLDER_PID
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_CONFIG_OVERRIDE FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE PI_CODING_AGENT NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS
FM_HOME="$FM" PATH="$LAB/tmuxbin:$PATH" "$LAB/harness/claude" -c '
  printf "%s\n" "$$" > "$FM_HOME/state/.lock"; printf "%s\n" "$$" >> "$1/claude-pids"
  "$FM_HOME/bin/fm-supervision-host.sh" park > "$1/host.out" 2>&1; printf "%s\n" "$?" > "$1/host.rc"
' _ "$LAB" 2>> "$LAB/harness.err" &
wait_until() { local l=$1 i=0; shift; while [ $i -lt $l ]; do "$@" && return 0; sleep 0.1; i=$((i+1)); done; return 1; }
watcher_live() { local p; p=$(cat "$FM/state/.watch.lock/pid" 2>/dev/null) || return 1; [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
settled() { grep -qE '	(handled|failed)	' "$FM/state/.supervision-host.log" 2>/dev/null || [ -s "$LAB/host.rc" ]; }
wait_until 300 watcher_live || { echo "no watcher"; cat "$LAB/host.out"; exit 1; }
printf 'needs-decision [key=story-order]: %s\n' "$DECISION" >> "$FM/state/zp-story.status"
wait_until 6000 settled || echo "TIMEOUT waiting for engine turn"
sleep 3
{
  echo "### host log"; cat "$FM/state/.supervision-host.log" 2>/dev/null
  echo "### host.out / rc"; cat "$LAB/host.out" 2>/dev/null; cat "$LAB/host.rc" 2>/dev/null
  echo "### zp-story.status"; cat "$FM/state/zp-story.status"
  echo "### worker inbox"; find "$FM/state/zp-story.inbox" -type f -exec sh -c 'echo "--- $1"; cat "$1"' _ {} \; 2>/dev/null
  echo "### branch-outcomes.jsonl"; cat "$FM/state/branch-outcomes.jsonl" 2>/dev/null
} > "$OUT/state.txt"
# Capture the wake prompt the host sent (the engine turn's input), if persisted.
ls -la "$FM/state" > "$OUT/state-ls.txt"
for f in "$FM"/state/.supervision-host-wake* "$FM"/state/.supervision-host-turn*; do [ -f "$f" ] && { echo "--- $f"; cat "$f"; }; done > "$OUT/wake-files.txt" 2>/dev/null
# Wake prompt as the real dispatch CLI renders it for this home now:
FM_HOME="$FM" "$FM/bin/fm-afk-contract.sh" readback > "$LAB/rb" 2>/dev/null
printf 'signal: zp-story.status\n' | FM_HOME="$FM" node "$FM/bin/fm-branch-dispatch.mjs" wake-prompt --report 'the bin/fm-branch-report.sh command' --away --readback-file "$LAB/rb" > "$OUT/away-wake-prompt.txt" 2>&1
# Stop the host before the return brief.
pid=$(awk -F '\t' '$1 == "host" { print $2; exit }' "$FM/state/.supervision-host" 2>/dev/null); [ -z "$pid" ] || kill -TERM "$pid"; sleep 4
FM_HOME="$FM" PATH="$LAB/tmuxbin:$PATH" "$FM/bin/fm-afk-return.sh" > "$OUT/return-brief.txt" 2>&1; echo "rc=$?" >> "$OUT/return-brief.txt"
echo "done $LABEL"
