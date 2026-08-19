# LANDED 2026-08-18 — `send_after` / `cancel_timer` surfaced to March

**Status: shipped.** `send_after(pid, msg, delay_ms) : TimerRef` and
`cancel_timer(ref)` are exposed as `actor_send_after`/`actor_cancel_timer`
(compiler builtins, following `actor_cast`/`actor_call`/`actor_reply`'s
"actor_"-prefixed-raw-name convention) with `Actor.send_after`/
`Actor.cancel_timer` wrappers in `stdlib/actor.march` for everyday use. Both
backends (interpreter and compiled/LLVM) implement the full mechanism.

**The two design decisions the todo flagged, resolved:**

1. **Ownership/RC of the pending message and the TimerRef itself.** The
   compiled side gave `TimerRef` a REAL `march_alloc`'d, RC'd representation
   (`MARCH_TIMER_TOKEN_TAG`, `runtime/march_runtime.h`) rather than a
   hand-rolled malloc'd/manually-refcounted struct like the existing
   `march_cancel_token` (`runtime/march_scheduler.h`). This was not the
   first design tried — a manually-refcounted, deliberately-never-freed
   ("leak-don't-free", mirroring `march_proc`'s own discipline) token was
   the original plan, chosen specifically to make cancel-after-fire safe
   without a UAF. It was abandoned once a probe of `march_cancel_token`'s
   OWN existing RC discipline (`MARCH_DUMP_TXT=perceus`, a hand-written
   .march repro reusing a `CancelToken` twice) showed Perceus inserts a
   real `inc_rc`/`dec_rc` on ANY `TCon _`-typed value used more than once —
   including `CancelToken`, which is `needs_rc = true` by `lib/tir/
   rc_types.ml`'s general rule but has NO real `march_hdr` layout. That is
   a genuine pre-existing latent bug in `march_cancel_token`, not something
   this feature could safely inherit: reusing that raw-struct pattern for
   `TimerRef` would corrupt the struct's fields the first time a March
   program held a `TimerRef` across more than one use (e.g. checking a
   `Bool` liveness flag before cancelling). Giving `TimerRef` a real header
   instead means ordinary Perceus-inserted `inc_rc`/`dec_rc` are correct by
   construction, with two owners across its lifetime (the timer heap's own
   hold, and the March-level binding) and no leak, no cancel-after-fire
   UAF, and no special-casing anywhere in Perceus/borrow/llvm_ctx. The
   `march_cancel_token` latent bug itself was left alone — out of scope,
   flagged for a separate fix.

   The message's own RC contract mirrors `march_send`/`actor_cast` exactly:
   the C entry point receives exactly one owned reference, transferred into
   the timer heap until the deadline, then either delivered or disposed via
   the ALREADY-EXISTING `march_sched_set_msg_dtor` channel (Task 14) — plus
   a NEW, symmetric `march_sched_set_timer_token_ops` registration for the
   token side, since `march_scheduler.c` must stay free of any direct
   dependency on March's GC (same rationale as the message dtor).

   **A real, adjacent pre-existing bug found and fixed while wiring this
   up:** `march_spawn_main` (called first, unconditionally, from every
   compiled program's emitted `@main`) wins the scheduler's lazy-init
   `g_sched_initialized` CAS before `march_spawn_common`'s block ever gets
   a turn — so the registration calls that ONLY lived in
   `march_spawn_common` (`march_sched_set_msg_dtor` since Task 14, and this
   feature's new `march_sched_set_timer_token_ops`) never actually ran in
   any normal compiled program. Message disposal for mailbox-overflow
   drops and dead-proc-reap (Task 14's whole point) was therefore silently
   a no-op in every compiled binary before this fix — caught only because
   `cancel_timer` visibly failed to prevent delivery in a real compiled
   run. Fixed by extracting both registrations into one shared
   `march_register_sched_callbacks()` helper, called from BOTH lazy-init
   sites so neither can register only one of the two callbacks again.

2. **Does a pending timer count as "work pending" for
   `march_sched_wait_idle`/`run_until_idle`?** Decided NO for `send_after`
   entries (unlike a WAKE-kind park/recv deadline, which still counts) —
   both backends agree: the compiled scheduler's `timers_pending` loop
   skips `MARCH_TIMER_SEND` entries explicitly, and the interpreter's
   `timer_service_tick` never blocks `run_scheduler`'s pass loop for one
   either. Rationale: a long-duration `send_after` (a periodic tick, a
   multi-second retry backoff) would otherwise keep `run_until_idle()` —
   whose whole contract is "return once nothing is happening right now" —
   blocked for the FULL remaining delay, which is surprising for a
   test-harness primitive. A real long-running process is kept alive by
   its own non-daemon/actor-daemon procs (or by driving
   `march_sched_run()`/the real event loop directly), not by
   `wait_idle`/`run_until_idle`, so this does not affect whether the
   message is eventually delivered — only whether waiting for it blocks a
   test.

**Verification:** interpreter tests (`test/test_stdlib_suite.ml`, "actor
timers" group — delivery timing, cancellation incl. double-cancel,
dead-target no-crash, and the `Actor.send_after`/`Actor.cancel_timer`
stdlib-wrapper naming-collision regression); a compiled/native functional
test (`test/native/timer_send_after.march`) using the same "block on
`Actor.call` against a never-replying actor" real-time-wait trick
`native/actor_call_timeout.march` already established; and a compiled
leak/dtor probe (`test/native/timer_leak_probe.march`, `live_allocs()`
signal, same three-rule dune pattern as `native_arr_fold_leak_probe.march`)
covering BOTH disposal paths (cancelled-before-deadline and
dead-target-at-deadline) — falsifiability checked by hand in both
directions (temporarily skipping either dispose call turns the probe's
healthy delta of 0 into the exact defect count, 5000, matching one leaked
object per sabotaged iteration).

**Known, documented trade-off left as-is (not a bug):** if a SEND-kind
timer's target has a bounded mailbox under `MARCH_MBOX_BLOCK` policy and is
currently full when the timer fires, `march_sched_send` (called from
`timer_service`, running on the preempt-daemon thread) sleep-polls that
thread until capacity frees — the same pre-existing hazard class as any
OTHER foreign-thread sender under `BLOCK`, not something newly introduced
by this feature, and not fixed here since a real fix needs a non-blocking
send path this codebase does not have yet.

---

## Original todo (design rationale, retained)

`[P2]` # No `send_after` / `cancel_timer`: the timer heap exists but isn't exposed

## The gap

March has no way to schedule a message. There is no `send_after`,
`cancel_timer`, or `Process.sleep`. An actor that wants to poll, retry, time
something out, or tick has to burn a task green thread in a yield loop.

## Why this is the cheapest item on the list

The hard part is already built and shipped. The 2026-08-12 hardening (Task 2)
added a real timer subsystem to the scheduler:

- a mutex-guarded binary min-heap of `(deadline_ms, proc, park_gen)`
  (`runtime/march_scheduler.c`), serviced every `MARCH_QUANTUM_US` from the
  preemption daemon;
- `march_sched_park_self_until(deadline_ms)` and `march_now_ms()`;
- lazy cancellation via `park_gen`, so a woken-early proc's stale entry is
  skipped rather than firing (added in Task 16's review round).

That machinery is entirely runtime-internal: it backs `Actor.call` deadlines and
supervisor restart backoff. Nothing surfaces it to March.

## Sketch

`send_after(pid, msg, delay_ms) : TimerRef` — enqueue into the same heap with a
payload variant that performs a `march_sched_send` on fire, instead of only
waking a parked proc. `cancel_timer(ref)` can reuse the `park_gen` trick
(bump a generation, let the stale entry fire into nothing) rather than needing
real heap removal.

Two things to decide:

1. **Ownership/RC of the pending message.** The heap would hold a March value
   between now and the deadline — it needs a reference, and a cancelled or
   dead-target timer must dispose it. The `march_sched_set_msg_dtor` hook added
   in Task 14 is exactly the disposal channel to reuse.
2. **Timer entries pin their target proc.** Procs are leak-don't-free, so a
   long timer cannot dangle — but a long timer *does* keep the scheduler from
   going idle, which now matters because `march_sched_wait_idle` counts live
   timer entries as busy (Task 16). A one-hour `send_after` would keep
   `run_until_idle()` from returning. Decide whether scheduled sends count as
   "work pending" (they do for a server; they probably should not for
   `run_until_idle` in a test).

## Acceptance

`send_after` delivers after the delay and not before; `cancel_timer` before the
deadline delivers nothing and leaks nothing; a cancelled or dead-target timer's
message is disposed through the registered dtor.
