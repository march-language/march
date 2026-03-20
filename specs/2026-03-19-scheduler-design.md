# Scheduler Design: Cooperative + Work-Stealing

March uses a **two-tier scheduler** with cooperative reduction-counted scheduling as the default and an explicit opt-in work-stealing pool as an escape hatch for CPU-bound parallel work.

**Design principles:**
- Actors and tasks run on the cooperative tier by default — safe, fair, predictable
- Work-stealing is a "sharp knife" — requires an unforgeable `Cap(WorkPool)` capability threaded from `main()`
- Cross-tier communication via mailboxes (BEAM model) — no artificial isolation between tiers
- Tasks are supervised — failure propagates through the supervision tree
- `Sendable` enforced on all cross-thread closures and messages

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                  March Runtime                   │
├──────────────────────┬──────────────────────────┤
│  Cooperative Sched.  │   Work-Stealing Pool     │
│  (default)           │   (Cap(WorkPool))        │
│                      │                          │
│  ┌───┐ ┌───┐ ┌───┐  │  ┌──────┐ ┌──────┐      │
│  │RQ1│ │RQ2│ │RQ3│  │  │Deque1│ │Deque2│      │
│  └───┘ └───┘ └───┘  │  └──────┘ └──────┘      │
│  1 per core          │  1 per core              │
│  Reduction-counted   │  Run-to-completion or    │
│  Round-robin         │  steal-half              │
│                      │                          │
│  Actors + Tasks      │  Tasks only              │
│  (Pid, Task)         │  (Task)                  │
├──────────────────────┴──────────────────────────┤
│  Shared: Mailboxes, Timer Wheel, Supervisors    │
└─────────────────────────────────────────────────┘
```

## Tier 1: Cooperative Scheduler (Default)

### Reduction Counting

Every actor and task on the cooperative tier gets a **reduction budget** per scheduling quantum. A "reduction" is one unit of work — roughly one function call, pattern match, or message send. When the budget is exhausted, the scheduler preempts the actor/task and moves to the next one in the run queue.

**Budget**: 4,000 reductions per quantum (matches BEAM). Tunable per-node via runtime config.

**Yield points** — the compiler inserts reduction counter decrements at:
- Function application (`EApp`)
- Pattern match evaluation (`EMatch`)
- Message send (`ESend`)
- Loop/recursion entry points

In the tree-walking interpreter, this is a counter check in `eval`. In compiled output (future), yield checks piggyback on function prologues (Go-style).

```march
# From the programmer's perspective, this is invisible.
# The scheduler preempts transparently between reductions.
def fib(n: Int) -> Int do
  # ← yield check inserted here by compiler
  if n <= 1 then n
  else fib(n - 1) + fib(n - 2)
end
```

### Run Queues

One run queue per OS thread (1 per core by default). Each queue is a FIFO of ready actors/tasks.

**Scheduling order:**
1. Check local run queue, pick the first ready actor/task
2. Run it for up to 4,000 reductions
3. If it yields (budget exhausted) → re-enqueue at the tail
4. If it blocks (waiting on `receive`) → move to wait queue
5. If the local queue is empty → steal one task from another queue's tail

### Priority Levels (Future)

> **Note:** Priority levels within the cooperative tier are deferred to a future version. The initial implementation uses a single priority level. When added, the design will follow BEAM's model with `low`, `normal`, `high`, and `max` priorities, controlled via a `Cap(Priority)` capability to prevent casual use.

## Tier 2: Work-Stealing Pool (Opt-In)

### Capability-Gated Access

The work-stealing pool is accessed exclusively through `Cap(WorkPool)`, an unforgeable capability granted by the runtime to `main()`. Functions that need work-stealing must declare the capability in their signature — making the requirement visible and grep-able throughout the codebase.

```march
# The runtime grants Cap(WorkPool) to main()
def main(pool: Cap(WorkPool)) do
  # Regular cooperative task — no capability needed
  let t1 = Task.spawn(fn () -> fib(30) end)

  # Work-stealing task — requires the capability
  let t2 = Task.spawn_steal(pool, fn () ->
    heavy_matrix_multiply(a, b)
  end)

  let results = Task.await_all([t1, t2])
  results
end
```

Any function that needs work-stealing must thread the capability:

```march
def parallel_sort(pool: Cap(WorkPool), data: List(a)) -> List(a) do
  let chunks = List.chunk(data, 4)
  let tasks = chunks |> List.map(fn chunk ->
    Task.spawn_steal(pool, fn () -> sort(chunk) end)
  end)
  tasks |> List.map(Task.await) |> List.flatten()
end

# Caller sees the requirement in the type
parallel_sort(pool, my_data)
```

**Why `main()` is the grant point:**
- Forces explicit threading — you cannot accidentally use work-stealing
- The capability appears in every function signature in the call chain, so code review catches it
- Matches the existing `Cap(a)` model for FFI (`Cap(LibC)`)
- No ambient authority — `Scheduler.work_pool()` would let any code silently opt in

### Work-Stealing Mechanics

Each worker thread in the pool maintains a **Chase-Lev deque** of ready tasks:

- **Push/pop** from the bottom (LIFO) — the owning thread
- **Steal** from the top (FIFO) — idle threads from other workers
- **Steal half** — when stealing, take half the victim's queue (Go/Tokio model)
- **Random victim selection** — idle worker picks a random other worker to steal from

Tasks on the stealing pool do **not** have reduction budgets. They run until they complete, block, or explicitly yield. This is the tradeoff: more throughput for CPU-bound work, but a runaway task can monopolize a worker thread.

### Actors Cannot Run on the Stealing Pool

Actors always run on the cooperative tier. Only `Task(a)` values can be scheduled on the work-stealing pool. This is enforced by the type system — `Task.spawn_steal` accepts a function, not an actor definition.

**Rationale:** Actors have mailboxes, state, and supervision trees that assume fair scheduling. Work-stealing's run-to-completion semantics would break actor fairness guarantees.

## Cross-Tier Communication

### Mailbox-Based Boundary (BEAM Model)

Communication between tiers uses the same mailbox mechanism as actor-to-actor messaging. A work-stealing task can send messages to cooperative actors, and vice versa:

```march
def main(pool: Cap(WorkPool)) do
  let (counter_id, counter_cap) = spawn(Counter)

  Task.spawn_steal(pool, fn () ->
    let result = expensive_computation()
    # Send from stealing pool → cooperative actor
    # The mailbox is just a concurrent queue
    send(counter_cap, Update(result))
  end)
end
```

**How it works:**
- Every actor's mailbox is a lock-free multi-producer/single-consumer queue
- Any thread (cooperative or stealing) can enqueue a message
- Only the owning cooperative scheduler thread dequeues
- No scheduler-awareness needed at the message layer

### Sendable Enforcement

The type checker verifies that closures passed to `Task.spawn_steal` only capture `Sendable` values. This prevents data races from shared mutable state across threads:

```march
# OK — Int is Sendable
let x = 42
Task.spawn_steal(pool, fn () -> x + 1 end)

# OK — linear value is transferred (ownership moves)
let buf = linear Buffer.new(1024)
Task.spawn_steal(pool, fn () -> Buffer.write(buf, "hello") end)
# buf is consumed here — cannot use after this point

# ERROR — Ref(Int) is not Sendable (mutable reference)
let r = Ref.new(0)
Task.spawn_steal(pool, fn () -> Ref.set(r, 1) end)
# ^^^ Type error: Ref(Int) is not Sendable
```

**Sendable rules:**
- All primitive types are Sendable
- Immutable compound types (tuples, records, variants) are Sendable if all fields are
- `Pid(a)` is Sendable (location-transparent by design)
- `Cap(a)` is Sendable only within the same node (node-local)
- `linear T` is Sendable (ownership transfer, no aliasing)
- `Ref(a)`, mutable arrays, and other mutable references are NOT Sendable

## Task Supervision

Tasks are supervised — they participate in the supervision tree like actors.

### Task Failure Modes

```march
# Task.await returns Result — caller handles failure
let task = Task.spawn(fn () -> might_fail() end)
match Task.await(task) do
  Ok(value)  -> use(value)
  Err(reason) -> handle_error(reason)
end

# Task.await! propagates failure — crashes the caller
let value = Task.await!(task)
```

### Linked Tasks

Tasks can be linked to their spawning actor or task. If a linked task crashes, the parent is notified:

```march
# Linked task — crash propagates to parent
let task = Task.spawn_link(fn () -> work() end)

# Linked work-stealing task
let task = Task.spawn_steal_link(pool, fn () -> work() end)
```

### Supervisor Integration

Tasks can be placed under a supervisor for automatic restart:

```march
actor TaskSupervisor do
  use Supervisor, strategy: :one_for_one

  children [
    worker(fn () -> periodic_cleanup() end, restart: :permanent),
    worker(fn () -> batch_job() end, restart: :transient),
  ]
end
```

**Supervision rules:**
- `:permanent` — always restart (long-running tasks)
- `:transient` — restart only on abnormal exit
- `:temporary` — never restart (fire-and-forget)
- Work-stealing tasks follow the same rules but run on the stealing pool

## Runtime Requirements

### Minimal Runtime Components

| Component | Purpose | Implementation |
|-----------|---------|----------------|
| Cooperative scheduler | Run queues, reduction counting, round-robin | OCaml 5 Domain per core, each with a run queue |
| Work-stealing pool | Chase-Lev deques, random victim selection | Separate Domain pool with lock-free deques |
| Mailbox queues | Actor message delivery | Lock-free MPSC queues (Michael-Scott or similar) |
| Timer wheel | `receive after`, timeouts, periodic tasks | Hierarchical timing wheel (shared across schedulers) |
| Supervisor registry | Track task/actor lifecycle, restart policies | Per-node registry with link tracking |

### OCaml 5 Domain Mapping

March's runtime maps onto OCaml 5's Domain system:

- **Cooperative scheduler**: One `Domain.t` per core. Each domain runs a scheduler loop that picks actors/tasks from its local run queue, runs them for up to 4K reductions, and yields.
- **Work-stealing pool**: Separate set of `Domain.t` instances. Each runs a work-stealing loop: pop from local deque, or steal from a random peer.
- **Cross-domain communication**: `Atomic` references and lock-free queues for mailboxes. No shared mutable state in user code (enforced by `Sendable`).

### Memory Model Interaction

The scheduler must respect March's per-actor arena heap model (see `specs/gc_design.md`):

- Each actor's arena stays pinned to one cooperative scheduler thread — no migration between cores (avoids false sharing and RC races)
- Work-stealing tasks allocate from a shared thread-local allocator (not actor arenas)
- Linear values transferred to tasks via `Sendable` are moved (no copy, no aliasing)
- FBIP optimizations are safe within a single task — the scheduler does not interrupt mid-rewrite

## API Summary

### Task Module

| Function | Tier | Returns | Requires |
|----------|------|---------|----------|
| `Task.spawn(fn)` | Cooperative | `Task(a)` | — |
| `Task.spawn_link(fn)` | Cooperative | `Task(a)` | — |
| `Task.spawn_steal(pool, fn)` | Work-stealing | `Task(a)` | `Cap(WorkPool)` |
| `Task.spawn_steal_link(pool, fn)` | Work-stealing | `Task(a)` | `Cap(WorkPool)` |
| `Task.await(task)` | Either | `Result(a, Error)` | — |
| `Task.await!(task)` | Either | `a` (crashes on error) | — |
| `Task.await_all(tasks)` | Either | `List(Result(a, Error))` | — |
| `Task.yield()` | Either | `Unit` | — |

### Scheduler Module

| Function | Purpose |
|----------|---------|
| `Scheduler.self()` | Returns the current scheduler's ID |
| `Scheduler.reduction_budget()` | Returns remaining reductions in current quantum |
| `Scheduler.core_count()` | Number of cooperative scheduler threads |
| `Scheduler.steal_pool_size()` | Number of work-stealing threads |

## Testing Plan

### Unit Tests (TDD — write these first)

Tests should be added to `test/test_march.ml` using Alcotest.

#### Phase 1: Reduction Counting

```
test "reduction counter decrements on function application"
  — Spawn a task calling a function N times
  — Verify it yields after 4000 reductions
  — Verify it resumes and completes

test "reduction counter decrements on pattern match"
  — Spawn a task with a deep match expression
  — Verify yield behavior

test "tight recursive loop eventually yields"
  — fib(35) must not starve other actors
  — Spawn fib(35) and a fast-responding actor
  — Verify the fast actor gets scheduled within reasonable time

test "blocked actor does not consume reductions"
  — Actor waiting on receive should not count against budget
  — Verify it moves to wait queue
```

#### Phase 2: Cooperative Task Scheduling

```
test "Task.spawn runs on cooperative scheduler"
  — Spawn multiple tasks, verify round-robin behavior

test "Task.await returns result"
  — Spawn task returning a value, await it

test "Task.await returns error on task crash"
  — Spawn task that raises, verify Err result

test "Task.await! crashes caller on task failure"
  — Verify crash propagation

test "multiple tasks interleave fairly"
  — Spawn 10 tasks each doing 10K reductions of work
  — Verify all complete (none starved)
```

#### Phase 3: Work-Stealing Pool

```
test "Task.spawn_steal requires Cap(WorkPool)"
  — Call without capability → type error

test "Task.spawn_steal runs to completion"
  — CPU-bound task completes without reduction preemption

test "work-stealing task can send to cooperative actor"
  — Spawn actor on cooperative tier
  — Spawn steal-task that sends message to actor
  — Verify actor receives message

test "steal-task closure must capture only Sendable values"
  — Capture a Ref in closure → type error
  — Capture an Int → OK
  — Capture a linear value → OK (ownership transfers)

test "idle stealing worker steals from peer"
  — Enqueue many tasks on one worker
  — Verify other workers pick up work

test "Cap(WorkPool) cannot be forged"
  — Attempt to construct Cap(WorkPool) manually → type error
  — Only obtainable from main() parameter
```

#### Phase 4: Task Supervision

```
test "Task.spawn_link propagates crash to parent"
  — Linked task crashes → parent receives exit signal

test "supervised task restarts on failure (permanent)"
  — Task under supervisor crashes → restarts

test "supervised task does not restart (temporary)"
  — Temporary task crashes → stays dead

test "transient task restarts only on abnormal exit"
  — Normal exit → no restart
  — Crash → restart
```

#### Phase 5: Integration

```
test "mixed cooperative and stealing tasks complete"
  — Spawn actors + cooperative tasks + stealing tasks
  — All communicate via messages
  — All complete correctly

test "stealing pool does not starve cooperative scheduler"
  — Saturate stealing pool with CPU-bound work
  — Verify cooperative actors still respond promptly

test "linear value transfer to steal-task is safe"
  — Create linear buffer, transfer to steal-task
  — Verify original binding is consumed
  — Verify task can use the buffer
```

### Benchmarks

Add to `bench/` alongside existing benchmarks. Each benchmark should have a `.ll` description file and a `.march` implementation.

#### `bench/scheduler_fairness.march`

Measures scheduling fairness under contention:
- Spawn N actors each responding to M messages
- Measure max/min/mean response latency per actor
- Verify no actor is starved (max latency < 10x mean)
- Run with N = 100, 1000, 10000

#### `bench/work_stealing.march`

Measures work-stealing throughput and load balancing:
- Parallel map over a large list using `spawn_steal`
- Compare: sequential vs cooperative-parallel vs work-stealing
- Measure wall-clock time, CPU utilization, steal count
- Exercise: `parallel_sort`, `parallel_map`, `matrix_multiply`

#### `bench/cross_tier.march`

Measures cross-tier communication overhead:
- Work-stealing task sends N messages to cooperative actor
- Measure message delivery latency (enqueue-to-dequeue)
- Compare with actor-to-actor messaging latency
- Verify < 2x overhead for cross-tier vs same-tier

#### `bench/supervisor_recovery.march`

Measures supervision overhead:
- Spawn N tasks under supervisor, crash M% of them
- Measure restart latency and throughput impact
- Verify supervision overhead < 5% of total runtime

### Benchmark Mapping Update

Add to `specs/benchmarks.md`:

| Change domain | Benchmark to run |
|---------------|-----------------|
| Reduction counting / yield points | `bench/scheduler_fairness.march` |
| Work-stealing pool / Cap(WorkPool) | `bench/work_stealing.march` |
| Cross-tier messaging | `bench/cross_tier.march` |
| Task supervision | `bench/supervisor_recovery.march` |
| Closure/HOF changes | `bench/list_ops.march` (existing) |
| Perceus/FBIP changes | `bench/tree_transform.march` (existing) |

## Open Questions

1. **Work-stealing pool size** — Should it match core count, or be configurable? BEAM uses core count for CPU-dirty schedulers and 10 for IO-dirty. March likely wants core count for the stealing pool since it's CPU-focused.

2. **Task cancellation** — Should `Task.cancel(task)` be supported? If so, cancellation needs a cooperative check (the task checks a flag at yield points). Deferred to implementation.

3. **Nested work-stealing** — Can a steal-task spawn more steal-tasks? Probably yes (it has the `Cap(WorkPool)` if passed in), but this risks pool exhaustion. May need a depth limit or separate pool.

4. **Actor migration** — Can actors move between cooperative scheduler threads? BEAM does this for load balancing. March's per-actor arena model makes migration expensive (must move the arena). Deferred.

5. **Async/await sugar** — Should `Task.await` be implicit via `async`/`await` keywords? The explicit `.await` is fine for v1 but sugar may improve ergonomics later.

## Prior Art

| System | Relevant mechanism | What March borrows |
|--------|-------------------|-------------------|
| BEAM/Erlang | Reduction counting, dirty schedulers, per-process heaps | Reduction model, two-pool architecture, mailbox boundary |
| Go | Chase-Lev deques, function prologue yield checks | Work-stealing deque design, compiler-inserted yields |
| Tokio/Rust | `spawn_blocking`, `Send + 'static` | Separate pool for blocking/CPU work, `Sendable` enforcement |
| Pony | Deny capabilities, per-actor GC | Type-system-controlled scheduling, no shared mutable state |
| Java Loom | ForkJoinPool work-stealing | Proven deque implementation, steal-half semantics |
