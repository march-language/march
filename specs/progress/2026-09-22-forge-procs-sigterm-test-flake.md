# `[P3]` forge `test_procs` "forge's own SIGTERM stops everything" flaked on CI

**DONE 2026-09-22.**

**Symptom.** CI run 35786511193, job `test (ubuntu-24.04, rest)`: the case failed on
"the killer exited 0". Added by #587 (`12c062761`).

**Cause.** A test-timing race, not a behaviour change in `Procs`. The test signalled
forge with a *supervised* child, `sh -c "sleep 1; kill -TERM <test pid>"`, and asserted
that child exited 0. When the SIGTERM arrived, `supervise`'s stop-all SIGTERMed every
supervised child, the killer included. On a slow runner the killer had not exited yet,
so its status was `WSIGNALED` instead of `WEXITED 0`.

**Fix** (`forge/test/test_procs.ml`, test only).
- The killer is started with `Unix.create_process` (stdio to `/dev/null`). It is not a
  supervised proc, so nothing signals it. The test reaps it with `waitpid` after
  `supervise` returns and still asserts `WEXITED 0`.
- The old sub-point "a child that exits cleanly is not, without fail_fast, a reason to
  stop" moves to a supervised `true` proc. The test waits for it (`wait_all`) *before*
  `supervise`, so its `WEXITED 0` status does not depend on scheduling.
- Unchanged: `a` and `c` (600s sleepers) must be `WSIGNALED SIGTERM` and gone
  (`kill 0` gives ESRCH). The only way that can happen is forge's own SIGTERM.

**Verified.** Ran `dune build --root . --force @forge/test/runtest` twice (exit 0). Ran the case
directly 15 times in a row with 16 `yes` CPU hogs running (load average about 37): 15/15 passed.
