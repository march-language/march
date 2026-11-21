`[P2]` Compiled, `task_await` on a task spawned with an already-cancelled token hangs forever

Found 2026-11-19 while fixing
`specs/progress/2026-11-11-compiled-task-is-cancelled-true-before-cancel.md`.

```march
mod Main do
  needs IO.Console
  needs IO.Spawn
  fn main(_c : Cap(IO.Console), _s : Cap(IO.Spawn)) do
    let tok = task_cancel_token_new()
    task_cancel(tok)
    let t = task_spawn_with_cancel(fn _ -> 7, tok)
    println(to_string(task_await(t)))
  end
end
```

- Interpreted: `Err(cancelled)` (and `test/stdlib/test_task.march` pins this, interpreted only).
- `--compile`: hangs in `task_await`.

Cause: `march_task_spawn_with_cancel_thunk` (`runtime/march_runtime.c`) spawns
`march_thunk_trampoline` through `march_sched_spawn_with_cancel`, whose `cancel_trampoline`
(`runtime/march_scheduler.c`) returns without calling `user_fn` when the token is cancelled. So
`march_thunk_trampoline` never runs: the Task's done word (task[4]) is never set, no waiter is
woken, the trampoline's own reference to the Task is never released, and the closure and the
`march_thunk_arg` wrapper leak.

Likely fix: make the skip Task-aware. Either carry the token in `march_thunk_arg` and have
`march_thunk_trampoline` treat a cancelled token like its cancellation landing (store
`MARCH_TASK_CANCELLED` in task[3], skip `apply`, release the closure, then run the normal
completion path), or check the token in the runtime before choosing the trampoline. Keep the
`Err("cancelled")` text the interpreter returns (the compiled cancellation sentinel currently
reads as `Err("task cancelled")`; check which string each path prints before pinning a test).
