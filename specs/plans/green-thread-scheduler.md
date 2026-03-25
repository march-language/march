# Green Thread Scheduler — Implementation Plan

## Overview

Replace the current actor-mailbox scheduler (message-passing only) with a
full M:N green-thread scheduler that can run any March function as a
lightweight process.  Implemented incrementally across phases:

```
OS threads (N=1)     OS threads (N=worker pool)
      │                         │
  Phase 1             Phase 3 (work-stealing)
  │                   │
  Basic ucontext      Multi-thread + atomic deque
  single scheduler    per-scheduler local queue
```

## Phase 1 — Basic green thread scheduler in C runtime ✅

**Goal:** Prove out the core context-switching primitives on a single OS thread.

**Files:**
- `runtime/march_scheduler.h` — public API + types
- `runtime/march_scheduler.c` — implementation
- `test/test_scheduler.c` — C test suite (4 tests)
- `test/dune` — dune rule to compile and run C tests

**Process struct** (`march_proc`):
| Field | Type | Purpose |
|---|---|---|
| `pid` | `int64_t` | Unique ID (monotonic counter) |
| `status` | `march_proc_status` | `READY / RUNNING / WAITING / DEAD` |
| `priority` | `march_proc_priority` | `NORMAL / HIGH` |
| `reductions` | `int64_t` | Budget remaining this quantum |
| `stack_base` | `void *` | mmap'd stack (above PROT_NONE guard page) |
| `stack_alloc` | `size_t` | Total mmap size (stack + guard) |
| `mailbox` | `march_mbox_node *` | Message queue head (Phase 2) |
| `ctx` | `ucontext_t` | Saved execution context |
| `fn` / `arg` | fn ptr + `void *` | Entry point |
| `next` | `march_proc *` | Intrusive run-queue link |

**Scheduler** (`march_scheduler`): single global instance, single OS thread.
- FIFO run queue (intrusive linked list)
- `sched_ctx`: the scheduler's own `ucontext_t`; all processes yield back here
- Round-robin: dequeue → run quantum → re-enqueue if READY, free if DEAD

**API:**
```c
void         march_sched_init(void);
void         march_sched_run(void);
march_proc  *march_sched_spawn(void (*fn)(void *), void *arg);
void         march_sched_yield(void);
void         march_sched_tick(void);   // decrement; yield if budget == 0
void         march_sched_exit(void);
```

**Context switching:** `ucontext_t` / `makecontext` / `swapcontext`.
Each stack is `mmap(PROT_READ|PROT_WRITE)` with a `PROT_NONE` guard page.
Default stack size: `MARCH_STACK_SIZE` = 64 KiB.
Reduction budget: `MARCH_REDUCTION_BUDGET` = 4000.

**Tests (all passing):**
1. `test_spawn_1000` — 1000 processes increment a counter; verify == 1000
2. `test_yield_interleaving` — explicit yields produce A→B→A→B ordering
3. `test_reduction_preemption` — `march_sched_tick()` causes automatic yield
4. `test_nested_spawn` — processes can spawn child processes

---

## Phase 2 — Message passing + PROC_WAITING

**Goal:** Allow processes to block on mailbox receive without busy-waiting.

Additions:
- `march_mbox_node *mailbox` — FIFO message queue (intrusive list)
- `march_sched_send(march_proc *, void *msg)` — enqueue message + wake target
- `march_sched_recv(void)` — dequeue next message, or park as PROC_WAITING
- Wakeup: `march_sched_wake(pid)` — re-enqueue a WAITING process
- Integrate with the existing March actor mailbox in `march_runtime.c`

---

## Phase 3 — Multi-thread M:N with work-stealing

**Goal:** Scale to multiple OS threads with minimal contention.

Architecture:
- `N` OS threads, each with its own `march_scheduler` instance
- Per-scheduler lock-free deque (Chase-Lev or similar)
- Work-stealing: idle thread steals from the tail of a victim's deque
- Global spawn balancer: new processes assigned to the least-loaded thread
- Shutdown: barrier + quiescence detection

Prerequisite: Phase 2 mailbox wakeup must work correctly before
multi-threading to avoid lost-wakeup races.

---

## Phase 4 — Stack growth (segmented or copying)

**Goal:** Start each process with a small stack (4 KiB) and grow on demand.

Options:
1. **Segmented stacks** (LLVM split-stacks): each frame checks stack limit;
   allocates a new segment on overflow.  Requires compiler cooperation.
2. **Copying stacks** (Go-style): on overflow (via signal handler / guard
   page trap), copy the entire stack to a larger allocation and fix up
   all pointers.  Simpler but requires scan-able stack frames.

Phase 1 uses 64 KiB fixed stacks as a safe baseline.

---

## Build integration

C runtime files (`runtime/`) are not part of the OCaml dune build — they are
emitted alongside compiled March programs by the LLVM code generator.

For testing the C scheduler standalone, `test/dune` contains a `(rule)` that
uses `%{cc}` (the OCaml-configured C compiler) to compile and run
`test/test_scheduler.c` as part of `dune runtest`.

```dune
(rule
 (targets test_scheduler_runner)
 (deps    test_scheduler.c
          ../runtime/march_scheduler.c
          ../runtime/march_scheduler.h)
 (action  (run %{cc} -std=gnu11 -Wall -Wextra -I../runtime
               -o %{targets}
               test_scheduler.c ../runtime/march_scheduler.c)))
```
