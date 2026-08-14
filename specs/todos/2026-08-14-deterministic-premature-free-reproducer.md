`[P2]` # No regression test pins the actor-dispatch premature-free window

The use-after-free fixed in `a9032530`
(`specs/progress/2026-08-14-actor-dispatch-rc-clobber-uaf.md`) has **no
regression test**. If someone reintroduces an RC-conditional reuse of the actor
record — the exact thing the deleted `a[0] = 1` clobber existed to enable — the
suite will stay green.

## Update 2026-08-14 (second pass) — the window itself is now pinned

`test/native/actor_dispatch_rc_window.march` closes the gap the section below
describes. It is option (1)'s invariant, reached without option (1)'s machinery:
**no second thread is required to observe the window.**

The clobber installed the forged `1` *before* the dispatch call, so the lie is
already published by the time the handler body runs. A `ffi_test_actor_rc` probe
called from **inside** the handler therefore reads exactly what a concurrent
thread would read — on one scheduler thread, with no race. The bug needs a
second thread to be *harmed* by the lie; it does not need one to *observe* it.
That is what turns "statistical repro" into a unit test.

The victim is a supervised child, so its true refcount exceeds 1 by
construction; the test's first line is the non-vacuity guard on that, and its
third line guards against a probe that silently never fired.

Verified adversarially by reinstating the `a[0] = 1` / `a[0] = saved_rc` pair
into `actor_green_thread` on top of current `main` (i.e. reverting only
`a9032530`'s hunks, keeping `acfa832c`):

| runtime | runs | result |
|---|---|---|
| clobber reinstated | 20 | 20/20 **RED** (`rc inside handler matches rc outside: false`) |
| clobber absent (`main`) | 20 | 20/20 **GREEN** |

Crucially this fails for a clobber that restores correctly on *every* exit path,
including the crash trap — the case `actor_crash_rc_restore.march` cannot see.
The two tests are complements: that one pins the failure to close the window,
this one pins the window being open at all.

**Still open: option (2)**, the source-level guard against a plain store to an
actor record's `a[0]`. Not done here deliberately — it is new machinery (nothing
in the suite currently greps runtime C source), it is trivially evadable by a
reintroduction that spells the store differently, and its value is only for
clobbers on dispatch paths this test has no window on. Worth doing, but it is a
different change than "pin the bug", which is now done.

## Partially covered as of 2026-08-14 — the deterministic red now exists

`test/native/actor_crash_rc_restore.march` asserts, through the test-only
`ffi_test_actor_rc` probe, that a supervised actor's refcount is unchanged
across a `panic()` in its handler. Reintroducing the `a[0] = 1` /
`a[0] = saved_rc` pair turns it red on **every** run (verified 3/3), because the
crash trap's `longjmp` skips the restore and the probe reads the forced `1`
directly. That satisfies this file's original acceptance criterion, and it needs
no race to observe: the crash path is a deterministic way to catch the window
open.

What it does NOT cover is the sharper invariant below — a *concurrent* reader
observing the forced `1` mid-dispatch. A future clobber that restores correctly
on every exit path (including the crash trap) would pass the new test and still
be unsafe on a multi-scheduler run. Options (1) and (2) below remain the real
ask; this file stays open for them, with the "there is no deterministic test at
all" part now resolved.

## Why there was no test

The reproducer is statistical: `bench/actors/spawn_churn.march` failed **6 of 30**
runs pre-fix and 0 of 60 post-fix. Instrumentation showed the crash rate
*understates* the defect rate — 2 premature frees were observed across 15 runs
while only 1 run crashed, because the corruption is sometimes benign. A test
that fails 20% of the time when the bug is present, and whose failure mode is
"SIGBUS with no output", does not belong in `runtest` as-is: it would be a flaky
red on a working tree as often as it would be a true positive.

What guards it today is `bash scripts/actor-load.sh` (the `churn` scenario, which
now registers each churned actor) — a de-facto guard that nobody is required to
run before merging.

## What would actually pin it

The invariant is sharp and does not need a race to observe:

> **An actor record's refcount word is never written non-atomically, and is
> never observed as `1` by another thread while its green thread is
> mid-dispatch.**

Options, cheapest first:

1. **A C-level test** in `test/` (alongside `test_actor_registry.c`) that opens a
   dispatch window on one thread and asserts from another that the record's
   refcount reads its true value — a direct assertion on the invariant rather
   than a race-and-hope loop. This is the shape
   `specs/todos/2026-08-12-supervised-child-registration-race.md` also argues
   for, for the same reason.
2. **A build-time or grep-level guard** that no plain (non-atomic) store to
   `a[0]` / `->rc` on an actor record exists in `runtime/march_runtime.c`. Crude,
   but it directly pins the thing that regressed, and the fix's own replacement
   comment already says "there is no safe version of this window."
3. **A stress target on its own alias** (the `@vault-scale` precedent): run the
   churn binary N times and fail on any non-zero exit. Not in `runtest` —
   wall-clock- and load-sensitive — but runnable in CI on a dedicated runner.

(1) plus (2) is probably the right pair: (1) proves the invariant, (2) catches
the reintroduction pattern even where (1) has no window to observe.

## Related pattern worth auditing while here

"Temporarily lie about a refcount so an `rc == 1` check passes" would be equally
unsafe anywhere else it appears. The runtime was grepped at fix time and no other
instance was found (`native_int_arr_set` and friends *read* `->rc` rather than
forging it), but the pattern is attractive enough to recur, and a guard of shape
(2) would catch the next one for free.

## Acceptance (revised 2026-08-14, second pass)

Original criterion — "reverting `a9032530` turns something red deterministically"
— is **met** by `test/native/actor_crash_rc_restore.march`.

The sharper criterion — "fails when the refcount word is written non-atomically
even if every exit path restores it correctly" — is **met** by
`test/native/actor_dispatch_rc_window.march` (20/20 red with the clobber, 20/20
green without; see the second-pass section at the top).

Remaining: only option (2), the source-level guard. This file stays open for
that alone; the testing question it was filed for is answered.
