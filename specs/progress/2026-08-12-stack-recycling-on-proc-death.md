# Recycle green-thread stack reservations on proc death

Task 12 of the actor-system-hardening plan
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`).

## What shipped

- `runtime/march_scheduler.c`: a global LIFO free-list of retired stack
  reservations (`g_stack_free` / `stack_free_node`, guarded by
  `g_stack_free_mu`). `stack_retire(mmap_base)` pushes a dead proc's
  reservation onto it; `stack_reuse(...)` pops one and re-arms it to the
  exact layout `stack_alloc_lazy` hands out fresh (mprotect the whole range
  PROT_NONE, then re-commit the top `MARCH_STACK_INITIAL` window;
  `MADV_FREE` on the reclaimed body so the kernel can drop the physical
  pages immediately rather than waiting for pressure).
- `sched_spawn_common` now tries `stack_reuse` before falling back to
  `stack_alloc_lazy`.
- `sched_loop`'s `PROC_DEAD` reap branch, immediately after the existing
  Task 8 waiter-wake block and before the "leak `p` on purpose" comment,
  now retires the stack (NULLs `stack_mmap_base`/`stack_base`, bumps
  `march_stat_counters[MARCH_STAT_STACKS_RECYCLED]`). The `march_proc`
  struct itself is unchanged — still leaked forever, per the existing
  cross-thread-reader contract documented at that site.
- Both the recycle-on-death path and the reuse-on-spawn path are compiled
  out under `MARCH_ASAN_BUILD` (kept leaking there) — ASan's fake-stack
  fiber annotation assumes a stack address range is never handed to a
  second, unrelated fiber.
- `march_sched_init()` deliberately does **not** clear `g_stack_free` on
  re-init: the mappings are process-wide OS state, so a second
  `march_sched_init()` call in the same process (as C test harnesses do)
  can still reuse reservations retired before the re-init.
- `test/test_scheduler_churn.c` + `test/dune` rule (cloned from the
  `test_scheduler_timer` pair): churns 3000 procs through spawn->run->death,
  asserts `march_sched_stat(5) >= 2900`; a second `march_sched_init()` +
  100-proc batch proves the free-list survives re-init and gets consumed.
  `alarm(60)` watchdog.

## Safety argument (also in the code comment at both the stack-reuse call
site and the retire call site)

After `sched_loop` observes `PROC_DEAD` for a reaped proc, that proc's stack
can never be touched again: the proc never runs again (`PROC_DEAD` is
terminal; the dispatch CAS's DEAD->RUNNING exception applies only to
`march_task_cancel_by_id`'s pre-completion store, which cannot occur after
the trampoline's own DEAD store since the proc has already exited by then).
Stale cross-thread readers of a leaked `march_proc` (e.g.
`march_actor_meta.green_thread`) only ever touch `status`/`pid`/mailbox
fields, never the stack. The SIGSEGV handler reads `s->current->stack_*`
only for the RUNNING proc on the faulting thread, and a RUNNING proc is
never reaped. The `MARCH_DEBUG` fatal walker reads `q->stack_mmap_base`
under no lock; it already skips NULL (`if (!q || !q->stack_mmap_base)
continue;`), and we NULL the field before returning the mapping to the
free-list.

## Diagnostic sub-task: the spawn-churn hang is NOT the VMA cliff

Before implementing, bisected `bench/actors/spawn_churn.march`-shaped
workloads (spawn -> send -> kill, repeated) at N = 2000/4000/5000/6000/8000
actors. 2000 and 4000 complete in ~0-1s; 5000, 6000, and 8000 all hang
**forever** (confirmed with a 90s wait, not just "slow" — zero progress,
not a timeout artifact of a merely-large N).

`sample <pid> 2` during the N=5000 hang showed **every** OS thread (5
scheduler threads + the preemption daemon) parked in `sched_loop`'s
`nanosleep`-based idle-poll, at ~10% total CPU (that 10% is the
preemption daemon's steady-state `pthread_kill` signalling, not scanning)
and flat 78MB RSS. Nobody was inside `march_sched_wait_idle`'s
registry-scan loop when sampled, and nobody was CPU-bound. That rules out
both of the brief's candidate theories:

- **(a) mmap/VA exhaustion** — RSS/footprint stayed flat at ~78MB across
  the hang; no mmap failure path was ever hit (that returns NULL loudly and
  this build has no such log line printed before the hang).
- **(b) quadratic `wait_idle`/`wake_idle_daemons` registry scan** — that
  would show as sustained CPU burn inside the scan loop, not near-zero CPU
  with every thread asleep in the scheduler's own idle path.

What the sample is consistent with: **(c) a lost wakeup**, most likely
somewhere in the `kill()`/actor-death interaction — some proc ends up
parked in a non-terminal status (`PROC_WAITING`/`PROC_PARKED`) that never
gets a matching wake, so `g_live_procs` never reaches 0, `g_all_done` never
gets set, and every scheduler thread cycles in its idle-nanosleep backoff
indefinitely. This is a genuine deadlock, distinct from (and apparently hit
well before) the `MARCH_MAX_PROCS` = 65536 registry cliff Task 13 targets.

**Consequence for the gate**: `bash scripts/actor-load.sh churn` still
XFAILs after this task (as the brief anticipated), but for a different
reason than assumed — the harness now times out around N~5000, not at the
40000-actor target or at the registry cliff. Task 13 (or a new task) needs
to actually find and fix the lost-wakeup in the kill/wake path before the
`churn` gate can be un-XFAILed; simply fixing the registry cliff will not
be sufficient on its own. No fix for this was attempted here — out of
scope for Task 12, and the brief's 15-minute diagnostic budget was for
finding out what the hang is, not fixing it.

## Recycling verified independently of the hang

Because the hang caps actor-level N well below where stack-reservation
volume would otherwise matter, the recycling benefit was verified directly
against the raw C scheduler API (no actor/mailbox machinery, so the hang
above does not apply):

- `test_scheduler_churn_runner`: 3000 spawns -> all 3000 deaths recycle
  their stack (`recycled=3000`), reproducible across 5 consecutive runs.
- A two-phase A/B (pre-fix `march_scheduler.c` vs. this commit's, both
  built against the same harness: 3000 spawns+deaths, then a *second*
  `march_sched_init()` + 100 more spawns+deaths): counting live 1MiB
  `VM_ALLOCATE` regions via `vmmap` while the process holds open,
  **before** = 3100 distinct reservations (every spawn gets its own mmap,
  nothing ever reused); **after** = 3000 (the second batch's 100 spawns
  were served entirely from the free-list populated by the first batch's
  deaths — zero new mmaps for phase 2).

## Notes for future tasks

- Task 13 (registry cliff): the diagnosis above means Task 13 should not
  assume fixing `MARCH_MAX_PROCS`/registry scanning alone unblocks
  `scripts/actor-load.sh churn` — there is a lower-N lost-wakeup deadlock
  in the kill/wake path to find first. Worth re-running the same
  bisect-then-`sample` recipe used here once that path changes.
- `MARCH_STAT_STACKS_RECYCLED` (index 5) is now live; `Scheduler.stat(5)`
  (stdlib, Task 6) reports it.
