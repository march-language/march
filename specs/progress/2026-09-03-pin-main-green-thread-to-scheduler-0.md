# Pin `main` to scheduler 0 (the OS main thread) — `MARCH_PIN_MAIN=1`

**Landed:** 2026-09-03, branch `runtime/pin-main-thread`.

## Problem

`fn main` is spawned as an ordinary green thread (`march_spawn_main` →
`march_sched_spawn`) and picked up by whichever scheduler worker pops or steals
it. Libraries that require the process main thread — Cocoa, and therefore GLFW
window creation on macOS — trap when called from `main` (cube_forge GAPS.md
G15: `pthread_main_np() == 0` inside the window-open extern, SIGTRAP, exit
133). The only workaround was `MARCH_NUM_SCHEDULERS=1`, which puts everything
on scheduler 0 (the calling thread) but also serialises `List.pmap*` and every
Task.

## Change (runtime only)

- `march_proc.pinned` (`runtime/march_scheduler.h`): set once at spawn by the
  new `march_sched_spawn_pinned`, never changed; calloc zero-inits to unpinned.
- A scheduler-0-only run queue, the "pin queue" (`pin_runq_push` /
  `pin_runq_pop` in `runtime/march_scheduler.c`): the same mutex-FIFO shape as
  the global runq, on the same `march_proc::next` link (a proc is never in
  both — every enqueue site checks the flag first). Only `sched_loop` running
  as scheduler 0 pops it. Scheduler 0 runs on the thread that called
  `march_sched_run`, i.e. the OS main thread of a compiled binary.
- Every enqueue point routes a pinned proc there instead of a Chase-Lev deque
  (stealable) or the global runq (popped by any scheduler): the spawn push
  (both the in-scheduler local push and the external global push), the
  post-swapcontext yield re-push including its deque-overflow fallback, and
  `march_sched_wake`. `proc_is_pinned` is `pinned && g_num_scheds > 1`: with a
  single scheduler everything already runs on scheduler 0's thread, so the
  unchanged single-scheduler dispatch (FIFO self-steal for fairness) is kept.
- Dispatch order on scheduler 0: global runq → pin queue → local deque → steal.
  In the `last_yielded` case the pin queue comes after the steal-from-others
  attempt, mirroring what a yielded unpinned proc gets: the yielder is re-run
  only if no other scheduler's work could be stolen first, so a pinned spinner
  (`wait_idle`, a yield loop) cannot starve leaf tasks any more than an
  unpinned one could. Workers never look at the pin queue.
- Shutdown accounting is unchanged: a proc waiting in the pin queue is still
  counted in `g_live_procs` (decremented only on `PROC_DEAD` reap), so no
  scheduler can observe "no live procs" while one is queued there.
- `march_spawn_main` (`runtime/march_runtime.c`) reads `MARCH_PIN_MAIN`; any
  value other than empty/`0` spawns `main` pinned. Opt-in on purpose: an
  unpinned `main` can run anywhere, which is the better default for servers,
  and the yielded-main/steal fairness logic stays exactly as it was for
  everyone who does not set it. Tasks and actors spawned by `main` are not
  pinned, so `pmap` still fans out to all workers. Blocking externs are
  unaffected (they run on whatever thread the proc is on; for a pinned proc
  that is the main thread, which is the point).

## Livelock review

The two scenarios the `sched_loop` comments guard against were checked:

- *Spinner that yields and is re-pushed locally every turn*: a pinned spinner
  goes to the pin queue; scheduler 0 still checks the global runq first every
  iteration (wakes are never starved), and in the yielded case tries to steal
  from other schedulers before re-running the spinner. Leaf tasks it spawned
  sit in scheduler 0's local deque, which workers steal from as before.
- *Task-await*: `task_wait_done` parks (`PROC_PARKED → WAITING`) rather than
  spinning, so a pinned `main` awaiting a pmap leaves scheduler 0 free to run
  its own deque; the completion wake lands in the pin queue and scheduler 0
  picks it up on its next iteration.

No case was found where pinning makes progress impossible that was possible
before; the only cost is that a pinned proc can wait for scheduler 0 to finish
its current quantum (same latency a global-runq wake already has).

## Verification

- `test/test_scheduler_pin.c` (new, built with `-DMARCH_NUM_SCHEDULERS=4`):
  a pinned proc yields 2000 times amid 128 busy siblings (spawned from both
  the external thread and from inside a scheduler), and a pinned proc is
  parked and woken ~1600 times from worker threads. Asserts the pinned proc
  never executed off the `march_sched_run` thread, that siblings DID run on
  workers, and that all work completed. A negative control (aliasing
  `march_sched_spawn_pinned` to `march_sched_spawn`) fails exactly the two
  thread assertions. Wired into the `runtest` alias in `test/dune` next to the
  other C scheduler tests. Note `scripts/run-tests.sh` runs the alcotest
  binaries only and does NOT cover the C rules, so it was also run directly
  (`./_build/default/test/test_scheduler_pin_runner`).
- `dune build` clean; `scripts/run-tests.sh -q` and the full
  `scripts/run-tests.sh` green ("All suites passed", 0 failures).
- cube_forge probe `probes/pin_main/` (pmap_n over 64 CPU-bound elements, 8
  workers, 14-core machine, runtime default of 4 scheduler threads):
  | config | main on OS main thread | pmap wall |
  |---|---|---|
  | default schedulers, unpinned | false | 207 ms |
  | default schedulers, `MARCH_PIN_MAIN=1` | **true (before and after)** | **210 ms** |
  | `MARCH_NUM_SCHEDULERS=1` | true | 762 ms |
  | `MARCH_NUM_SCHEDULERS=1 MARCH_PIN_MAIN=1` | true | 748 ms |
  | stock 0.3.0, `MARCH_PIN_MAIN=1` (control) | false | 214 ms |
- cube_forge itself (GLFW window): `MARCH_PIN_MAIN=1` with 4 scheduler threads
  opens the window (no main-thread refusal), `mesh all` 349 ms vs 436 ms under
  the old `MARCH_NUM_SCHEDULERS=1` workaround (headless: 327 ms / 448 ms), 240
  frames at 113 fps, frame dump renders.

## Not done / follow-ups

- No compiler or `forge.toml` switch to bake the flag into a binary; see
  `specs/todos/2026-09-03-pin-main-compiler-switch.md`.
- No `march_sched_stat` index for the pin-queue depth (index 6 is already the
  timer heap); add one if it ever needs observing.
