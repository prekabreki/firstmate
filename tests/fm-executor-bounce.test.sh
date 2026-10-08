#!/usr/bin/env bash
# Behavior tests for bin/fm-executor-bounce.sh: the executor-dispatch skill's
# BOUNCE verdict as one command, over a fake gh that logs every call.
#   (a) first bounce on a foreman-onboarded project: the pull request is closed
#       with the comment and no branch deletion, and the issue gains bounced +
#       needs-replan and loses in-progress
#   (b) second bounce (issue already carries bounced) escalates to needs-human
#   (c) a plain project closes the pull request and writes no label
#   (d) refusals before anything is closed: a pull request whose head is not
#       fm/<id>, one that is not OPEN, an empty comment, a non-executor task,
#       and a repository the captain does not own
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BOUNCE="$ROOT/bin/fm-executor-bounce.sh"
TMP_ROOT=$(fm_test_tmproot fm-executor-bounce)
URL=https://github.com/captain/proj/pull/12

# make_case <name> <labels> [kind] [owner] [pr-state] [pr-head] -> case dir
make_case() {
  local name=$1 labels=$2 kind=${3:-executor} owner=${4:-captain} prstate=${5:-OPEN} prhead=${6:-fm/ex1}
  local dir="$TMP_ROOT/$name"
  mkdir -p "$dir/state" "$dir/proj" "$dir/fakebin"
  printf 'project=%s\nkind=%s\nissue=5\n' "$dir/proj" "$kind" > "$dir/state/ex1.meta"
  printf '%s\n' "$labels" > "$dir/labels"
  printf 'Bounced: the verify gate was weakened in tests/test_x.py.\n' > "$dir/comment.md"
  cat > "$dir/fakebin/gh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$dir/gh.log'
case " \$* " in
  *" api user "*) echo captain ;;
  *" repo view "*) echo '$owner/proj' ;;
  *" pr view "*) printf '%s\t%s\n' '$prstate' '$prhead' ;;
  *" pr close "*) exit 0 ;;
  *" issue view "*"--json labels"*) cat '$dir/labels' ;;
  *" issue edit "*) exit 0 ;;
  *) exit 1 ;;
esac
SH
  chmod +x "$dir/fakebin/gh"
  printf '%s\n' "$dir"
}

onboard() {  # <dir>
  printf 'FOREMAN_VERIFY_CMD="make ci"\n' > "$1/proj/.foreman.local"
}

run_bounce() {  # <dir> [url] [comment-file]
  local dir=$1 url=${2:-$URL} comment=${3:-$1/comment.md}
  PATH="$dir/fakebin:$PATH" FM_ROOT_OVERRIDE='' FM_HOME="$dir" FM_STATE_OVERRIDE="$dir/state" \
    "$BOUNCE" ex1 "$url" "$comment" 2>&1
}

closed() {  # <dir>
  grep -q '^pr close ' "$1/gh.log" 2>/dev/null
}

test_first_bounce_replans() {
  local dir out rc
  dir=$(make_case first $'in-progress\nbug')
  onboard "$dir"
  out=$(run_bounce "$dir"); rc=$?
  expect_code 0 "$rc" "a first bounce should succeed: $out"
  [ "$out" = "bounced ex1 pr=$URL issue=#5 label=needs-replan" ] || fail "unexpected outcome line: $out"
  grep -qx "pr close $URL --comment Bounced: the verify gate was weakened in tests/test_x.py." "$dir/gh.log" \
    || fail "the pull request must be closed with the comment: $(cat "$dir/gh.log")"
  ! grep -q -- '--delete-branch' "$dir/gh.log" || fail "a bounce must keep the remote branch"
  grep -qx 'issue edit 5 --add-label bounced,needs-replan --remove-label in-progress' "$dir/gh.log" \
    || fail "a first bounce must add bounced + needs-replan: $(cat "$dir/gh.log")"
  pass "a first bounce closes the PR with its comment, keeps the branch, and replans the issue"
}

test_second_bounce_escalates() {
  local dir out rc
  dir=$(make_case second $'in-progress\nbounced')
  onboard "$dir"
  out=$(run_bounce "$dir"); rc=$?
  expect_code 0 "$rc" "a second bounce should succeed: $out"
  assert_contains "$out" "label=needs-human" "the outcome names the escalation"
  grep -qx 'issue edit 5 --add-label needs-human --remove-label in-progress' "$dir/gh.log" \
    || fail "a second bounce must escalate to needs-human: $(cat "$dir/gh.log")"
  pass "a bounce of an already-bounced issue escalates to needs-human"
}

test_plain_project_writes_no_label() {
  local dir out rc
  dir=$(make_case plain 'in-progress')
  out=$(run_bounce "$dir"); rc=$?
  expect_code 0 "$rc" "a plain-project bounce should succeed: $out"
  [ "$out" = "bounced ex1 pr=$URL" ] || fail "unexpected outcome line: $out"
  closed "$dir" || fail "the pull request must be closed"
  ! grep -q '^issue edit' "$dir/gh.log" || fail "a project without .foreman.local gets no label write"
  pass "a project without .foreman.local closes the PR and writes no label"
}

test_refusals_close_nothing() {
  local dir out rc
  dir=$(make_case wrong-head 'in-progress' executor captain OPEN fm/other)
  onboard "$dir"
  out=$(run_bounce "$dir"); rc=$?
  expect_code 1 "$rc" "a pull request on another branch must be refused"
  assert_contains "$out" "not ex1's branch fm/ex1" "the refusal names the head mismatch"
  ! closed "$dir" || fail "a head mismatch must close nothing"

  dir=$(make_case not-open 'in-progress' executor captain MERGED)
  out=$(run_bounce "$dir"); rc=$?
  expect_code 1 "$rc" "a merged pull request must be refused"
  ! closed "$dir" || fail "a non-open pull request must not be closed"

  dir=$(make_case empty-comment 'in-progress')
  : > "$dir/comment.md"
  out=$(run_bounce "$dir"); rc=$?
  expect_code 1 "$rc" "an empty comment must be refused"
  ! closed "$dir" || fail "an empty comment must close nothing"

  dir=$(make_case ship-task 'in-progress' ship)
  out=$(run_bounce "$dir"); rc=$?
  expect_code 1 "$rc" "a ship task must be refused"
  assert_contains "$out" "not an executor task" "the refusal names the kind"

  dir=$(make_case foreign 'in-progress' executor someorg)
  onboard "$dir"
  out=$(run_bounce "$dir"); rc=$?
  expect_code 1 "$rc" "a repository the captain does not own must be refused"
  assert_contains "$out" "someorg/proj is not owned by captain" "the refusal names the owner"
  ! closed "$dir" || fail "a foreign repository must not be touched"
  pass "every refusal fires before the pull request is closed"
}

test_first_bounce_replans
test_second_bounce_escalates
test_plain_project_writes_no_label
test_refusals_close_nothing
