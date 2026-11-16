#!/usr/bin/env bash
# Drives the real bin/fm-spawn.sh through the executor-dispatch SKILL.md exec:pro
# procedure under an active config/crew-dispatch.json, over the repo's own spawn
# fixtures (fake tmux pane + fake gh, real isolated git worktree).
set -u
cd "$1"
. tests/fixtures.sh
TMP_ROOT=$(fm_test_tmproot exec-pro-override)
case_dir="$TMP_ROOT/c"; home="$case_dir/home"; proj="$case_dir/project"; wt="$case_dir/wt"; log="$case_dir/launch.log"
fakebin=$(fm_test_make_spawn_fakebin "$case_dir/fake")
printf '#!/usr/bin/env bash\nshift\nexec "$@"\n' > "$fakebin/timeout"; chmod +x "$fakebin/timeout"
printf '#!/usr/bin/env bash\n[ "${1:-}" = --version ] && echo 1.18.35\nexit 0\n' > "$fakebin/opencode"; chmod +x "$fakebin/opencode"
fm_test_spawn_home "$home"
printf '%s\n' '- project [direct-PR] - fixture (added 2026-07-01)' > "$home/data/projects.md"
fm_git_worktree "$proj" "$wt" wt-c
printf 'FOREMAN_VERIFY_CMD="make ci"\n' > "$proj/.foreman.local"
printf 'ready-for-agent\nexec:pro\n' > "$case_dir/labels"
cat > "$fakebin/gh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$case_dir/gh.log'
case " \$* " in
  *" api user "*) echo captain ;;
  *" repo view "*) echo 'captain/project' ;;
  *" issue view "*"--json labels"*) cat '$case_dir/labels' ;;
  *" issue edit "*) exit 0 ;;
  *) exit 1 ;;
esac
SH
chmod +x "$fakebin/gh"
id=exec-pro-1
FM_ROOT_OVERRIDE='' FM_HOME="$home" FM_DATA_OVERRIDE="$home/data" FM_STATE_OVERRIDE="$home/state" \
  bin/fm-brief.sh "$id" project --executor --issue 7 --verify 'make ci' >/dev/null
# active dispatch config; the recorded resolution holds the BASE profile only
printf '%s\n' '{"rules":[{"when":"anything","use":{"harness":"opencode","model":"deepseek/deepseek-flash"}}],"default":{"harness":"opencode","model":"deepseek/deepseek-flash"}}' > "$home/config/crew-dispatch.json"
mkdir -p "$home/data/$id"
printf '%s\n' "{\"task\":\"$id\",\"status\":\"clear\",\"profile\":{\"harness\":\"opencode\",\"model\":\"deepseek/deepseek-flash\",\"effort\":null}}" > "$home/data/$id/dispatch-resolution.json"
run() { : > "$log"; CLAUDE_CONFIG_DIR='' FM_FAKE_LAUNCH_LOG="$log" fm_test_run_spawn "$home" "$wt" "$fakebin" "$@"; }
echo "== 1. base profile flags (what the dispatch selection names) on an exec:pro issue"
echo "\$ fm-spawn.sh $id <proj> --executor --issue 7 --yolo off --harness opencode --model deepseek/deepseek-flash --pro opencode:deepseek/deepseek-v4-pro"
run "$id" "$proj" --executor --issue 7 --yolo off --harness opencode --model deepseek/deepseek-flash --pro opencode:deepseek/deepseek-v4-pro 2>&1; echo "exit=$?"
echo; echo "== 2. pro profile flags WITHOUT --dispatch-override"
echo "\$ fm-spawn.sh $id <proj> --executor --issue 7 --yolo off --harness opencode --model deepseek/deepseek-v4-pro --pro opencode:deepseek/deepseek-v4-pro"
run "$id" "$proj" --executor --issue 7 --yolo off --harness opencode --model deepseek/deepseek-v4-pro --pro opencode:deepseek/deepseek-v4-pro 2>&1; echo "exit=$?"
echo; echo "== 3. documented procedure: pro profile + --dispatch-override naming exec:pro"
echo "\$ fm-spawn.sh $id <proj> --executor --issue 7 --yolo off --harness opencode --model deepseek/deepseek-v4-pro --pro opencode:deepseek/deepseek-v4-pro --dispatch-override 'issue carries exec:pro'"
run "$id" "$proj" --executor --issue 7 --yolo off --harness opencode --model deepseek/deepseek-v4-pro --pro opencode:deepseek/deepseek-v4-pro --dispatch-override 'issue carries exec:pro' 2>&1; echo "exit=$?"
echo; echo "-- task meta:"; grep -E 'executor_pro|harness|model|dispatch' "$home/state/$id.meta"
echo "-- launch command:"; fm_test_launch_unframe "$(cat "$log")" | head -c 600; echo
echo "-- gh label writes:"; grep 'issue edit' "$case_dir/gh.log"
rm -rf "$TMP_ROOT"
