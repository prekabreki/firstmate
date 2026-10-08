#!/usr/bin/env bash
# fm-executor-bounce.sh - bounce one executor pull request (the executor-dispatch
# skill's BOUNCE verdict): close it with firstmate's actionable review comment,
# keep its remote branch (the closed pull request and branch preserve the exact
# diff the re-scope references), and move a foreman-onboarded issue through
# foreman-status's bounce transition.
#
# Usage: fm-executor-bounce.sh <task-id> <pr-url> <comment-file>
#
# The pull request must be OPEN and its head must be the task's own fm/<id>, so
# a mistyped URL can never close somebody else's pull request. The comment file
# is the whole review comment; an empty one is refused, because the comment is
# the input to the re-scope.
#
# On a project with a .foreman.local (bin/fm-executor-lib.sh, "the foreman
# contract") the issue is then relabelled, only on a repository the captain
# owns: the first bounce adds the sticky `bounced` plus `needs-replan`; a bounce
# of an issue already carrying `bounced` adds `needs-human` instead, because a
# spec that failed the crew twice needs the captain's intent, not attempt three.
# Both remove `in-progress`. A project without .foreman.local gets no label
# write.
#
# Prints: bounced <id> pr=<url> [issue=#<N> label=<needs-replan|needs-human>]
# Exit 1 on any refusal or failure, with the reason on stderr. The pull request
# is closed before the labels move, so a label failure after a successful close
# says so and names the label to set by hand.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"

case "${1:-}" in
  -h|--help)
    sed -n '2,${/^#/!q;p;}' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

# shellcheck source=bin/fm-backend.sh
. "$SCRIPT_DIR/fm-backend.sh"
# shellcheck source=bin/fm-pr-lib.sh
. "$SCRIPT_DIR/fm-pr-lib.sh"
# shellcheck source=bin/fm-executor-lib.sh
. "$SCRIPT_DIR/fm-executor-lib.sh"

die() { echo "error: $*" >&2; exit 1; }

[ "$#" -eq 3 ] || die "usage: fm-executor-bounce.sh <task-id> <pr-url> <comment-file>"
ID=$1 URL=$2 COMMENT_FILE=$3

fm_pr_task_id_valid "$ID" || die "invalid task id '$ID'"
META="$STATE/$ID.meta"
[ -f "$META" ] && [ ! -L "$META" ] || die "no task record for $ID at $META"
[ "$(fm_meta_get "$META" kind)" = executor ] || die "$ID is not an executor task; bounce applies only to executor pull requests"
ISSUE=$(fm_meta_get "$META" issue)
fm_executor_issue_valid "$ISSUE" || die "$ID records no valid issue="
PROJ=$(fm_meta_get "$META" project)
[ -n "$PROJ" ] && [ -d "$PROJ" ] || die "$ID's recorded project '${PROJ:-none}' is missing"
fm_pr_url_parse "$URL" && [ "$FM_PR_PROVIDER" = github ] || die "'$URL' is not a GitHub pull-request URL"
[ -f "$COMMENT_FILE" ] && [ -s "$COMMENT_FILE" ] || die "the review comment file '$COMMENT_FILE' is missing or empty; the comment is what the re-scope works from"

FOREMAN=0
[ ! -f "$(fm_executor_foreman_config "$PROJ")" ] || FOREMAN=1
if [ "$FOREMAN" -eq 1 ]; then
  # Refuse before anything is closed, so a foreign repository is never touched.
  fm_executor_repo_owned "$PROJ" >/dev/null || die "refusing to bounce $ID: the foreman label lifecycle cannot run on this repository"
fi

PR_FACTS=$(cd "$PROJ" && gh pr view "$URL" --json state,headRefName --jq '[.state, .headRefName] | @tsv' 2>/dev/null) \
  || die "gh could not read $URL"
PR_STATE=${PR_FACTS%%$'\t'*}
PR_HEAD=${PR_FACTS#*$'\t'}
[ "$PR_HEAD" = "fm/$ID" ] || die "$URL's head is '$PR_HEAD', not $ID's branch fm/$ID; refusing to close it"
[ "$PR_STATE" = OPEN ] || die "$URL is $PR_STATE, not OPEN; nothing to bounce"

(cd "$PROJ" && gh pr close "$URL" --comment "$(cat "$COMMENT_FILE")") >/dev/null \
  || die "gh could not close $URL; nothing was relabelled"

if [ "$FOREMAN" -eq 0 ]; then
  echo "bounced $ID pr=$URL"
  exit 0
fi
LABEL=$(fm_executor_issue_bounce "$PROJ" "$ISSUE") \
  || die "$URL was closed, but issue #$ISSUE could not be relabelled; set '$FM_EXECUTOR_LABEL_BOUNCED' and '$FM_EXECUTOR_LABEL_REPLAN' (or '$FM_EXECUTOR_LABEL_HUMAN' if it was already bounced) by hand"
echo "bounced $ID pr=$URL issue=#$ISSUE label=$LABEL"
