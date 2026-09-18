# Live executor dispatch: CLI transcript

Driven against the real firstmate scripts in an isolated sandbox: a throwaway
FM_HOME, a real git project with a local bare `origin`, a REAL tmux server
(session `firstmate`), and a local stand-in for the forge on PATH (`gh`) plus
adapter stand-ins that stand where a metered model would run. Everything under
`bin/` is the product itself, unmodified.

## 1. Scaffold the one-shot brief (bin/fm-brief.sh --executor)

    $ bin/fm-brief.sh exec-live project --executor --issue 42 --verify "bash ci.sh"
    scaffolded: .../home/data/exec-live/brief.md (executor, issue=42)

    You are a one-shot executor launched by Firstmate. Work autonomously to completion, then exit: nobody is watching this session and nobody will answer a question.
    Your whole job is to close GitHub issue #42 of project with one pull request.
    ...
    4. Commit on `fm/exec-live` with a message whose first line is `Close #42: <summary>`.
    5. Push the branch: `git push -u origin fm/exec-live`.
    7. Open the pull request: `gh pr create --title "Close #42: <summary>" --body-file .fm-pr-body.md --head fm/exec-live`.
    Delivery contract: kind=executor issue=42

## 2. Dispatch it (bin/fm-spawn.sh --executor) into a real tmux pane

    $ bin/fm-spawn.sh exec-live <project> --executor --issue 42 --yolo off "bash .../executor-stub.sh"
    notice: exec-live is an executor (mode=direct-PR) while the standing posture for project is no-mistakes - less rigor ...
    spawned exec-live harness=bash kind=executor mode=direct-PR yolo=off issue=42 window=firstmate:fm-exec-live worktree=.../1/project

    state/exec-live.meta:
      kind=executor  mode=direct-PR  yolo=off  issue=42
      executor_base=f4e578278ddeb1f4c58e6aded5842848ac00ad6d
      executor_launched=1789714931

    pane (real tmux):
      bash .../executor-stub.sh "$('.../bin/fm-operational-input.sh' encode launch-brief < '.../launch-brief.md')"; printf '%s\n' "$?" > '.../state/exec-live.executor-exit'
      [stub] read brief (2100 bytes); implementing issue
      https://github.com/acme/project/pull/7

    state/exec-live.executor-exit -> 0
    pushed branch in origin: 724f9ec Close #42: add greet.sh
    state/exec-live.check.sh is byte-identical to bin/fm-executor-poll.sh

## 3. Firstmate is woken by the real watcher

    $ FM_CHECK_INTERVAL=0 bin/fm-watch.sh
    check: .../state/exec-live.check.sh: executor-ready: PR https://github.com/acme/project/pull/7 ready

    $ bin/fm-crew-state.sh exec-live
    state: done · source: executor · PR https://github.com/acme/project/pull/7 ready

## 4. Bounce and escalate: per-incarnation executor_base (task exec-esc, issue 77)

Incarnation 1 ran on the `claude` headless template, committed, pushed and opened PR 9.

    $ bin/fm-executor-poll.sh --validated ... exec-esc ...
    executor-ready: PR https://github.com/acme/project/pull/9 ready

Firstmate bounces it: PR 9 closed, branch kept.

    $ bin/fm-executor-poll.sh --validated ... exec-esc ...
    executor-failed: committed but no PR

Relaunch to escalate, into a launch environment that dies:

    $ bin/fm-control.sh exec-esc relaunch --harness claude --note "bounced: re-scoped issue #77"
    relaunched exec-esc harness=claude from=claude model=default effort=default backend=tmux endpoint=firstmate:fm-exec-esc worktree=.../3/project

    meta after relaunch:  executor_base=8a439a4911d1393785f21916617006857de1c975
    worktree HEAD (incarnation 1's commit): 8a439a4911d1393785f21916617006857de1c975

    pane: Invalid API key · Please run /login

    $ bin/fm-executor-poll.sh --validated ... exec-esc ...
    executor-failed: no commits and no PR (verify likely failed before commit)

The second incarnation's verdict points at the launch environment, not at a
phantom commit inherited from the first one.

## 5. Retry after a partial failure left fm/<id> behind (task exec-retry, issue 88)

    $ git -C <project> branch fm/exec-retry main        # stale branch from an earlier partial spawn
    $ bin/fm-spawn.sh exec-retry <project> --executor --issue 88 --yolo off claude
    spawned exec-retry harness=claude kind=executor mode=direct-PR yolo=off issue=88 window=firstmate:fm-exec-retry worktree=.../4/project
    pane: https://github.com/acme/project/pull/10

## 6. Refusals (adversarial)

    $ bin/fm-spawn.sh exec-held <project> --executor --issue 99 --yolo off claude   # another worktree holds fm/exec-held
    error: could not create the executor branch fm/exec-held in .../5/project: fatal: 'fm/exec-held' is already used by worktree at '/tmp/.../held'; inspect window firstmate:fm-exec-held

    $ bin/fm-spawn.sh exec-refuse <project> --executor --issue 9 --yolo off gemini
    error: harness 'gemini' has no verified headless one-shot form for --executor; use one of: claude codex opencode, or pass a raw launch command (the rendered brief becomes its final argument)

    $ bin/fm-spawn.sh exec-refuse <project> --executor --issue 9 --yolo off --mode direct-PR claude
    error: --mode is refused with --executor: an executor's delivery is inherently direct-PR ...

    $ bin/fm-spawn.sh exec-refuse <project> --executor --yolo off claude
    error: executor spawns require --issue <N>, the GitHub issue the one-shot worker closes

    $ bin/fm-spawn.sh exec-refuse <project> --executor --issue 11 --yolo off claude   # brief says #9
    error: issue mismatch for exec-refuse: the brief closes issue #9 but this spawn names --issue 11; correct the flag or re-scaffold the brief ...

    $ bin/fm-promote.sh exec-live --mode direct-PR --yolo off
    error: task exec-live is not a scout task (kind=scout not in meta); only a scout is promoted, and an executor task already ships its own pull request, so re-scope its GitHub issue and relaunch it (bin/fm-control.sh exec-live relaunch) or dispatch a separate ship task

## 7. A running executor: silence, the stale bound, and exit (task exec-long)

    $ bin/fm-crew-state.sh exec-long
    state: working · source: executor · running 0m
    $ bin/fm-executor-poll.sh --validated ...            -> (no output: silence)
    $ FM_EXECUTOR_MAX_RUNTIME=1 bin/fm-executor-poll.sh --validated ...
    executor-stale: running 0m past the bound
    $ bin/fm-control.sh exec-long exit
    stopped exec-long harness=claude backend=tmux endpoint=firstmate:fm-exec-long worktree=.../6/project
    $ bin/fm-crew-state.sh exec-long                     # after the confirmed stop
    state: working · source: executor · running 3m       # <- see findings

## 8. Teardown

    $ bin/fm-teardown.sh exec-live
    🌳 Worktree returned to pool.
    teardown exec-live complete (window firstmate:fm-exec-live, worktree .../1/project)
    state/exec-live.* : removed
