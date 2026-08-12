# Exponential supervisor restart backoff with jitter

Task 16 of the actor-system-hardening plan
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`).

## The fix

`runtime/march_runtime.c`:

- `march_sup_child` gained `int32_t crash_streak` / `int64_t last_crash_ms`,
  zeroed explicitly in `march_actor_register_child` (the field array grows
  via `realloc`, which does not zero new memory).
- `march_supervisor_notify` now tracks a per-child crash streak (reset once
  the child survives a full `supervisor_window_secs` window) and computes a
  delay of `min(5000, 25 << min(streak-1, 7))` ms `±25%` jitter (a weak
  xorshift-style LCG seeded off an atomic counter — `Math.random` isn't
  available in the runtime and `rand()` is process-global) for the second
  and every subsequent crash of a slot. The **first** crash of a slot always
  takes `delay == 0` — the exact pre-existing synchronous restart path —
  which is what keeps every existing supervision golden
  (`examples/supervision_strategies.march`, the native supervision tests)
  unaffected: they each crash a given child exactly once.
- A non-zero delay is handled by `delayed_restart_thread`, spawned via
  `march_sched_spawn` (never runs on the crashing actor's own scheduler
  thread): it parks in a loop around `march_sched_park_self_until` until the
  deadline, re-checks `march_is_alive(supervisor)` (a supervisor that died
  during the delay aborts the restart — no `find_meta` on a stale
  supervisor), then runs the same `one_for_one`/`one_for_all`/`rest_for_one`
  restart function the synchronous path used, budget-gated exactly as
  before (`march_restart_budget_ok` is judged at restart time, inside the
  delayed body, not at crash time). `one_for_all`/`rest_for_one` delay the
  *entire batch* by the crashed child's own streak delay.
- `MARCH_SUP_TRACE=1` prints `march: supervisor backoff child=<idx>
  streak=<n> delay_ms=<d>` to stderr on every crash (delay 0 included) for
  harness/debug observability.

### `g_supervise_mu`: closing a pre-existing concurrent-crash race

`march_supervisor_notify` is called from `do_actor_death` with **no lock
held** — confirmed by reading `do_actor_death`: the `$alive` flag flip,
monitor/cleanup delivery, and the call to `march_supervisor_notify` are all
unsynchronized, and `do_actor_death` runs either on the crashing actor's own
scheduler thread (the crash trap in `actor_green_thread`) or on any foreign
thread (`march_kill` from an evloop). Before this task, two children of the
*same* supervisor crashing concurrently on different threads could run
`march_supervisor_notify` — and therefore `march_restart_budget_ok`'s
`sup_restart_ts` realloc and the `*_restart` functions' `sup_children`/
supervisor-state writes — concurrently. A racing `realloc` on the same
pointer is heap corruption; this was a real, pre-existing hazard, just
never triggered by anything in the test corpus. Task 16 adds
`crash_streak`/`last_crash_ms` writes to that same unsynchronized surface,
so closing the race became in-scope rather than deferred.

Fix: a single global `pthread_mutex_t g_supervise_mu`, taken around the
entire body of `march_supervisor_notify` (both the synchronous and the
delayed-dispatch paths) and around `delayed_restart_thread`'s call into the
restart strategies. Supervision is control-plane — restarts are rare
relative to steady-state message traffic — so one global mutex is
deliberately simpler than per-supervisor locking.

**Lock ordering: `g_supervise_mu` is OUTER, `g_tbl_mu` is INNER.** Everything
reachable while holding `g_supervise_mu` — `march_respawn_child` →
`find_meta_by_pid_index` (lock-free per Task 15) and `find_or_create_meta`
(takes `g_tbl_mu`) — only ever takes `g_tbl_mu`, never `g_supervise_mu`, so
there's no inversion. `march_spawn` (called from `march_respawn_child`)
allocs and registers the new actor but runs no user code synchronously —
the spawned actor's body only runs later, on its own green thread — so
there is no re-entrant call back into `march_supervisor_notify` while
`g_supervise_mu` is held.

### `march_sched_wait_idle` fix (`runtime/march_scheduler.c`)

Building the crashloop harness against the delayed-restart path surfaced a
genuine, pre-existing gap in `march_sched_wait_idle` (backing
`run_until_idle()`): a green thread parked on a real timer via
`march_sched_park_self_until` transitions `PROC_PARKED` → `PROC_WAITING`
the moment `sched_loop`'s dispatch loop observes the parked status (see the
post-swapcontext `PROC_PARKED` branch), and `wait_idle`'s busy check only
treats `PROC_WAITING` as busy when the proc has a pending mailbox message
(`mbox_count > 0`) — a non-actor green thread like
`delayed_restart_thread` never has one. The result: `run_until_idle()`
returned "idle" while the delayed restart was still genuinely pending,
silently racing ahead. This was invisible before Task 16 because nothing
in the existing corpus combined `run_until_idle()` with a plain (non-actor,
non-mailbox) `march_sched_park_self_until` parker.

Confirmed by instrumenting a scratch reproduction
(`crashdbg.march`-style: 8 `Poison` sends interleaved with `is_alive`
checks) — before the fix, the child stayed dead across 6 more poison
iterations while the delayed thread was still parked, only completing its
restart after `main()` had already finished and the process was winding
down; after the fix, each iteration correctly observed the freshly-restarted
child before sending the next poison.

Fix: `wait_idle`'s "not busy" branch now additionally checks
`g_timer_len` (the global timer min-heap's length, `g_timer_mu`-guarded,
never nested with `g_registry_mu` — no new lock-order hazard) — a non-empty
timer heap means some proc is genuinely still going to wake up and do more
work, so the system isn't actually idle yet. This restores the function's
own documented contract ("returns only once the system is quiescent")
rather than changing it.

### `march_actor_register_child`

`sup_children[idx].crash_streak`/`.last_crash_ms` are set to `0` explicitly
right after the `realloc` — `realloc` does not zero new memory, so without
this the first crash of a slot could see garbage in `last_crash_ms` and
mis-classify the very first crash as a "repeat."

## Delay-sum vs. the crashloop wall gate

`bench/actors/crash_loop.march` sends 20 `Poison` messages to a
`one_for_one`-supervised child (`max_restarts 100 within 60`), asserting
the current incarnation still answers afterward. Streak `s`'s delay (before
jitter) is `25 << min(s-1, 7)`, capped at `min(...,5000)` — but `25 << 7 =
3200`, so the `5000` ceiling is never actually reached; the real per-streak
ceiling is 3200ms. Streaks 2–8 grow 50, 100, 200, 400, 800, 1600, 3200;
streaks 9–20 (12 more crashes) each cap at 3200. Sum (pre-jitter):
`(50+100+200+400+800+1600+3200) + 12*3200 = 6350 + 38400 = 44750`ms ≈
44.75s — comfortably under `scripts/actor-load.sh`'s 60s wall gate for
`crashloop`, even accounting for `±25%` jitter (worst case ≈56s). Measured:
46.1s and 46.14s across two full runs (see Verification), both well inside
the gate — no fixture change needed.

## `MARCH_SUP_TRACE=1` excerpt (bench/actors/crash_loop.march)

```
march: supervisor backoff child=0 streak=1 delay_ms=0
march: supervisor backoff child=0 streak=2 delay_ms=39
march: supervisor backoff child=0 streak=3 delay_ms=124
march: supervisor backoff child=0 streak=4 delay_ms=155
march: supervisor backoff child=0 streak=5 delay_ms=370
march: supervisor backoff child=0 streak=6 delay_ms=923
march: supervisor backoff child=0 streak=7 delay_ms=1754
march: supervisor backoff child=0 streak=8 delay_ms=3883
```

## Verification

- `dune build --root . bin/main.exe` — clean build.
- `scripts/run-tests.sh` (full, not `-q`) — all suites passed (859
  march-stdlib tests + 58 stdlib_march tests), including the 20 Slow
  compiled-adversarial/JIT-parity tests.
- `dune build @test/runtest --root .` — 849 march-compiler tests, green.
- `bash scripts/actor-load.sh` (full, all four scenarios) —
  `fanin`/`churn`/`callstorm`/`crashloop` all `PASS`; `crashloop` wall time
  46.1s, under the 60s gate.
- Supervision golden byte-comparison: compiled
  `examples/supervision_strategies.march` with the pre-Task-16 runtime
  (file-copy swap of `runtime/march_runtime.c` / `march_scheduler.c` back
  to `HEAD`, rebuilt, ran, then restored — **not** `git stash`, which is
  forbidden in this shared worktree) versus the post-Task-16 runtime.
  Filtering out `[Worker] work #N` lines (a pre-existing, unrelated print
  race between concurrently-running worker actors — confirmed flaky
  run-to-run on *both* the pre- and post-Task-16 binaries independently,
  3-6 repeated runs each), every substantive line (spawned/restarted pids,
  `wa unchanged`/`wb restarted` booleans, `alive` checks) is byte-identical
  between pre and post, across all three strategies (`one_for_one`,
  `one_for_all`, `rest_for_one`).
