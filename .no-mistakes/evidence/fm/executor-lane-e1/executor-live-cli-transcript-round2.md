# Live executor dispatch, round 2: the operator stop and the review fixes

Re-driven against the real firstmate scripts in a fresh isolated sandbox after
the round-1 finding was fixed: a throwaway FM_HOME, a real git project with a
local bare `origin`, a REAL tmux server on a private socket, a local stand-in
forge (`gh`) on PATH, and an adapter stand-in compiled so its process name
really is `claude` - firstmate's own liveness classifier therefore sees an
agent process exactly as it would for the metered CLI. Everything under `bin/`
is the product itself, unmodified.

## 1. Scaffold and dispatch, end to end

    $ bin/fm-brief.sh exec-live project --executor --issue 42 --verify "bash ci.sh"
    scaffolded: .../data/exec-live/brief.md (executor, issue=42)
      (the rendered brief is the companion artifact executor-brief-rendered.md)

    $ bin/fm-spawn.sh exec-live <project> --executor --issue 42 --yolo off "bash .../executor-stub.sh"
    notice: exec-live is an executor (mode=direct-PR) while the standing posture for project is no-mistakes - less rigor ...
    spawned exec-live harness=bash kind=executor mode=direct-PR yolo=off issue=42 window=firstmate:fm-exec-live worktree=.../1/project

    pane (real tmux), the launch line the pane shell runs:
      bash .../executor-stub.sh "$('.../bin/fm-operational-input.sh' encode launch-brief < '.../launch-brief.md')"; printf '%s\n' "$?" > '.../state/exec-live.executor-exit'
      [stub] read brief (2100 bytes); implementing issue
      ci ok
      https://github.com/acme/project/pull/7

    state/exec-live.executor-exit          -> 0
    state/exec-live.check.sh               -> byte-identical to bin/fm-executor-poll.sh
    state/exec-live.meta                   -> kind=executor mode=direct-PR yolo=off issue=42
                                              executor_base=2420b8c1... executor_launched=1789716312

    $ FM_CHECK_INTERVAL=0 bin/fm-watch.sh            # the real watcher
    check: .../state/exec-live.check.sh: executor-ready: PR https://github.com/acme/project/pull/7 ready

    $ bin/fm-wake-drain.sh                            # the durable wake firstmate reads
    1789716327  1  check  .../exec-live.check.sh  check: ...: executor-ready: PR https://github.com/acme/project/pull/7 ready

    $ bin/fm-crew-state.sh exec-live
    state: done · source: executor · PR https://github.com/acme/project/pull/7 ready

## 2. The round-1 finding, re-driven: operator stop then the supervisor read

# A long-running executor, stopped by the operator (the executor-stale path
# the executor-dispatch skill tells firstmate to take).

$ bin/fm-crew-state.sh exec-stop2
state: working · source: executor · running 0m

$ bin/fm-control.sh exec-stop2 exit
stopped exec-stop2 harness=claude backend=tmux endpoint=firstmate:fm-exec-stop2 worktree=/tmp/fm-live-e2/sb/userhome/.treehouse/project-b19fb9/2/project

$ cat state/exec-stop2.executor-exit
operator-exit

$ bin/fm-crew-state.sh exec-stop2      # the supervisor read, right after the stop
state: failed · source: executor · no commits and no PR (verify likely failed before commit)

$ tmux display-message -p "#{pane_current_command}"
bash

    $ FM_CHECK_INTERVAL=0 bin/fm-watch.sh
    check: .../state/exec-stop.check.sh: executor-failed: no commits and no PR (verify likely failed before commit)
    $ bin/fm-wake-drain.sh
    1789716496  2  check  .../exec-stop.check.sh  check: ...: executor-failed: no commits and no PR (verify likely failed before commit)

Round 1 showed `state: working · source: executor · running 3m` here, with no
terminal verdict until the 2h runtime bound. The task now reads terminally the
moment the stop is proved, and the marker says the operator ended it.

## 3. Adversarial: a stop that cannot be proved must not claim one

# Adversarial: the one-shot ignores INT and TERM, so the stop cannot be proved.

$ FM_CONTROL_EXIT_WAIT=5 bin/fm-control.sh exec-hang2 exit
error: exit-delivered exec-hang2 interrupt=C-c agent-state=alive exit=unconfirmed; the executor process did not stop within 5s
rc=1

$ ls state/exec-hang2.executor-exit
ls: cannot access '/tmp/fm-live-e2/sb/home/state/exec-hang2.executor-exit': No such file or directory

$ bin/fm-crew-state.sh exec-hang2
state: working · source: executor · running 0m

The one-shot ignored SIGINT and SIGTERM, so exit failed closed, wrote no
marker, and the task still reads as honestly running.

## 4. Relaunch clears the operator marker with the freshly minted base

# The stopped incarnation left an operator-exit marker; a relaunch must not inherit it.
$ cat state/exec-stop2.executor-exit
operator-exit
base before: executor_base=2420b8c1813f2c8038eca9b56c7111023cfe9e14

$ bin/fm-control.sh exec-stop2 relaunch --note "operator stop; retrying"
WARNING: queued wakes pending - drain them with bin/fm-wake-drain.sh before anything else.
notice: exec-stop2 is an executor (mode=direct-PR) while the standing posture for project is no-mistakes - less rigor than the captain's standing posture; firstmate's real-diff review replaces the pipeline, so proceed only on a current explicit captain instruction or an intake judgment you can state
relaunched exec-stop2 harness=claude from=claude model=default effort=default backend=tmux endpoint=firstmate:fm-exec-stop2 worktree=/tmp/fm-live-e2/sb/userhome/.treehouse/project-b19fb9/2/project

$ ls state/exec-stop2.executor-exit
ls: cannot access '/tmp/fm-live-e2/sb/home/state/exec-stop2.executor-exit': No such file or directory
base after:  executor_base=2420b8c1813f2c8038eca9b56c7111023cfe9e14

$ bin/fm-crew-state.sh exec-stop2
state: working · source: executor · running 0m

## 5. Bounce and escalate: per-incarnation executor_base

# Incarnation 1 committed, pushed and opened PR 8.
$ poll exec-esc
executor-ready: PR https://github.com/acme/project/pull/8 ready

# Firstmate bounces it: PR 8 closed on the forge, branch kept.
fm/exec-esc	https://github.com/acme/project/pull/8	false	CLOSED
$ poll exec-esc
executor-failed: committed but no PR

worktree HEAD (incarnation 1 commit): 6ec85cea2f98347a29ba763e90da8acba53906f2
meta base before relaunch:          2420b8c1813f2c8038eca9b56c7111023cfe9e14

# Relaunch to escalate, into a launch environment that dies immediately.
$ bin/fm-control.sh exec-esc relaunch --note "bounced: re-scoped issue #77"
relaunched exec-esc harness=claude from=claude model=default effort=default backend=tmux endpoint=firstmate:fm-exec-esc worktree=/tmp/fm-live-e2/sb/userhome/.treehouse/project-b19fb9/4/project

meta base after relaunch: 6ec85cea2f98347a29ba763e90da8acba53906f2
--- pane:
-esc.executor-exit'
Invalid API key · Please run /login
bash-5.3$

$ bin/fm-crew-state.sh exec-esc
state: failed · source: executor · no commits and no PR (verify likely failed before commit)
$ poll exec-esc
executor-failed: no commits and no PR (verify likely failed before commit)

The second incarnation's verdict points at the launch environment, not at a
phantom commit inherited from the first one.

## 6. A running executor: silence inside the bound, stale past it

$ bin/fm-crew-state.sh exec-stop2   # relaunched, still working
state: working · source: executor · running 1m
$ poll exec-stop2                   # inside the bound: silence
(no output above = the poll stays silent)
$ FM_EXECUTOR_MAX_RUNTIME=1 poll exec-stop2
executor-stale: running 1m past the bound

## 7. Retry after a partial failure left fm/<id> behind

# Retry after a partial failure left fm/<id> behind in the shared refs.
$ git -C <project> branch fm/exec-retry main
$ bin/fm-spawn.sh exec-retry <project> --executor --issue 88 --yolo off claude
spawned exec-retry harness=claude kind=executor mode=direct-PR yolo=off issue=88 window=firstmate:fm-exec-retry worktree=/tmp/fm-live-e2/sb/userhome/.treehouse/project-b19fb9/5/project
--- pane:
https://github.com/acme/project/pull/9
bash-5.3$

# Adversarial: another worktree already holds fm/<id>, so git itself refuses.
$ bin/fm-spawn.sh exec-held <project> --executor --issue 99 --yolo off claude
error: could not create the executor branch fm/exec-held in /tmp/fm-live-e2/sb/userhome/.treehouse/project-b19fb9/6/project: fatal: 'fm/exec-held' is already used by worktree at '/tmp/fm-live-e2/sb/held/w'; inspect window firstmate:fm-exec-held

## 8. Refusals (adversarial)

$ bin/fm-promote.sh exec-esc --mode direct-PR --yolo off
WARNING: queued wakes pending - drain them with bin/fm-wake-drain.sh before anything else.
error: task exec-esc is not a scout task (kind=scout not in meta); only a scout is promoted, and an executor task already ships its own pull request, so re-scope its GitHub issue and relaunch it (bin/fm-control.sh exec-esc relaunch) or dispatch a separate ship task
rc=1

$ bin/fm-spawn.sh exec-x <project> --executor --issue 9 --yolo off gemini
WARNING: queued wakes pending - drain them with bin/fm-wake-drain.sh before anything else.
error: harness 'gemini' has no verified headless one-shot form for --executor; use one of: claude codex opencode, or pass a raw launch command (the rendered brief becomes its final argument)

$ bin/fm-spawn.sh exec-x <project> --executor --yolo off claude   # no --issue
WARNING: queued wakes pending - drain them with bin/fm-wake-drain.sh before anything else.
error: executor spawns require --issue <N>, the GitHub issue the one-shot worker closes

$ bin/fm-spawn.sh exec-x <project> --executor --issue 11 --yolo off claude   # brief says #9
WARNING: queued wakes pending - drain them with bin/fm-wake-drain.sh before anything else.
error: issue mismatch for exec-x: the brief closes issue #9 but this spawn names --issue 11; correct the flag or re-scaffold the brief so the worker's instructions and the task record agree

$ bin/fm-spawn.sh exec-x <project> --executor --issue 9 --mode direct-PR --yolo off claude
WARNING: queued wakes pending - drain them with bin/fm-wake-drain.sh before anything else.
error: --mode is refused with --executor: an executor's delivery is inherently direct-PR (push fm/<id>, open a pull request, no no-mistakes pipeline), and firstmate's real-diff review is the rigor that replaces the pipeline

$ bin/fm-send.sh exec-esc "any steering message"
WARNING: queued wakes pending - drain them with bin/fm-wake-drain.sh before anything else.
error: task exec-esc is a one-shot executor that reads no steering inbox; re-scope its GitHub issue and relaunch it with bin/fm-control.sh <id> relaunch instead of steering it

## 9. Teardown

$ bin/fm-teardown.sh exec-retry
teardown: reaping leaked worktree process(es) for exec-retry: 3317652
teardown: force-killing leaked worktree process(es) for exec-retry: 3317652
🌳 Worktree returned to pool.
/tmp/fm-live-e2/sb/project: already current
teardown exec-retry complete (window firstmate:fm-exec-retry, worktree /tmp/fm-live-e2/sb/userhome/.treehouse/project-b19fb9/5/project)
$ ls state/exec-retry.*
ls: cannot access '/tmp/fm-live-e2/sb/home/state/exec-retry.*': No such file or directory

## 10. The default-on headless-flag guard, against the adapters installed here

    $ bin/fm-test-run.sh tests/fm-executor-headless-flags-live-e2e.test.sh
    ok - claude 2.1.275 (Claude Code) advertises every flag of the executor template (claude -p)
    ok - codex codex-cli 0.153.4 advertises every flag of the executor template (codex exec)
    ok - opencode 1.18.29 advertises every flag of the executor template (opencode run)

claude has moved 2.1.274 -> 2.1.275 since docs/verification/executor.md was
written; the narrowed guard still passes on the flag tokens alone, which is the
point of dropping the vendor prose assertions.

## 11. Adversarial: the forge read fails

# Adversarial: the forge read fails. The poll must stay silent and non-zero,
# never read the failure as "no pull request".
$ poll exec-esc   (with gh failing)
stdout: []
rc=1
$ bin/fm-crew-state.sh exec-esc
state: unknown · source: executor · exited; pull-request read failed (gh unavailable or errored)
