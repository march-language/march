# A dead proc's execution context is freed

Shipped 2026-09-17. Phase 1 of [[2026-09-17-proc-struct-reclamation]] (the design for item
5 of [[2026-08-11-actor-hardening-distributed-plane]]); the rest of that item stays open.

## What changed

`march_proc.ctx` was an embedded `ucontext_t` — **880 of the struct's 1136 bytes** on
macOS/arm64 — inside a struct that is deliberately never freed (the "Deliberately NOT
munmap ... / free(p)" comment on the `PROC_DEAD` reap branch). It is now `ucontext_t *`:
`calloc`'d in `sched_spawn_common` before `getcontext`, and freed and NULLed in the reap
branch beside the stack retire.

Retained per dead proc: **1136 → 256 B** for a task or `main` (4.4×), and **1408 → 528 B**
for an actor, whose never-freed `march_actor_meta` (272 B) is the other term.

## Why it is safe

The same argument that has licensed stack recycling since
[[2026-08-12-stack-recycling-on-proc-death]], and the reap branch already stated it for
the context in as many words ("p's ucontext/stack_base are stale/garbage; both are fine
because a DEAD proc is never dispatched or grown again"):

- **Nothing reads it after death.** The reason the struct is never freed is stale
  cross-thread readers (`march_actor_meta.green_thread`, the Task handle); every one of
  them touches `status`, `pid` or mailbox fields. None touches the context. The only
  readers of `ctx` are `getcontext`/`makecontext` at spawn and the `swapcontext` pairs on
  dispatch and suspend, all of which require a proc that can still run.
- **Nothing writes it at the reap.** The proc's final `swapcontext` (in the trampoline)
  saves into it *before* control reaches the scheduler thread that reaps it.
- **A reaped proc is never dispatched again.** Checked on the one path that looked like it
  could: `march_task_cancel_by_id` stores `PROC_DEAD` into a proc but never wakes or
  enqueues it, so a cancel against an already-reaped proc changes nothing reachable.
- **A regression crashes at the cause.** Dispatch now aborts with `dispatch of reaped pid N
  (no context)` on a NULL `ctx`, rather than switching into freed memory.

## Evidence

- `test/test_scheduler_churn.c` asserts `Scheduler.stat(7)` (new:
  `MARCH_STAT_CTX_RELEASED`, "execution contexts released at proc death") equals the
  number of deaths **exactly** — 3000 of 3000. Proven non-vacuous: with the `free`
  disabled the counter reads 0 and the assertion fails; restored, it passes.
- **Measured, same box, A/B against the base runtime** (`scripts/actor-load.sh`, the base
  scheduler swapped in by file copy and restaged, then this one restored and run again so
  the result is not an ordering artefact; load average ~4–5):

  | scenario | base | this change | this change, rerun |
  |---|---|---|---|
  | churn — peak RSS | 139 MB | **100 MB** | **101 MB** |
  | fanin / callstorm / crashloop — peak RSS | 27 / 4 / 3 MB | 27 / 4 / 3 MB | 27 / 4 / 2 MB |
  | wall ms (fanin, churn, callstorm) | 381, 903, 810 | 509, 922, 586 | 337, 755, 452 |

  **−28% peak RSS where procs churn**, nothing moved where they do not, and wall time is
  inside run-to-run noise (the base column sits between the two runs of this change on
  every scenario). crashloop is ~46 s on every run: it is paced by supervision backoff.
- All seven C scheduler tests; the full `dune runtest` tree — every native
  compile-and-run golden, including the kill/restart/supervision fixtures — with one
  failure unrelated to this change (`alloc_contract` 46: the compiler's library walker hit
  a temp file a concurrently running test deleted mid-walk; 54/54 when rerun alone); and
  all eleven two-node scenarios (`partition` skips without root).
- **ASAN is CI's**: the context is freed in ASAN builds too (unlike the stack), so the
  sanitize gate's native and two-node sweeps would report any stale read as a
  use-after-free. ASAN cannot run on this Mac (Falcon) and Docker was down.

## Deviation from the design

The design specified a slab free-list shaped like `g_stack_free`. A plain `calloc`/`free`
shipped instead: the stack free-list exists to avoid mmap/munmap and VMA churn, which an
880-byte malloc does not incur, and *freeing* is what returns peak memory — a free-list
would have kept holding the high-water mark, which is the property being removed.
