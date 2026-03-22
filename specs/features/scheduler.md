# March Scheduler

**Last Updated:** March 22, 2026
**Status:** Implemented (OCaml structs). Not yet wired to the actor evaluator or compiled path.

**Implementation:**
- `lib/scheduler/scheduler.ml` (72 lines) — cooperative scheduler, reduction-counted preemption
- `lib/scheduler/mailbox.ml` (48 lines) — bounded FIFO actor mailbox
- `lib/scheduler/task.ml` (28 lines) — `Task(a)` abstraction for structured parallel compute
- `lib/scheduler/work_pool.ml` (109 lines) — work-stealing thread pool

---

## Overview

The March scheduler implements a **two-tier concurrency model**:

1. **Cooperative scheduling** — each actor/task gets a budget of `max_reductions` reductions per quantum. Reduction-counted preemption prevents any single actor from starving others.
2. **Work-stealing thread pool** — parallelism across OS threads via a deque-based work-stealing algorithm.

This matches the Erlang/BEAM model at the cooperative level while exploiting multi-core hardware via the work pool.

---

## 1. Cooperative Scheduler (`lib/scheduler/scheduler.ml`)

### Reduction Budget

```ocaml
let max_reductions = 4_000

type reduction_ctx = {
  mutable remaining : int;
  mutable yielded   : bool;
}
```

One "reduction" ≈ one function application, pattern match arm, or message send. After `max_reductions` reductions, the scheduler yields and moves to the next process in the run queue.

This is intentionally tuned to match BEAM's default reduction budget, giving similar fairness characteristics.

### Run Queue

```ocaml
type proc_id = int

(* Processes are stored in a run queue (deque) *)
(* Round-robin scheduling: pop front, run quantum, push back *)
```

Processes are round-robined: dequeued, given their reduction budget, then re-enqueued if they haven't terminated or blocked on a message receive.

### Preemption Points

The `tick ctx` function is called at every reduction point. It decrements `remaining`; when it hits 0, `yielded` is set to true and the evaluator checks this flag to yield cooperatively.

---

## 2. Mailbox (`lib/scheduler/mailbox.ml`)

```ocaml
type 'a mailbox = {
  buf      : 'a Queue.t;
  capacity : int;
  mutex    : Mutex.t;
  not_empty: Condition.t;
  not_full : Condition.t;
}
```

Bounded FIFO queue with condition variables. Supports:
- `send` — enqueue a message; blocks if full (backpressure)
- `recv` — dequeue a message; blocks if empty (waiting)
- `try_recv` — non-blocking receive; returns `None` if empty

---

## 3. Task (`lib/scheduler/task.ml`)

```ocaml
type 'a task_state =
  | Pending
  | Running
  | Done of 'a
  | Failed of exn
```

`Task(a)` represents a structured parallel computation. Tasks are spawned into the work pool, run to completion, and the result is retrieved via `task_await`. Structured concurrency: a scope cannot exit until all tasks spawned within it complete or fail.

---

## 4. Work-Stealing Pool (`lib/scheduler/work_pool.ml`)

A fixed-size pool of OS threads, each with a local deque. Work items are pushed to the local deque; idle threads steal from the back of peer deques (Chase-Lev work-stealing).

```ocaml
type work_pool = {
  threads  : Thread.t array;
  deques   : work_item Deque.t array;  (* one per thread *)
  global_q : work_item Queue.t;        (* overflow queue *)
  shutdown : bool Atomic.t;
}
```

### Scheduling policy

1. Check own deque (LIFO for locality)
2. Steal from a random peer (FIFO from the other end)
3. Check global queue (overflow)
4. Block until work arrives

---

## 5. Integration Status

The scheduler is implemented as standalone OCaml modules but is **not yet integrated** into the main evaluator (`eval.ml`). The current actor system uses a simpler synchronous dispatch model (messages are processed inline at `send` time).

To integrate:
- Replace `eval_actor_msg` direct dispatch with a mailbox enqueue
- Wire `reduction_ctx` into the evaluator's main eval loop
- Use `work_pool` for `task_spawn` / `task_await` implementations
- Surface `Task(a)` as a proper value type in the type checker

---

## 6. Known Limitations

- **Not connected to eval.ml** — actors in the tree-walking interpreter run synchronously; this scheduler is ahead-of-integration
- **No preemption in compiled path** — LLVM-compiled code has no reduction counting yet
- **Mailbox capacity** — hardcoded bound; no per-actor configuration
- **Work pool shutdown** — `shutdown` flag is an `Atomic.t` but the shutdown sequence may not drain all pending work
