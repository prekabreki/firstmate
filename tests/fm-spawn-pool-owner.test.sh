#!/usr/bin/env bash
# fm-spawn.sh and fm-treehouse-pool-owner.sh against a Treehouse pool that
# belongs to another clone of the same repository.
#
# Treehouse keys a pool on the repository, not the clone path, so a project
# clone can resolve to a pool whose slots are worktrees of the captain's other
# clone. A spawn used to lease such a slot, open its pane, and only then refuse
# deep in trust setup, leaving the lease held and a pane it could not close.
# These cases pin the replacement: the pool is read before any pane, record, or
# lease exists; a slot that turns foreign after that read has its fresh lease
# returned unless it holds work; symlinked paths to one clone never read as a
# mismatch; and project-add intake gets the same warning.
#
# Canned/stateful fakes only - never a real herdr session or a real pool.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
OWNER="$ROOT/bin/fm-treehouse-pool-owner.sh"
TMP_ROOT=$(fm_test_tmproot fm-spawn-pool-owner)
mkdir -p "$TMP_ROOT"
TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)

# make_pool_case <name> <foreign|own>: a home; a project clone and a second
# clone of the same upstream; and a Treehouse-shaped pool whose slot 1 is a
# worktree of the second clone (foreign) or of the project itself (own).
# The fake treehouse lists $D/status.json for `status --json`, leases
# $FM_FAKE_SLOT, and records a return.
make_pool_case() {
  local name=$1 owner=$2 dir home d fb slot_parent
  dir="$TMP_ROOT/$name"
  home="$dir/home"
  d="$dir/fake"
  fb="$dir/fakebin"
  mkdir -p "$d" "$fb" "$dir/user-home"
  fm_test_spawn_home "$home" codex
  fm_git_init_commit "$dir/upstream-src"
  git clone -q --bare "$dir/upstream-src" "$dir/upstream.git"
  git clone -q "$dir/upstream.git" "$dir/project"
  git clone -q "$dir/upstream.git" "$dir/other-clone"
  mkdir -p "$dir/pool/1"
  printf '{}\n' > "$dir/pool/treehouse-state.json"
  slot_parent=$dir/other-clone
  [ "$owner" = foreign ] || slot_parent=$dir/project
  git -C "$slot_parent" worktree add -q --detach "$dir/pool/1/repo"
  fm_test_spawn_brief "$home" "$name" "Exercise the Treehouse pool owner check for $name."
  printf '[{"name":"1","path":"%s","status":"available","processes":[]}]\n' "$dir/pool/1/repo" > "$d/status.json"
  printf '%s' "$dir/project" > "$d/cwd"
  printf '%s' "$dir/project" > "$d/fg"
  : > "$d/treehouse-log"
  : > "$d/herdr-log"
  cat > "$fb/treehouse" <<'SH'
#!/usr/bin/env bash
set -u
D=$FM_FAKE_DIR
printf '%s\n' "$*" >> "$D/treehouse-log"
case "$*" in
  'status --json') [ ! -f "$D/status-fails" ] || exit 1; cat "$D/status.json" ;;
  'get --lease '*) printf '%s\n' "$FM_FAKE_SLOT" ;;
  'get') printf '%s' "$FM_FAKE_SLOT" > "$D/fg" ;;
  'return --force '*) : > "$D/returned" ;;
esac
exit 0
SH
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
D=$FM_FAKE_DIR
printf '%s\n' "$*" >> "$D/herdr-log"
if [ "${1:-}" = status ] && [ "${2:-}" = --json ]; then
  printf '{"client":{"version":"0.9.0","protocol":22},"server":{"running":true}}\n'
  exit 0
fi
[ "${1:-}" != server ] || exit 0
case "${1:-} ${2:-}" in
  'session list') exit 0 ;;
  'pane close') : > "$D/pane-gone"; exit 0 ;;
  'pane get')
    [ ! -f "$D/pane-gone" ] || { printf '{"error":{"code":"pane_not_found"}}\n'; exit 0; }
    printf '{"result":{"pane":{"pane_id":"%s","cwd":"%s","foreground_cwd":"%s"}}}\n' \
      "${3:-}" "$(cat "$D/cwd")" "$(cat "$D/fg")"
    exit 0 ;;
  'pane run' | 'pane send-text')
    payload=${4:-}
    case "$payload" in
      ". '"*"'") staged=${payload#". '"}; staged=${staged%"'"}; [ ! -f "$staged" ] || payload=$(cat "$staged") ;;
    esac
    case "$payload" in
      'cd -- '*) path=${payload#cd -- }; path=${path#\'}; path=${path%\'}
        bash -c 'cd -- "$1" && pwd -P > "$2"' bash "$path" "$D/cwd"
        cp "$D/cwd" "$D/fg" ;;
      *'encode launch-brief'* | *'Firstmate operational input waiting: read'*)
        printf '%s\n' "$payload" > "$D/launched-command"
        : > "$D/herdr-agent-live" ;;
    esac
    exit 0 ;;
  'agent get')
    if [ -f "$D/herdr-agent-live" ]; then
      printf '{"result":{"agent":{"agent_status":"idle"}}}\n'
    else
      printf '{"result":{"agent":{"agent_status":"shell-starting"}}}\n'
    fi
    exit 0 ;;
  'workspace list') printf '{"result":{"workspaces":[]}}\n'; exit 0 ;;
  'workspace create')
    printf '{"result":{"workspace":{"workspace_id":"wsnew"},"tab":{"tab_id":"seedtab"},"root_pane":{"pane_id":"%%1"}}}\n'
    exit 0 ;;
  'tab list') printf '{"result":{"tabs":[]}}\n'; exit 0 ;;
  'tab create')
    printf '{"result":{"tab":{"tab_id":"tabnew"},"root_pane":{"pane_id":"%%9"}}}\n'
    exit 0 ;;
esac
exit 0
SH
  chmod +x "$fb/treehouse" "$fb/herdr"
  fm_test_fake_sleep_noop "$fb"
  printf '%s\n' "$dir"
}

run_pool_spawn() {  # <case-dir> <id> <project-path> <slot-path>
  local dir=$1 id=$2 project=$3 slot=$4
  env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SESSION -u HERDR_SOCKET_PATH \
    -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID \
    PATH="$dir/fakebin:$PATH" FM_HOME="$dir/home" FM_FAKE_DIR="$dir/fake" \
    FM_FAKE_SLOT="$slot" HOME="$dir/user-home" CLAUDE_CONFIG_DIR='' \
    FM_SPAWN_NO_GUARD=1 \
    "$SPAWN" "$id" "$project" --backend herdr --mode no-mistakes --yolo off 2>&1
}

assert_no_pane_or_record() {  # <case-dir> <id> <context>
  local dir=$1 id=$2 context=$3
  ! grep -qE '^(workspace|tab) create' "$dir/fake/herdr-log" \
    || fail "$context created a Herdr workspace or tab"
  ! grep -q '^pane run\|^pane send-text' "$dir/fake/herdr-log" \
    || fail "$context typed into a pane"
  [ ! -e "$dir/home/state/$id.meta" ] || fail "$context published task metadata"
  [ ! -e "$dir/pool/1/.fm-slot-owner" ] || fail "$context claimed the foreign slot"
  [ ! -e "$dir/fake/launched-command" ] || fail "$context launched an agent"
}

test_foreign_pool_refuses_before_any_pane_record_or_lease() {
  local id=pool-foreign dir out status
  dir=$(make_pool_case "$id" foreign)
  out=$(run_pool_spawn "$dir" "$id" "$dir/project" "$dir/pool/1/repo")
  status=$?
  [ "$status" -ne 0 ] || fail "spawn went on into another clone's pool"$'\n'"$out"
  assert_contains "$out" "is a worktree of '$dir/other-clone'" "the refusal did not name the owning clone"$'\n'"$out"
  assert_contains "$out" "(cd '$dir/other-clone' && treehouse destroy '$dir/pool' --all)" \
    "the refusal did not name the exact remedy"$'\n'"$out"
  assert_grep 'status --json' "$dir/fake/treehouse-log" "the pool was not read before leasing"
  ! grep -q '^get' "$dir/fake/treehouse-log" || fail "the spawn leased a slot from another clone's pool"
  ! grep -q '^return' "$dir/fake/treehouse-log" || fail "a refusal with no lease returned a slot"
  [ -z "$(git -C "$dir/pool/1/repo" status --porcelain)" ] || fail "the refusal touched the foreign slot"
  assert_no_pane_or_record "$dir" "$id" "a pre-lease refusal"
  pass "a pool owned by another clone is refused before any pane, record, or lease"
}

test_slot_turning_foreign_after_the_read_returns_its_clean_lease() {
  local id=pool-race-clean dir out status
  dir=$(make_pool_case "$id" foreign)
  printf '[]\n' > "$dir/fake/status.json"
  out=$(run_pool_spawn "$dir" "$id" "$dir/project" "$dir/pool/1/repo")
  status=$?
  [ "$status" -ne 0 ] || fail "spawn went on into a foreign slot"$'\n'"$out"
  assert_contains "$out" "is a worktree of '$dir/other-clone'" "the refusal did not name the owning clone"$'\n'"$out"
  assert_contains "$out" "the lease this spawn took on $dir/pool/1/repo was returned" \
    "the refusal did not report the returned lease"$'\n'"$out"
  assert_grep "get --lease --lease-holder $id" "$dir/fake/treehouse-log" "the race case never leased"
  [ -e "$dir/fake/returned" ] || fail "a clean foreign lease was left held"$'\n'"$out"
  [ ! -e "$dir/home/state/$id.meta" ] || fail "the refusal published task metadata"
  [ ! -e "$dir/pool/1/.fm-slot-owner" ] || fail "the refusal claimed the foreign slot"
  [ ! -e "$dir/fake/launched-command" ] || fail "the refusal launched an agent"
  pass "a slot found foreign after leasing is refused and its clean lease returned"
}

test_slot_turning_foreign_with_work_keeps_its_lease() {
  local id=pool-race-dirty dir out status
  dir=$(make_pool_case "$id" foreign)
  printf '[]\n' > "$dir/fake/status.json"
  echo 'unlanded' > "$dir/pool/1/repo/notes.txt"
  out=$(run_pool_spawn "$dir" "$id" "$dir/project" "$dir/pool/1/repo")
  status=$?
  [ "$status" -ne 0 ] || fail "spawn went on into a foreign slot"$'\n'"$out"
  [ ! -e "$dir/fake/returned" ] || fail "the refusal returned a slot holding uncommitted work"
  assert_grep unlanded "$dir/pool/1/repo/notes.txt" "the refusal discarded the slot's work"
  assert_contains "$out" "stays leased to $id" "a kept lease was not named"$'\n'"$out"
  assert_contains "$out" "treehouse return --force $dir/pool/1/repo" "a kept lease did not name its release command"
  [ ! -e "$dir/home/state/$id.meta" ] || fail "the refusal published task metadata"
  pass "a foreign slot holding work keeps its lease and names the release"
}

test_slot_turning_foreign_in_an_interactive_get_closes_its_window() {
  local id=pool-race-tmux dir out status
  dir=$(make_pool_case "$id" foreign)
  printf '[]\n' > "$dir/fake/status.json"
  fm_test_fake_tmux_spawn "$dir/fakebin"
  out=$(env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SESSION -u HERDR_SOCKET_PATH \
    -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID \
    PATH="$dir/fakebin:$PATH" FM_HOME="$dir/home" FM_FAKE_DIR="$dir/fake" \
    FM_FAKE_PANE_PATH="$dir/pool/1/repo" TMUX="fake,1,0" \
    HOME="$dir/user-home" CLAUDE_CONFIG_DIR='' FM_SPAWN_NO_GUARD=1 \
    "$SPAWN" "$id" "$dir/project" --backend tmux --mode no-mistakes --yolo off 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "spawn went on into a foreign slot"$'\n'"$out"
  assert_contains "$out" "is a worktree of '$dir/other-clone'" "the refusal did not name the owning clone"$'\n'"$out"
  [ -f "$dir/fakebin/.spawn-window" ] || fail "the race case never opened a window"$'\n'"$out"
  [ ! -s "$dir/fakebin/.spawn-window" ] \
    || fail "the window whose treehouse get holds the foreign slot was left open"$'\n'"$out"
  assert_not_contains "$out" "inspect window" "the refusal pointed at a window it should have closed"$'\n'"$out"
  [ ! -e "$dir/home/state/$id.meta" ] || fail "the refusal published task metadata"
  [ ! -e "$dir/pool/1/.fm-slot-owner" ] || fail "the refusal claimed the foreign slot"
  pass "a slot found foreign inside an interactive treehouse get closes the window holding it"
}

test_symlinked_paths_to_the_same_clone_are_not_a_mismatch() {
  local id=pool-symlinked dir out status
  dir=$(make_pool_case "$id" own)
  ln -s "$dir/project" "$dir/project-link"
  ln -s "$dir/pool" "$dir/pool-link"
  printf '[{"name":"1","path":"%s","status":"available","processes":[]}]\n' \
    "$dir/pool-link/1/repo" > "$dir/fake/status.json"
  out=$(run_pool_spawn "$dir" "$id" "$dir/project-link" "$dir/pool-link/1/repo")
  status=$?
  expect_code 0 "$status" "a symlinked path to the project's own pool was refused"$'\n'"$out"
  assert_not_contains "$out" "belongs to another clone" "symlinked paths read as a foreign pool"
  assert_grep "get --lease --lease-holder $id" "$dir/fake/treehouse-log" "the own pool was not leased"
  [ -e "$dir/home/state/$id.meta" ] || fail "the spawn into its own pool left no task record"
  pass "symlinked paths to the project's own clone and pool spawn normally"
}

test_intake_warns_about_a_foreign_pool() {
  local dir out status
  dir=$(make_pool_case intake-foreign foreign)
  out=$(PATH="$dir/fakebin:$PATH" FM_FAKE_DIR="$dir/fake" bash "$OWNER" "$dir/project")
  status=$?
  expect_code 1 "$status" "intake did not flag a foreign pool"$'\n'"$out"
  assert_contains "$out" "warning: Treehouse pool '$dir/pool' belongs to another clone" "intake warning missing"$'\n'"$out"
  assert_contains "$out" "(cd '$dir/other-clone' && treehouse destroy '$dir/pool' --all)" "intake warning lacked the remedy"
  ! grep -qv '^status --json$' "$dir/fake/treehouse-log" || fail "intake ran a treehouse command other than status"
  pass "project-add intake warns about a pool owned by another clone"
}

test_intake_accepts_its_own_pool_and_reports_an_unreadable_one() {
  local dir out status
  dir=$(make_pool_case intake-own own)
  ln -s "$dir/project" "$dir/project-link"
  out=$(PATH="$dir/fakebin:$PATH" FM_FAKE_DIR="$dir/fake" bash "$OWNER" "$dir/project-link")
  status=$?
  expect_code 0 "$status" "intake flagged the project's own pool"$'\n'"$out"
  assert_contains "$out" "ok: " "intake did not report its own pool as fine"
  : > "$dir/fake/status-fails"
  out=$(PATH="$dir/fakebin:$PATH" FM_FAKE_DIR="$dir/fake" bash "$OWNER" "$dir/project")
  status=$?
  expect_code 3 "$status" "intake did not report an unreadable pool"$'\n'"$out"
  assert_contains "$out" "unknown: could not read the Treehouse pool" "intake hid an unreadable pool"
  pass "project-add intake accepts its own pool and reports an unreadable one"
}

test_foreign_pool_refuses_before_any_pane_record_or_lease
test_slot_turning_foreign_after_the_read_returns_its_clean_lease
test_slot_turning_foreign_with_work_keeps_its_lease
test_slot_turning_foreign_in_an_interactive_get_closes_its_window
test_symlinked_paths_to_the_same_clone_are_not_a_mismatch
test_intake_warns_about_a_foreign_pool
test_intake_accepts_its_own_pool_and_reports_an_unreadable_one

echo "# all fm-spawn-pool-owner tests passed"
