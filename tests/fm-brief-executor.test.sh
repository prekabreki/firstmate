#!/usr/bin/env bash
# Behavior tests for bin/fm-brief.sh --executor: the short one-shot executor
# brief (AGENTS.md section 7, the executor-dispatch skill).
#
#   (a) scaffold shape: short, numbered, names the issue, branch, and gate,
#       and ends with the machine-readable delivery-contract line the spawn checks
#   (b) --issue and --verify are required and validated; a literal <VERIFY>
#       placeholder is refused
#   (c) no status-file protocol, no steering-inbox section, no no-mistakes
#       definition of done, no project-memory section, no {TASK} placeholders
#   (d) --mode, --scout, --secondmate, and --herdr-lab are refused with
#       --executor; --issue and --verify are refused without it
#   (e) fm_brief_executor_issue reads the contract line and rejects ship briefs
#   (f) without --verify, a foreman-onboarded project's gate is read through the
#       real `foreman` CLI: FOREMAN_VERIFY_CMD alone, composed with matched path
#       legs (each in its own subshell, proven by running it), refused on an
#       unbacked leg, refused loudly when foreman is missing, and never sourced
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-marker-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-classify-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-dod-lib.sh"

BRIEF_BIN="$ROOT/bin/fm-brief.sh"
TMP_ROOT=$(fm_test_tmproot fm-brief-executor)

run_brief() {  # <home> <args...>
  local home=$1
  shift
  FM_ROOT_OVERRIDE='' FM_HOME="$home" FM_DATA_OVERRIDE="$home/data" FM_STATE_OVERRIDE="$home/state" \
    "$BRIEF_BIN" "$@" 2>&1
}

new_home() {  # <name>
  local home="$TMP_ROOT/$1"
  mkdir -p "$home/data" "$home/state"
  printf '%s\n' "$home"
}

test_executor_scaffold_shape() {
  local home out rc brief lines
  home=$(new_home shape)
  out=$(run_brief "$home" exec-shape-a1 widget-repo --executor --issue 42 --verify 'make ci'); rc=$?
  expect_code 0 "$rc" "executor scaffold should succeed: $out"
  assert_contains "$out" "scaffolded: $home/data/exec-shape-a1/brief.md (executor, issue=42)" "scaffold report"
  brief="$home/data/exec-shape-a1/brief.md"
  [ -f "$brief" ] || fail "brief not written"
  lines=$(wc -l < "$brief" | tr -d ' ')
  [ "$lines" -lt 60 ] || fail "an executor brief must stay well under 60 lines, got $lines"
  assert_grep 'gh issue view 42' "$brief" "the brief reads the issue"
  assert_grep 'git push -u origin fm/exec-shape-a1' "$brief" "the brief pushes the task branch"
  assert_grep 'git branch --show-current' "$brief" "the brief asserts the branch it was launched on"
  assert_grep 'make ci' "$brief" "the brief carries the resolved gate"
  assert_grep 'Close #42:' "$brief" "the commit message carries Close #N"
  assert_grep 'Closes #42' "$brief" "the pull request body closes the issue"
  assert_grep '--body-file .fm-pr-body.md' "$brief" "the pull request body is a file inside the worktree"
  assert_grep '--draft' "$brief" "a draft is required when the gate cannot pass"
  assert_grep 'never weaken, skip, delete, or loosen a test' "$brief" "tests are never weakened"
  assert_grep 'Never merge' "$brief" "executors never merge"
  assert_grep 'git rev-parse --show-toplevel' "$brief" "the worktree-isolation assertion is present"
  [ "$(tail -n 1 "$brief")" = 'Delivery contract: kind=executor issue=42' ] \
    || fail "the brief must end with the exact delivery-contract line, got: $(tail -n 1 "$brief")"
  assert_grep 'widget-repo' "$brief" "the brief names the project"
  out=$(run_brief "$home" exec-shape-a1 widget-repo --executor --issue 42 --verify 'make ci'); rc=$?
  expect_code 1 "$rc" "an existing brief is never overwritten"
  pass "executor scaffold: short, numbered, issue-driven, and ends with the delivery contract"
}

test_executor_brief_omits_interactive_contracts() {
  local home brief
  home=$(new_home omit)
  run_brief "$home" exec-omit-b1 widget-repo --executor --issue 3 --verify 'npm test' >/dev/null
  brief="$home/data/exec-omit-b1/brief.md"
  assert_no_grep '.status' "$brief" "no status-file protocol"
  assert_no_grep 'needs-decision' "$brief" "no decision-state protocol"
  assert_no_grep 'instruction inbox' "$brief" "no steering-inbox section"
  assert_no_grep '.inbox' "$brief" "no inbox path"
  assert_no_grep 'no-mistakes' "$brief" "no no-mistakes definition of done"
  assert_no_grep 'Project memory' "$brief" "no project-memory section"
  assert_no_grep 'fm-ensure-agents-md' "$brief" "no AGENTS.md authoring instruction"
  assert_no_grep '{TASK}' "$brief" "no Task placeholder"
  assert_no_grep '{FIRSTMATE_SPEC}' "$brief" "no Firstmate spec placeholder"
  assert_no_grep '## Captain' "$brief" "no intent subsection"
  assert_no_grep 'Herdr' "$brief" "no Herdr lifecycle declaration"
  pass "executor brief carries none of the interactive worker contracts"
}

test_issue_and_verify_are_required_and_validated() {
  local home out rc
  home=$(new_home required)
  out=$(run_brief "$home" exec-req-c1 widget-repo --executor --verify 'make ci'); rc=$?
  expect_code 1 "$rc" "missing --issue must refuse"
  assert_contains "$out" 'requires --issue' "missing --issue names the flag"
  out=$(run_brief "$home" exec-req-c1 widget-repo --executor --issue 0 --verify 'make ci'); rc=$?
  expect_code 1 "$rc" "issue 0 must refuse"
  out=$(run_brief "$home" exec-req-c1 widget-repo --executor --issue 12a --verify 'make ci'); rc=$?
  expect_code 1 "$rc" "a non-numeric issue must refuse"
  assert_contains "$out" 'positive integer' "invalid issue names the shape"
  out=$(run_brief "$home" exec-req-c1 widget-repo --executor --issue 12); rc=$?
  expect_code 1 "$rc" "missing --verify must refuse"
  assert_contains "$out" 'no --verify given' "missing --verify on a non-onboarded project names the flag"
  out=$(run_brief "$home" exec-req-c1 widget-repo --executor --issue 12 --verify '   '); rc=$?
  expect_code 1 "$rc" "a blank --verify must refuse"
  out=$(run_brief "$home" exec-req-c1 widget-repo --executor --issue 12 --verify 'run <VERIFY>'); rc=$?
  expect_code 1 "$rc" "a literal <VERIFY> placeholder must refuse"
  assert_contains "$out" '<VERIFY> placeholder' "the placeholder refusal names it"
  [ ! -e "$home/data/exec-req-c1/brief.md" ] || fail "a refused scaffold must write nothing"
  pass "--issue and --verify are required, shape-checked, and refused when placeholder-literal"
}

test_executor_flag_exclusions() {
  local home out rc
  home=$(new_home excl)
  out=$(run_brief "$home" exec-x-d1 widget-repo --executor --issue 5 --verify 'make ci' --mode direct-PR); rc=$?
  expect_code 1 "$rc" "--mode with --executor must refuse"
  assert_contains "$out" 'inherently direct-PR' "the mode refusal explains the implied delivery"
  out=$(run_brief "$home" exec-x-d1 widget-repo --executor --scout --issue 5 --verify 'make ci'); rc=$?
  expect_code 1 "$rc" "--scout with --executor must refuse"
  assert_contains "$out" 'exactly one' "conflicting kinds are named"
  out=$(run_brief "$home" exec-x-d1 --executor --secondmate --issue 5 --verify 'make ci'); rc=$?
  expect_code 1 "$rc" "--secondmate with --executor must refuse"
  out=$(run_brief "$home" exec-x-d1 widget-repo --executor --issue 5 --verify 'make ci' --herdr-lab); rc=$?
  expect_code 1 "$rc" "--herdr-lab with --executor must refuse"
  assert_contains "$out" 'herdr-lab' "the herdr-lab refusal names the flag"
  out=$(run_brief "$home" exec-x-d1 widget-repo --executor --issue 5 --verify 'make ci' --base-branch dev); rc=$?
  expect_code 1 "$rc" "--base-branch with --executor must refuse"
  assert_contains "$out" 'base-branch' "the base-branch refusal names the flag"
  out=$(run_brief "$home" ship-x-d2 widget-repo --mode direct-PR --issue 5); rc=$?
  expect_code 1 "$rc" "--issue without --executor must refuse"
  assert_contains "$out" 'apply only to --executor' "the ship refusal names the executor flag"
  out=$(run_brief "$home" scout-x-d3 widget-repo --scout --verify 'make ci'); rc=$?
  expect_code 1 "$rc" "--verify without --executor must refuse"
  [ ! -e "$home/data/exec-x-d1/brief.md" ] || fail "a refused scaffold must write nothing"
  pass "--executor is exclusive with --mode, --scout, --secondmate, and --herdr-lab; --issue/--verify need it"
}

test_contract_reader() {
  local home issue
  home=$(new_home reader)
  run_brief "$home" exec-read-e1 widget-repo --executor --issue 77 --verify 'make ci' >/dev/null
  issue=$(fm_brief_executor_issue "$home/data/exec-read-e1/brief.md") || fail "reader failed on an executor brief"
  [ "$issue" = 77 ] || fail "reader returned '$issue', expected 77"
  run_brief "$home" ship-read-e2 widget-repo --mode direct-PR >/dev/null
  ! fm_brief_executor_issue "$home/data/ship-read-e2/brief.md" >/dev/null \
    || fail "reader accepted a ship brief as an executor brief"
  printf 'The Delivery contract: kind=executor issue=5 line is mentioned in prose\n' > "$home/data/prose.md"
  ! fm_brief_executor_issue "$home/data/prose.md" >/dev/null \
    || fail "a prose mention of the contract must not read as the contract"
  pass "fm_brief_executor_issue reads exactly the executor contract line"
}


FOREMAN_BIN=$(command -v foreman 2>/dev/null || true)

# An onboarded project clone under the home's projects dir, plus a fakebin whose
# gh serves one issue body to foreman compose-verify. Echoes the fakebin.
onboard_project() {  # <home> <repo> <foreman-local-body> <issue-body>
  local home=$1 repo=$2 cfg=$3 body=$4 fakebin
  mkdir -p "$home/projects/$repo"
  printf '%s\n' "$cfg" > "$home/projects/$repo/.foreman.local"
  fakebin="$home/fakebin"
  mkdir -p "$fakebin"
  python3 -c 'import json,sys; print(json.dumps({"body": sys.argv[1]}))' "$body" > "$home/issue.json"
  cat > "$fakebin/gh" <<SH
#!/usr/bin/env bash
case " \$* " in
  *" issue view "*"--json body"*) cat '$home/issue.json' ;;
  *) echo "fake gh: unexpected \$*" >&2; exit 1 ;;
esac
SH
  chmod +x "$fakebin/gh"
  printf '%s\n' "$fakebin"
}

run_brief_path() {  # <path> <home> <args...>
  local path=$1 home=$2
  shift 2
  PATH="$path" FM_ROOT_OVERRIDE='' FM_HOME="$home" FM_DATA_OVERRIDE="$home/data" FM_STATE_OVERRIDE="$home/state" \
    FM_PROJECTS_OVERRIDE="$home/projects" "$BRIEF_BIN" "$@" 2>&1
}

# The issue bodies carry literal markdown backticks, not command substitutions.
# shellcheck disable=SC2016
test_foreman_gate_read_without_verify() {
  local home fakebin out rc brief marker
  if [ -z "$FOREMAN_BIN" ]; then pass "SKIP: foreman not on PATH"; return 0; fi
  home=$(new_home foreman-base)
  marker="$home/pwned"
  fakebin=$(onboard_project "$home" widget-repo "touch $marker
FOREMAN_VERIFY_CMD=\"make ci && make lint\"" 'Touches `src/a.py`.')
  out=$(run_brief_path "$fakebin:$(dirname "$FOREMAN_BIN"):$PATH" "$home" exec-fg-f1 widget-repo --executor --issue 9); rc=$?
  expect_code 0 "$rc" "an onboarded project scaffolds without --verify: $out"
  brief="$home/data/exec-fg-f1/brief.md"
  assert_grep 'make ci && make lint' "$brief" "the brief carries FOREMAN_VERIFY_CMD verbatim when no leg is declared"
  [ ! -e "$marker" ] || fail ".foreman.local must never be executed"
  out=$(run_brief_path "$fakebin:$(dirname "$FOREMAN_BIN"):$PATH" "$home" exec-fg-f2 widget-repo --executor --issue 9 --verify 'make other'); rc=$?
  expect_code 0 "$rc" "an explicit --verify still scaffolds"
  assert_grep 'make other' "$home/data/exec-fg-f2/brief.md" "an explicit --verify wins over .foreman.local"
  pass "without --verify the onboarded project's gate is read through foreman, never by sourcing"
}

# The issue bodies carry literal markdown backticks, not command substitutions.
# shellcheck disable=SC2016
test_foreman_two_legs_compose_and_run() {
  local home fakebin out rc proj gate
  if [ -z "$FOREMAN_BIN" ]; then pass "SKIP: foreman not on PATH"; return 0; fi
  home=$(new_home foreman-legs)
  fakebin=$(onboard_project "$home" widget-repo 'FOREMAN_VERIFY_CMD="test -f top.txt"
FOREMAN_VERIFY_LEGS="
sub/** = cd sub && test -f here.txt
web/** = test -f top.txt
"' 'Files: `sub/a.py` and `web/b.ts`.')
  out=$(run_brief_path "$fakebin:$(dirname "$FOREMAN_BIN"):$PATH" "$home" exec-fl-f3 widget-repo --executor --issue 9); rc=$?
  expect_code 0 "$rc" "two backed legs scaffold: $out"
  gate='( test -f top.txt ) && ( cd sub && test -f here.txt ) && ( test -f top.txt )'
  assert_grep "$gate" "$home/data/exec-fl-f3/brief.md" "both legs compose, each in its own subshell"
  # Run the composed gate end to end: the second leg passes only if the first
  # leg's cd stayed inside its subshell, and a failing leg reddens the whole.
  proj="$home/projects/widget-repo"
  mkdir -p "$proj/sub"
  : > "$proj/top.txt"
  : > "$proj/sub/here.txt"
  (cd "$proj" && eval "$gate") || fail "the composed gate must pass when every leg passes from the right directory"
  rm "$proj/sub/here.txt"
  ! (cd "$proj" && eval "$gate") || fail "a failing leg must fail the composed gate"
  pass "two path legs compose in subshells and the composed gate runs correctly end to end"
}

# The issue bodies carry literal markdown backticks, not command substitutions.
# shellcheck disable=SC2016
test_foreman_unbacked_leg_refuses() {
  local home fakebin out rc
  if [ -z "$FOREMAN_BIN" ]; then pass "SKIP: foreman not on PATH"; return 0; fi
  home=$(new_home foreman-unbacked)
  fakebin=$(onboard_project "$home" widget-repo 'FOREMAN_VERIFY_CMD="make ci"
FOREMAN_VERIFY_LEGS="
frontend/** =
"' 'Touches `frontend/app.ts`.')
  out=$(run_brief_path "$fakebin:$(dirname "$FOREMAN_BIN"):$PATH" "$home" exec-fu-f4 widget-repo --executor --issue 9); rc=$?
  expect_code 1 "$rc" "an unbacked leg must refuse the scaffold"
  assert_contains "$out" 'WARN #9 touches frontend/**' "foreman's WARN line reaches the operator"
  assert_contains "$out" 'refusing to scaffold exec-fu-f4' "the refusal names the task"
  [ ! -e "$home/data/exec-fu-f4/brief.md" ] || fail "a refused scaffold must write no brief"
  pass "an issue touching a declared-but-unbacked leg refuses the scaffold with foreman's WARN"
}

test_foreman_missing_fails_loudly() {
  local home fakebin out rc path
  home=$(new_home foreman-missing)
  fakebin=$(onboard_project "$home" widget-repo 'FOREMAN_VERIFY_CMD="make ci"' 'x')
  # PATH without any foreman: only the fakebin and the system dirs.
  path="$fakebin:/usr/bin:/bin"
  out=$(run_brief_path "$path" "$home" exec-fm-f5 widget-repo --executor --issue 9); rc=$?
  expect_code 1 "$rc" "a missing foreman must refuse"
  assert_contains "$out" "'foreman' is not on PATH" "the refusal names the missing tool"
  [ ! -e "$home/data/exec-fm-f5/brief.md" ] || fail "no brief with an empty gate"
  pass "a missing foreman fails loudly instead of scaffolding an empty gate"
}

test_executor_scaffold_shape
test_executor_brief_omits_interactive_contracts
test_issue_and_verify_are_required_and_validated
test_executor_flag_exclusions
test_contract_reader
test_foreman_gate_read_without_verify
test_foreman_two_legs_compose_and_run
test_foreman_unbacked_leg_refuses
test_foreman_missing_fails_loudly
