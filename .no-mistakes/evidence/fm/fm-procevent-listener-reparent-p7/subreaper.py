import ctypes, os, sys
PR_SET_CHILD_SUBREAPER = 36
libc = ctypes.CDLL(None, use_errno=True)
assert libc.prctl(PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0) == 0
mode, argv = sys.argv[1], sys.argv[2:]
if mode == "self":   # the test's own bash becomes the subreaper (preserved across execve)
    print(f"test-shell-subreaper pid={os.getpid()} (becomes the test bash, i.e. $$)", flush=True)
    os.execvp(argv[0], argv)
pid = os.fork()      # "above": this wrapper is a subreaper sitting above the test's bash
if pid == 0:
    os.execvp(argv[0], argv)
print(f"wrapper-subreaper pid={os.getpid()} test-bash pid={pid}", flush=True)
rc = None
while True:          # reap everything, report the test's own status
    try:
        p, st = os.wait()
    except ChildProcessError:
        break
    if p == pid:
        rc = os.waitstatus_to_exitcode(st)
        break
sys.exit(rc)
