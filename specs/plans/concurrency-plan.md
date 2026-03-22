# Concurrency — Implementation Plan

## Current State

### Scheduler (`lib/scheduler/`)

**What exists**:

`scheduler.ml`:
- Reduction counting with 4,000 budget per quantum
- Process states: `PReady`, `PRunning`, `PWaiting`, `PDone`, `PDead`
- Run queue with `dequeue`, `enqueue`, `park` (move to wait list), `wake`
- Single-threaded cooperative scheduling — one actor runs at a time

`work_pool.ml`:
- Chase-Lev work-stealing deque implementation using OCaml 5 `Atomic.t`
- Per-worker deques with lock-free `push`, `pop` (owner LIFO), `steal` (thief FIFO)
- Steal-half semantics

`mailbox.ml`:
- Michael-Scott lock-free MPSC queue
- Uses OCaml 5 `Atomic.t` for CAS operations

`task.ml`:
- Task type with status tracking and tier designation

**What's missing**:
- **No actual multi-threading** — the scheduler runs on a single OS thread; actors are cooperative-only
- **Work pool not integrated** — `work_pool.ml` exists as infrastructure but is never called from the main scheduler or runtime
- **No Domain spawning** — OCaml 5 Domains are not used for parallelism
- **Mailbox not wired to actors** — actor `send` in `eval.ml` is synchronous, not going through the mailbox queue
- **No preemption mechanism** — reduction counting exists but there's no yield point insertion in compiled code

### Perceus RC — Thread Safety (`lib/tir/perceus.ml`, `runtime/march_runtime.c`) — ✅ Atomic RC COMPLETE (Track C)

**What exists**:
- Runtime header: `_Atomic int64_t rc` — the refcount field IS declared atomic in the C struct
- ✅ `march_incrc`/`march_decrc` now use proper atomic operations with correct memory ordering (Track C, passed ThreadSanitizer)
- ✅ FBIP RC data race in actor dispatch fixed
- ✅ Message RC double-increment leak fixed (`march_send` no longer increments RC)
- Works for both single-threaded and multi-threaded compiled code

**What's still missing**:
- Biased reference counting (thread-local fast path, shared slow path)
- Deferred decrements for cross-thread sharing

### Supervision (`lib/ast/ast.ml`, `lib/eval/eval.ml`)

**What exists**:
- `DActor` has `supervision` field in AST (optional strategy, max_restarts, restart_window)
- Basic actor lifecycle: spawn, send, kill, is_alive
- `ESpawn` creates actors, `ESend` sends messages, `kill` terminates
- No crash recovery — if an actor panics, it's dead permanently

**What's missing**:
- Monitor/link registration between actors
- `Down` message delivery on actor crash
- Supervisor pattern (one_for_one, one_for_all, rest_for_one)
- Restart logic with max_restarts sliding window
- Epoch-stamped capabilities (`Cap(A, e)`)

---

## Target State (from specs)

Per `2026-03-19-scheduler-design.md`, `2026-03-19-two-tier-scheduler.md`, `specs/supervision-plan.md`, `specs/epochs-design.md`:

### Two-Tier Scheduler
1. **Cooperative tier**: Reduction-counted (4K budget), FIFO round-robin, all actors live here
2. **Work-stealing tier**: Opt-in via `Cap(WorkPool)`, Chase-Lev deques, for CPU-bound tasks
3. **Cross-tier communication**: Lock-free MPSC mailbox queues
4. **Actor placement**: Actors always on cooperative tier; tasks can be on either

### Atomic Reference Counting
1. Atomic inc/dec for shared heap objects
2. Biased RC as optimization: thread-local fast path avoids atomics for locally-owned objects
3. Per-actor arenas prevent most cross-actor sharing (reducing atomic RC pressure)

### Supervision Trees
1. **Monitors**: Actor A monitors Actor B → gets `Down(B, reason)` message on B's crash
2. **Links**: Bidirectional — if A links to B and B crashes, A also crashes (unless A traps exits)
3. **Supervisors**: Actors with a `supervise` block defining child specs and restart strategy
4. **Restart strategies**: one_for_one, one_for_all, rest_for_one
5. **Max restarts**: Sliding window — if N restarts happen within T seconds, supervisor gives up

### Epochs
1. **Epoch-stamped capabilities**: `Cap(A, e)` — invalidated when actor A restarts at epoch `e+1`
2. **LiveCap**: Supervisor-managed capability that auto-updates on restart
3. **Down-before-Dead guarantee**: `Down` messages delivered before actor marked as dead
4. **Drop handlers**: Resource cleanup on crash (file handles, network connections)

---

## Implementation Steps

### Phase 1: Wire Mailbox into Actor Runtime (Medium complexity, Low risk)

**Step 1.1: Replace synchronous send with mailbox enqueue**
- File: `lib/eval/eval.ml`
- Currently `ESend` directly calls the actor's handler. Change to enqueue message in actor's mailbox
- Each actor gets a `Mailbox.t` at spawn time
- Estimated effort: 2 days

**Step 1.2: Add message dispatch loop**
- File: `lib/scheduler/scheduler.ml`
- The scheduler's run loop should: dequeue an actor, drain its mailbox (up to reduction budget), then yield
- Use existing reduction counting for preemption
- Estimated effort: 2 days

**Step 1.3: Integrate scheduler into eval main loop**
- File: `lib/eval/eval.ml`, `bin/main.ml`
- Replace the current "run main, then process actor messages" approach with the scheduler driving execution
- Main program itself becomes a task on the cooperative scheduler
- Estimated effort: 3 days
- Risk: This is a significant architectural change to the interpreter

### Phase 2: Multi-threaded Scheduler (High complexity, High risk)

**Step 2.1: Spawn OCaml 5 Domains for worker threads**
- File: `lib/scheduler/scheduler.ml`
- Use `Domain.spawn` to create N worker domains (default: `Domain.recommended_domain_count()`)
- Each domain runs the cooperative scheduler loop
- Actors are still single-threaded (one domain processes one actor at a time, no sharing)
- Estimated effort: 3 days

**Step 2.2: Actor affinity and migration**
- File: `lib/scheduler/scheduler.ml`
- Initially: actors pinned to the domain that spawned them
- Later: allow migration when a domain is idle (steal an actor from a busy domain)
- Estimated effort: 2 days (pinned), 5 days (migration)
- Risk: Actor migration requires careful handling of mutable state and mailbox references

**Step 2.3: Wire work-stealing pool for tasks**
- File: `lib/scheduler/work_pool.ml`, `lib/scheduler/scheduler.ml`
- Tasks (non-actor work items) opt into the work-stealing tier via `Cap(WorkPool)`
- Use existing Chase-Lev deque implementation
- Workers steal from random victims when their local queue is empty
- Estimated effort: 3 days

**Step 2.4: Cross-tier communication**
- File: `lib/scheduler/mailbox.ml`
- Tasks on the work-stealing tier may need to send messages to actors on the cooperative tier
- Use the MPSC mailbox (already implemented) as the bridge
- Actor wakeup: when a message arrives for a parked actor, wake it
- Estimated effort: 2 days

### Phase 3: Atomic Reference Counting (High complexity, High risk) — ✅ Step 3.1 COMPLETE (Track C)

**Step 3.1: Make RC operations atomic in C runtime** — ✅ DONE (Track C, committed, passed ThreadSanitizer)
- File: `runtime/march_runtime.c`
- ✅ RC operations now use proper atomic semantics
- ✅ FBIP RC data race fixed (C1 in correctness audit)
- ✅ Scheduler `scheduled` flag race fixed (H1)
- ✅ Message RC double-increment leak fixed (H7)
- ✅ Scheduler processes multiple messages per cycle (M1, starvation fix)

**Step 3.2: Biased reference counting optimization**
- File: `runtime/march_runtime.c`
- Add thread-local RC table: each thread maintains a `(ptr → local_delta)` map
- Increments/decrements on locally-owned objects update the local delta (no atomics)
- Periodically (or on thread sync points), flush local deltas to the shared atomic RC
- Estimated effort: 5 days
- Risk: Flushing strategy affects performance and correctness; too infrequent = memory leaks, too frequent = defeats the purpose

**Step 3.3: Per-actor arena optimization**
- File: `runtime/march_runtime.c`
- Allocations within an actor use a per-actor arena (bump allocator)
- Objects that escape the actor (sent via message) get promoted to the shared heap with atomic RC
- Estimated effort: 3 days
- Dependency: Need escape analysis to detect which objects escape actor boundaries (distinct from function-level escape analysis in `lib/tir/escape.ml`)

**Step 3.4: Yield point insertion for compiled code**
- File: `lib/tir/llvm_emit.ml`
- Insert reduction counter checks at function entries and loop back-edges
- When budget exhausted, call `march_yield()` which saves state and returns to scheduler
- Estimated effort: 4 days
- Risk: Yield points in compiled code require saving/restoring continuation state; may need stack switching or coroutine support

### Phase 4: Supervision Trees (Medium complexity, Medium risk)

**Step 4.1: Monitor/link registration**
- Files: `lib/eval/eval.ml`, `lib/scheduler/scheduler.ml`
- Add `monitor(target_actor)` builtin — returns a monitor reference
- Add `link(target_actor)` builtin — bidirectional link
- Store monitor/link sets in actor metadata
- Estimated effort: 2 days

**Step 4.2: Down message delivery**
- File: `lib/scheduler/scheduler.ml`
- When an actor crashes (unhandled exception or `kill`):
  1. Set actor state to `PDead`
  2. For each monitor: enqueue `Down(actor_id, reason)` message to the monitoring actor
  3. For each link: crash the linked actor (unless it traps exits)
- Maintain Down-before-Dead ordering guarantee
- Estimated effort: 3 days

**Step 4.3: Supervisor pattern**
- Files: `lib/eval/eval.ml`, `lib/desugar/desugar.ml`
- Desugar `supervise` blocks into supervisor actor creation
- Supervisor actor maintains child spec list and restart strategy
- On receiving `Down` from a child:
  - `one_for_one`: restart only the crashed child
  - `one_for_all`: restart all children
  - `rest_for_one`: restart the crashed child and all children started after it
- Estimated effort: 5 days

**Step 4.4: Max restarts sliding window**
- File: `lib/eval/eval.ml` or `lib/scheduler/scheduler.ml`
- Track restart timestamps in a circular buffer
- If count exceeds max_restarts within restart_window, supervisor itself crashes (escalates)
- Estimated effort: 1 day

### Phase 5: Epochs (Medium complexity, Medium risk)

**Step 5.1: Epoch counter on actors**
- File: `lib/eval/eval.ml`, `lib/ast/ast.ml`
- Each actor has a monotonically increasing epoch counter
- Incremented on each restart
- Estimated effort: 0.5 days

**Step 5.2: Epoch-stamped capabilities**
- File: `lib/typecheck/typecheck.ml`, `lib/eval/eval.ml`
- `Cap(A, e)` carries the epoch — using a stale cap produces a runtime error (or compile-time error if detectable)
- Supervisor's `LiveCap(A)` automatically updates to current epoch
- Estimated effort: 3 days

**Step 5.3: Drop handlers**
- Files: `lib/ast/ast.ml`, `lib/eval/eval.ml`
- Add `drop` block to actor definitions for resource cleanup
- On actor crash: run drop handler before restarting
- Must handle the case where the drop handler itself panics (skip and log)
- Estimated effort: 3 days

**Step 5.4: Compiled supervision support**
- File: `lib/tir/llvm_emit.ml`, `runtime/march_runtime.c`
- Lower supervisor patterns to C runtime calls
- Runtime maintains supervisor tree structure
- `march_supervisor_on_down()` callback dispatches restart strategy
- Estimated effort: 5 days
- Dependency: Phases 1–4 working in interpreter first

---

## Dependencies

```
Phase 1 (Mailbox wiring) ← no blockers
    ↓
Phase 2 (Multi-threading) ← depends on Phase 1
    ↓
Phase 3 (Atomic RC) ← depends on Phase 2 for testing; step 3.1 can happen independently

Phase 4 (Supervision) ← depends on Phase 1 (needs mailbox-based actors)
    ↓
Phase 5 (Epochs) ← depends on Phase 4

Phase 3, Step 3.4 (yield points) ← depends on Phase 2
```

Phase 3 Step 3.1 (atomic RC in C) can be done immediately — it's a runtime-only change with no compiler dependencies.

## Testing Strategy

### Scheduler Tests
1. **Cooperative scheduling**: N actors sending messages to each other; verify all messages delivered
2. **Reduction budget**: Actor doing heavy computation yields after 4K reductions
3. **Work stealing**: CPU-bound tasks distributed across domains; verify speedup
4. **Cross-tier**: Task sends result to actor; verify delivery
5. **Stress test**: 10,000 actors sending random messages; no deadlocks or lost messages

### Atomic RC Tests
1. **Correctness**: Multi-threaded increment/decrement; verify final RC is correct
2. **No use-after-free**: Stress test with concurrent inc/dec; run with AddressSanitizer
3. **Biased RC**: Thread-local operations don't touch atomic; verify with performance counters
4. **Arena**: Objects allocated in actor arena are fast; cross-actor sends promote correctly

### Supervision Tests
1. **Monitor notification**: A monitors B; B crashes; A receives Down message
2. **Link propagation**: A links to B; B crashes; A also crashes
3. **one_for_one**: Supervisor with 3 children; child 2 crashes; only child 2 restarts
4. **one_for_all**: Same setup; all 3 restart
5. **rest_for_one**: Same setup; children 2 and 3 restart
6. **Max restarts**: Child crashes repeatedly; supervisor escalates after max_restarts

### Epoch Tests
1. **Stale cap detection**: After actor restart, old cap produces error
2. **LiveCap update**: Supervisor's LiveCap tracks current epoch
3. **Drop handler**: Actor with open file handle crashes; drop handler closes it
4. **Drop handler panic**: Drop handler panics; actor still restarts (drop failure logged)

## Open Questions

1. **Interpreter vs. compiled scheduling**: Should the interpreter use real OCaml Domains, or should multi-threading be compiled-only? The interpreter currently uses a simple event loop; adding real parallelism to the tree-walker is complex.

2. **Stack switching for yield points**: Compiled code yield points need to save/restore state. Options: (a) setjmp/longjmp, (b) libco coroutines, (c) compile to CPS, (d) split stacks. Each has tradeoffs for performance and portability.

3. **GC interaction**: If we add per-actor arenas, objects that escape need promotion. When does promotion happen — at send time, or lazily? Eager promotion is simpler but slower; lazy promotion requires read barriers.

4. **Actor-to-actor pointer sharing**: The current spec says per-actor arenas prevent cross-actor pointers. But if an actor sends a large data structure, do we deep-copy it into the receiver's arena? That's expensive for large messages. Alternative: shared immutable heap with atomic RC.

5. **REPL concurrency**: How should the REPL handle multi-threaded actors? Currently the REPL is single-threaded. Options: (a) REPL stays single-threaded, actors run on separate domains, (b) REPL is an actor itself on the cooperative scheduler.

6. **Compiled yield points and LLVM**: Inserting yield checks in LLVM IR is straightforward (check reduction counter, branch to yield stub). But restoring execution after yield requires either stack switching or continuation capture. Which approach?

## Estimated Total Effort

| Phase | Effort | Risk |
|-------|--------|------|
| Phase 1: Mailbox wiring | 7 days | Low |
| Phase 2: Multi-threading | 10–15 days | High |
| Phase 3: Atomic RC | 13 days | High |
| Phase 4: Supervision | 11 days | Medium |
| Phase 5: Epochs | 11.5 days | Medium |
| **Total** | **52.5–57.5 days** | |

## Suggested Priority

~~1. **Phase 3 Step 3.1** — atomic RC~~ ✅ DONE (Track C)
1. **Phase 1** — prerequisite for everything; makes actor messaging correct
2. **Phase 4** — supervision trees are a key language differentiator
3. **Phase 2** — real parallelism; high value but high risk
4. **Phase 5** — epochs refine the supervision story
5. **Phase 3 Steps 3.2–3.4** — performance optimizations for multi-threaded RC
