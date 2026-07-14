# March Scheduler

**Last Updated:** 2026-04-15
**Status:** Implemented — C runtime scheduler with signal-based preemption and
cancellation tokens; interpreter layer wired via `task_*` builtins and
`VCancelToken` value type; `Task` stdlib module complete.

**Key files:**
- `runtime/march_scheduler.{h,c}` — M:N green-thread scheduler, preemption daemon, cancel tokens
- `lib/eval/eval.ml` — interpreter task builtins (`task_spawn`, `task_await`, `VCancelToken`, …)
- `stdlib/task.march` — `Task.async/await/race/any/all_settled/scope`
- `test/stdlib/test_task.march` — 24 task tests

---

## Overview

The March scheduler implements a two-tier concurrency model:

1. **Cooperative scheduling with signal-based preemption** — each green thread
   gets a budget of `MARCH_SCHED_REDUCTIONS` (4 000) reductions per quantum.
   A daemon OS thread sends `SIGUSR1` every `MARCH_QUANTUM_US` (1 000 µs) to
   each worker thread, zeroing `march_tls_reductions` and forcing a yield at
   the next reduction check — preventing any single green thread from starving
   the scheduler indefinitely.
2. **M:N work-stealing thread pool** — 4 OS threads by default, each with a
   local deque; idle threads steal from peers (Chase-Lev).

This matches the Erlang/BEAM model at the cooperative level while exploiting
multi-core hardware via the work pool.

---

## 1. Reduction counting

```c
extern volatile _Thread_local int64_t march_tls_reductions;
#define MARCH_SCHED_REDUCTIONS 4000
```

`march_tls_reductions` is decremented at every reduction point (function call,
match arm, message send). When it reaches zero the current green thread
cooperatively yields back to the scheduler.

---

## 2. Signal-based preemption

```c
#define MARCH_QUANTUM_US 1000   /* 1 ms */
```

`march_sched_preempt_start()` spawns a daemon OS thread that loops:

```c
nanosleep(1 ms);
for each scheduler OS thread:
    pthread_kill(thread, SIGUSR1);
```

The `SIGUSR1` handler zeroes `march_tls_reductions`:

```c
static void march_preempt_signal_handler(int sig) {
    march_tls_reductions = 0;
}
```

This ensures long-running native computations (C FFI, tight loops without
reductions) cannot hold the CPU indefinitely. `march_sched_preempt_stop()`
joins the daemon thread on scheduler shutdown.

---

## 3. Cancellation tokens

```c
typedef struct march_cancel_token {
    _Atomic int   cancelled;
    _Atomic int   refcount;
} march_cancel_token;
```

API:

| Function | Description |
|---|---|
| `march_cancel_token_new()` | Allocate a new uncancelled token (refcount=1) |
| `march_cancel_token_cancel(tok)` | Atomically set `cancelled = 1` |
| `march_cancel_token_is_cancelled(tok)` | Return `cancelled` |
| `march_cancel_token_ref(tok)` | Increment refcount |
| `march_cancel_token_unref(tok)` | Decrement refcount; free when zero |
| `march_sched_spawn_with_cancel(fn, arg, tok)` | Spawn; skip `fn` if token already cancelled |

`march_sched_spawn_with_cancel` uses a `cancel_trampoline` wrapper: the wrapper
checks the token before calling the user function, so a pre-cancelled token
causes the task to complete immediately with an `Err("cancelled")` result.

---

## 4. Interpreter layer (`lib/eval/eval.ml`)

The tree-walking interpreter models tasks as entries in a global `task_table`:

```ocaml
type task_entry = {
  te_id       : int;
  te_result   : value option ref;
  te_cancelled: bool ref;
}
```

Tasks execute **eagerly at spawn time** (single-threaded cooperative scheduler
— no actual parallelism in the interpreter). `task_await` checks `te_cancelled`
before returning the result.

### Task builtins

| Builtin | Signature | Description |
|---|---|---|
| `task_spawn` | `(Int → a) → Task(a)` | Spawn (runs eagerly) |
| `task_await` | `Task(a) → Result(a, String)` | Await result |
| `task_await_unwrap` | `Task(a) → a` | Await, panic on Err |
| `task_cancel_token_new` | `CancelToken` | New uncancelled token |
| `task_cancel` | `CancelToken → Unit` | Set token cancelled |
| `task_is_cancelled` | `CancelToken → Bool` | Check token |
| `task_spawn_with_cancel` | `(Int → a) → CancelToken → Task(a)` | Spawn; skip if pre-cancelled |
| `task_cancel_by_id` | `Task(a) → Unit` | Cancel a task by handle |

`task_cancel_token_new` is a zero-arg builtin — declared as `Mono (TCon ("CancelToken", [])))`
in the typecheck environment (not `TArrow (t_unit, ...)`) because `infer_app`
returns the type as-is for zero-arg calls.

---

## 5. `Task` stdlib module (`stdlib/task.march`)

Built on the builtins above, the stdlib provides a clean API:

### Basic

```march
let t = Task.async(fn () -> work())     -- spawn
Task.await(t)                           -- Ok(v) or Err(reason)
Task.await_unwrap(t)                    -- v, panic on Err
Task.await_many([t1, t2])              -- [Ok(v1), Ok(v2)]
Task.async_stream(xs, fn x -> f(x))    -- parallel map
```

### Structured combinators

| Function | Behaviour |
|---|---|
| `Task.race(tasks)` | First result wins (Ok or Err); losers get `task_cancel_by_id` |
| `Task.any(tasks)` | First Ok wins; all-Err → `Err(reasons_list)` |
| `Task.all_settled(tasks)` | Collect all; never short-circuits |
| `Task.scope(f)` | Call `f()`; Phase 2+ will cancel leaked tasks on exit |

### Cancellation token flow

```march
let tok = task_cancel_token_new()
let t   = task_spawn_with_cancel(fn _ -> heavy(), tok)
-- ... later ...
task_cancel(tok)
Task.await(t)    -- Err("cancelled")
```

---

## 6. Known limitations (Phase 1 interpreter)

- **No actual parallelism** — tasks run eagerly and synchronously at spawn
  time; `Task.race` returns the first task in list order deterministically.
- **`Task.scope` is a pass-through** — task cancellation on scope exit requires
  the multi-core runtime (Phase 2+) to inject a shared cancel token into the
  dynamic binding so `Task.async` picks it up automatically.
- **`await_ms` timeout not enforced** — `Task.await_ms(t, timeout_ms)` accepts
  the timeout for API compatibility but ignores it; enforcement requires Phase 2+.
