# `native_signal_watch` has a ~7% output-ordering flake

Filed 2026-08-20, found while verifying the NativeArray bounds-check fix
(`specs/progress/2026-08-20-nativearray-get-set-unchecked-oob-compiled.md`),
whose `dune runtest` run this test reddened. It is **not** related to that
change — see the control below.

## The flake

`test/native/signal_watch.expected` pins:

```
before raise
after raise
caught usr2
```

Two different wrong outputs were observed:

```
before raise
after raisecaught usr2          <- handler's write lands mid-line, no newline
```
```
before raise
caught usr2
after raise                      <- handler observed BEFORE the main thread's line
```

So both the interleaving *and* the ordering of the handler's output against the
main thread's are unpinned. The fixture raises SIGUSR2 and expects the handler's
line to appear strictly after `after raise`, which is only true if the handler's
delivery is deferred to a drain point that happens to fall there.

## Measurement — the change under test is exonerated

Both binaries built from the same tree, differing only in the runtime, then run
INTERLEAVED (so contention is shared evenly across arms — the box was at load
average ~8 on 14 cores at the time):

| runtime | mismatched |
|---|---|
| baseline (no bounds check) | 4/60 |
| with the bounds check | 4/60 |

Identical. Neither binary even links the new check (`strings | grep -c
"out of bounds (len="` is 0 for both), and `signal_watch.march` never mentions
`NativeArray`, so the change is mechanically inert here.

Worth recording the trap: an earlier, smaller sample read 0/20 baseline vs 2/20
fixed, which looks alarming and is not significant — at a ~7% rate, 0/20 happens
about 12% of the time by chance. A 20-run spot check cannot resolve a flake of
this size; the interleaved 60-run pair could.

## Fix

Make the assertion insensitive to the delivery point, or make the delivery point
deterministic. Either pin only that all three lines appear (order-free, as
`native_actor_monitor_down_reason`'s rule does with per-line `grep -Eq`), or
have the fixture drain signals at an explicit synchronisation point before
printing `after raise` so the ordering is guaranteed rather than typical.

Prefer the second if the ordering is meant to be part of the contract — an
order-free assertion would stop pinning "the handler does not run before the
raise returns", which may be the property the fixture exists to check. Read
`specs/progress/2026-08-11-signal-watch-stage-b.md` (Signal.watch Stage B)
before choosing.

## Acceptance

200 consecutive runs with no mismatch, on a loaded box (an idle box hides it —
the observed rate roughly tracks contention).

---

## Resolution (landed 2026-08-21)

**Root cause.** `march_signal_drain()` is called at the *top of every
`sched_loop` iteration on every scheduler thread* (`runtime/march_scheduler.c`,
in the `while (!g_all_done)` loop). `MARCH_NUM_SCHEDULERS` defaults to 4
(`runtime/march_scheduler.h`), and this fixture's dune rule set no override, so
while main's green thread ran on scheduler 0 the other three workers were
idle-spinning in that loop. `Signal.raise` sets the pending flag (POSIX
guarantees delivery before `kill()` returns for a self-raise), and whichever
thread reaches the drain first claims it via `atomic_exchange` — typically an
idle worker, microseconds later. The handler therefore ran **concurrently with
main's own `println`**, on a different OS thread.

That single cause produces both recorded symptoms:

- `caught usr2` ahead of `after raise` — the worker drained and printed before
  main's green thread reached its next `println`.
- `after raisecaught usr2` / `caught usr2after raise` — two threads' writes
  tearing. Note `march_println` already emits payload+newline in one `writev(2)`
  (`e73644aa`, 2026-07-20) precisely to make a line atomic, so this is evidence
  that a single vectored write is **not** in fact atomic against a concurrent
  thread on macOS; the tear always falls between the two iovecs. Filed
  separately as `specs/todos/2026-08-21-println-writev-not-atomic-across-threads.md`
  — it is a real (if low-severity) runtime finding, not something this fixture
  should paper over.

The fixture's old header comment claimed the handler "prints AFTER main's body
because dispatch is deferred (the drain runs once main's green thread
finishes)". That is true only at `MARCH_NUM_SCHEDULERS=1`. At >1 it was a
typical outcome, never a guarantee — the fixture was pinning an ordering the
runtime does not promise.

**Fix.** The ordering *is* worth pinning — it is the only thing separating a
deferred drain from a handler run synchronously inside `Signal.raise`, which is
the property Stage B exists to establish. So it was made genuinely deterministic
rather than loosened:

1. `native_signal_watch` now runs at `MARCH_NUM_SCHEDULERS=1`, keeping the exact
   golden diff. At one scheduler nothing else can run while main's green thread
   runs, so the drain *cannot* happen before main finishes.
2. A new `native_signal_watch_multisched` rule runs the same binary at the
   default scheduler count, so the worker-thread drain path — the one Stage B
   relies on for a signal arriving while green threads are busy — keeps
   coverage. It asserts only what >1 scheduler actually promises: the handler
   ran, and the process exited 0. Its greps are deliberately unanchored, since
   anchoring them would just relocate the flake.

**Measured**, both arms built once and run interleaved so contention is shared:

| Arm | Result |
|---|---|
| before, default (4) schedulers, exact golden | **17/400 mismatched (4.25%)** |
| after, `MARCH_NUM_SCHEDULERS=1`, exact golden | **0/400** |
| after, default schedulers, new grep rule | **0/400** |

Load average 13.88 during the interleaved run. Two earlier confirmations:
8/200 (4.0%) at the default at load 13.8, and — the decisive control — **0/200
on the *unmodified* binary at `MARCH_NUM_SCHEDULERS=1` at load 17.0**, i.e. a
*busier* box than the arm that failed, ruling out "the box just got quiet".
The 0/400 for the unanchored greps is what establishes that a substring match
survives the tear.

A further confirmation round at load average **75.04** (the box's heaviest
point all session) added **0/600** for each of the two after-arms, so the
cumulative post-fix sample is **1000 consecutive clean runs each** for the
pinned golden and for the new multi-scheduler grep rule. Acceptance bar (200
consecutive clean on a loaded box) met five times over.

`dune build --root . @runtest` is green end to end: exit 0, 584 tests run.
