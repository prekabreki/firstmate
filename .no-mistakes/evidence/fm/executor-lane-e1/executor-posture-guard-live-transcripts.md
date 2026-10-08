# Live lab transcripts: executor posture guard (lab home /tmp/fm-lab.vl2Sz4, private tmux socket fm-lab)

## data/projects.md (final; dpproj was direct-PR until s7 tightened it)
- nmproj [no-mistakes] - lab fixture (added 2026-10-08)
- prodproj [no-mistakes-prod-only] - lab fixture (added 2026-10-08)
- dpproj [no-mistakes] - lab fixture (added 2026-10-08)
- badforge [no-mistakes forge=gerit] - lab fixture (added 2026-10-08)
- shipproj [no-mistakes] - lab fixture (added 2026-10-08)

## s1a-nm-noconsent
$ bin/fm-spawn.sh ex-nm /tmp/fm-lab.vl2Sz4/projects/nmproj --executor --issue 3 --yolo off --harness \'/tmp/fm-lab.vl2Sz4/tools/lab-executor run\'
fm-gate-refuse: gate agent lifecycle permitted only against lab home /tmp/fm-lab.vl2Sz4
error: ex-nm cannot launch: an executor delivers direct-PR, below the standing posture no-mistakes for nmproj, and dropping below the captain's standing posture needs the captain's word; on a present captain instruction for this task, spawn again with --accept-direct-pr, otherwise dispatch a no-mistakes ship task
[exit=1]

## s1b-nm-consent
$ bin/fm-spawn.sh ex-nm /tmp/fm-lab.vl2Sz4/projects/nmproj --executor --issue 3 --yolo off --accept-direct-pr --harness \'/tmp/fm-lab.vl2Sz4/tools/lab-executor run\'
fm-gate-refuse: gate agent lifecycle permitted only against lab home /tmp/fm-lab.vl2Sz4
notice: ex-nm is an executor (mode=direct-PR) while the standing posture for nmproj is no-mistakes - proceeding on the recorded captain consent (posture_consent=direct-PR); firstmate's real-diff review replaces the pipeline
spawned ex-nm harness=lab-executor kind=executor mode=direct-PR yolo=off issue=3 window=primary:fm-ex-nm worktree=/tmp/fm-lab.vl2Sz4/pool/.treehouse/nmproj-8f3f01/1/nmproj
[exit=0]

## s2b-relaunch-accept-refused
$ bin/fm-spawn.sh ex-nm --relaunch --accept-direct-pr --harness \'/tmp/fm-lab.vl2Sz4/tools/lab-executor run\'
fm-gate-refuse: gate agent lifecycle permitted only against lab home /tmp/fm-lab.vl2Sz4
error: --relaunch reuses the consent recorded at the executor's first spawn; --accept-direct-pr cannot be granted on a relaunch (tear the task down and spawn it afresh on the captain's word)
[exit=1]

## s2c-relaunch-reuses-consent
$ bin/fm-spawn.sh ex-nm --relaunch --harness \'/tmp/fm-lab.vl2Sz4/tools/lab-executor run\'
fm-gate-refuse: gate agent lifecycle permitted only against lab home /tmp/fm-lab.vl2Sz4
notice: ex-nm is an executor (mode=direct-PR) while the standing posture for nmproj is no-mistakes - proceeding on the recorded captain consent (posture_consent=direct-PR); firstmate's real-diff review replaces the pipeline
spawned ex-nm harness=lab-executor kind=executor mode=direct-PR yolo=off issue=3 window=primary:fm-ex-nm worktree=/tmp/fm-lab.vl2Sz4/pool/.treehouse/nmproj-8f3f01/1/nmproj
[exit=0]

## s3a-prod-noconsent
$ bin/fm-spawn.sh ex-prodproj /tmp/fm-lab.vl2Sz4/projects/prodproj --executor --issue 4 --yolo off --harness \'/tmp/fm-lab.vl2Sz4/tools/lab-executor run\'
fm-gate-refuse: gate agent lifecycle permitted only against lab home /tmp/fm-lab.vl2Sz4
error: ex-prodproj cannot launch: an executor delivers direct-PR, below the standing posture no-mistakes-prod-only for prodproj, and dropping below the captain's standing posture needs the captain's word; on a present captain instruction for this task, spawn again with --accept-direct-pr, otherwise dispatch a no-mistakes ship task
[exit=1]

## s4a-unreg-noconsent
$ bin/fm-spawn.sh ex-unregproj /tmp/fm-lab.vl2Sz4/projects/unregproj --executor --issue 4 --yolo off --harness \'/tmp/fm-lab.vl2Sz4/tools/lab-executor run\'
fm-gate-refuse: gate agent lifecycle permitted only against lab home /tmp/fm-lab.vl2Sz4
error: ex-unregproj cannot launch: an executor delivers direct-PR, below the standing posture no-mistakes for unregproj, and dropping below the captain's standing posture needs the captain's word; on a present captain instruction for this task, spawn again with --accept-direct-pr, otherwise dispatch a no-mistakes ship task
[exit=1]

## s4b-unreg-consent
$ bin/fm-spawn.sh ex-unregproj /tmp/fm-lab.vl2Sz4/projects/unregproj --executor --issue 4 --yolo off --accept-direct-pr --harness \'/tmp/fm-lab.vl2Sz4/tools/lab-executor run\'
fm-gate-refuse: gate agent lifecycle permitted only against lab home /tmp/fm-lab.vl2Sz4
notice: ex-unregproj is an executor (mode=direct-PR) while the standing posture for unregproj is no-mistakes - proceeding on the recorded captain consent (posture_consent=direct-PR); firstmate's real-diff review replaces the pipeline
spawned ex-unregproj harness=lab-executor kind=executor mode=direct-PR yolo=off issue=4 window=primary:fm-ex-unregproj worktree=/tmp/fm-lab.vl2Sz4/pool/.treehouse/unregproj-b07ee4/1/unregproj
[exit=0]

## s5-badforge-noconsent
$ bin/fm-spawn.sh ex-badforge /tmp/fm-lab.vl2Sz4/projects/badforge --executor --issue 4 --yolo off --harness \'/tmp/fm-lab.vl2Sz4/tools/lab-executor run\'
fm-gate-refuse: gate agent lifecycle permitted only against lab home /tmp/fm-lab.vl2Sz4
refused: unknown forge "gerit" registered for badforge in /tmp/fm-lab.vl2Sz4/data/projects.md; the accepted value is forge=gerrit, or no forge token at all for a forge whose pull requests no-mistakes already drives; correct the registry entry
error: ex-badforge cannot launch: the registry entry for badforge does not resolve to a delivery posture (see the refusal above); correct data/projects.md and spawn again
[exit=1]

## s5-badforge-consent
$ bin/fm-spawn.sh ex-badforge /tmp/fm-lab.vl2Sz4/projects/badforge --executor --issue 4 --yolo off --accept-direct-pr --harness \'/tmp/fm-lab.vl2Sz4/tools/lab-executor run\'
fm-gate-refuse: gate agent lifecycle permitted only against lab home /tmp/fm-lab.vl2Sz4
refused: unknown forge "gerit" registered for badforge in /tmp/fm-lab.vl2Sz4/data/projects.md; the accepted value is forge=gerrit, or no forge token at all for a forge whose pull requests no-mistakes already drives; correct the registry entry
error: ex-badforge cannot launch: the registry entry for badforge does not resolve to a delivery posture (see the refusal above); correct data/projects.md and spawn again
[exit=1]

## s6-direct-pr
$ bin/fm-spawn.sh ex-dpproj /tmp/fm-lab.vl2Sz4/projects/dpproj --executor --issue 4 --yolo off --harness \'/tmp/fm-lab.vl2Sz4/tools/lab-executor run\'
fm-gate-refuse: gate agent lifecycle permitted only against lab home /tmp/fm-lab.vl2Sz4
spawned ex-dpproj harness=lab-executor kind=executor mode=direct-PR yolo=off issue=4 window=primary:fm-ex-dpproj worktree=/tmp/fm-lab.vl2Sz4/pool/.treehouse/dpproj-36764b/1/dpproj
[exit=0]

## s7-tightened-relaunch-refused
$ bin/fm-spawn.sh ex-dpproj --relaunch --harness \'/tmp/fm-lab.vl2Sz4/tools/lab-executor run\'
fm-gate-refuse: gate agent lifecycle permitted only against lab home /tmp/fm-lab.vl2Sz4
error: ex-dpproj cannot launch: an executor delivers direct-PR, below the standing posture no-mistakes for dpproj, and dropping below the captain's standing posture needs the captain's word; on a present captain instruction for this task, spawn again with --accept-direct-pr, otherwise dispatch a no-mistakes ship task
[exit=1]

## s8-ship-accept-refused
$ bin/fm-spawn.sh sh-1 /tmp/fm-lab.vl2Sz4/projects/shipproj --mode no-mistakes --yolo off --accept-direct-pr --harness claude
fm-gate-refuse: gate agent lifecycle permitted only against lab home /tmp/fm-lab.vl2Sz4
error: --accept-direct-pr applies only to --executor spawns; a ship task chooses its delivery with --mode
[exit=1]

## s9-ship-normal
$ bin/fm-spawn.sh sh-1 /tmp/fm-lab.vl2Sz4/projects/shipproj --mode no-mistakes --yolo off --harness \'sleep 600\'
fm-gate-refuse: gate agent lifecycle permitted only against lab home /tmp/fm-lab.vl2Sz4
spawned sh-1 harness=sleep kind=ship mode=no-mistakes yolo=off window=primary:fm-sh-1 worktree=/tmp/fm-lab.vl2Sz4/pool/.treehouse/shipproj-bbe67a/1/shipproj
[exit=0]

## state/ex-nm.meta after relaunch
window=primary:fm-ex-nm
endpoint_task_id=ex-nm
worktree=/tmp/fm-lab.vl2Sz4/pool/.treehouse/nmproj-8f3f01/1/nmproj
project=/tmp/fm-lab.vl2Sz4/projects/nmproj
harness=lab-executor
kind=executor
mode=direct-PR
yolo=off
issue=3
posture_consent=direct-PR
executor_base=04b5259c7ab4bd7dddc50dcf3ef9045d173fa4d2
executor_launched=1791491041
tasktmp=/tmp/fm-ex-nm
model=default
effort=default
spawn_gen=s1791491041.3470582.7485

## state/ex-dpproj.meta (direct-PR spawn, no consent recorded; unchanged by refused relaunch)
window=primary:fm-ex-dpproj
endpoint_task_id=ex-dpproj
worktree=/tmp/fm-lab.vl2Sz4/pool/.treehouse/dpproj-36764b/1/dpproj
project=/tmp/fm-lab.vl2Sz4/projects/dpproj
harness=lab-executor
kind=executor
mode=direct-PR
yolo=off
issue=4
executor_base=04b5259c7ab4bd7dddc50dcf3ef9045d173fa4d2
executor_launched=1791491076
tasktmp=/tmp/fm-ex-dpproj
model=default
effort=default
spawn_gen=s1791491076.3475257.16210

## lab-executor.log (one line per real executor launch)
lab-executor ran in /tmp/fm-lab.vl2Sz4/pool/.treehouse/nmproj-8f3f01/1/nmproj with 3 bytes of brief
lab-executor ran in /tmp/fm-lab.vl2Sz4/pool/.treehouse/nmproj-8f3f01/1/nmproj with 3 bytes of brief
lab-executor ran in /tmp/fm-lab.vl2Sz4/pool/.treehouse/unregproj-b07ee4/1/unregproj with 3 bytes of brief
lab-executor ran in /tmp/fm-lab.vl2Sz4/pool/.treehouse/dpproj-36764b/1/dpproj with 3 bytes of brief
