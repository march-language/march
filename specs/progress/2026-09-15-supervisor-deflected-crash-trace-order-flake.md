# `supervisor_deflected_crash_absorbed` golden: trace lines raced to stderr

Fixed 2026-09-15. The native golden
`test/native/supervisor_deflected_crash_absorbed.{march,expected}` (from
[[2026-09-10-supervision-race-test-seam]]) failed intermittently on CI (main's
run 35002248704, and PR #486's run 35027001905, an interpreter-only change)
with its two `MARCH_SUP_TRACE` lines swapped:

```
march: supervisor backoff child=0 streak=1 delay_ms=0 (batch restart already pending, skipped)
march: supervisor backoff child=1 streak=1 delay_ms=0
```

## Cause

Not the crash order. In `march_supervisor_notify` (`runtime/march_runtime.c`)
both crashes decide their fate inside `g_supervise_mu`: `hi` (child 1) claims
`batch_restart_in_flight`, and `lo` (child 0), arriving on a worker thread
during the `MARCH_SUP_TEST_STALL_MS` window, sees the marker and is deflected.
That order is fixed by construction; the output above even proves it (child 0
says "skipped"). But the trace `fprintf` ran **after** the unlock, so once the
claimant released the lock the deflected thread could reach stderr first. The
log order was a race between two post-unlock `fprintf`s, unrelated to the
semantics the test checks.

Proof: a 50 ms `usleep` inserted right after the unlock on the claiming
(`claimed_sync_batch`) path reproduced the exact CI diff 5/5. It did not
reproduce unperturbed in 60 local runs.

## Fix

Runtime, not test: the backoff-delay arithmetic (lock-free, cheap) and the
`MARCH_SUP_TRACE` line now run before `pthread_mutex_unlock`, so trace lines
from racing siblings come out in the order the lock decided them. A claimant's
line always precedes the line of the sibling it deflected. The golden is
unchanged and still asserts that order, which is now a real guarantee and not
luck. It was not made order-insensitive, since that would stop checking
claim-then-deflect.

The stderr write under the leaf lock only happens with `MARCH_SUP_TRACE` set.

## Verification

- The same perturbation, kept just after the new unlock position: 20/20 match
  the golden.
- Perturbation removed: 100/100 unperturbed runs match.
- Every other supervision native golden is unchanged:
  spawn_children, one_for_one/one_for_all/rest_for_one_restart,
  actor_stop_tree (+ `.order`), restart_transient, restart_temporary,
  restart_batch_temporary.
