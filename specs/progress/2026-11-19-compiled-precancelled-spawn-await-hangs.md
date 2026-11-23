`[P2]` Compiled, `task_await` on a task spawned with an already-cancelled token hangs forever (DONE)

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

## Root cause

As above. `cancel_trampoline` (`runtime/march_scheduler.c:5374`) returned without calling its
`user_fn` on a cancelled token, and for a task that `user_fn` is `march_thunk_trampoline`, the
only code that completes the Task. A token cancelled after the spawn but before the task first
ran hit the same skip (the check runs when the proc is first dispatched).

The two backends also disagreed on the text: the interpreter's `task_await`/`task_poll`
answer `Err("cancelled")` for a cancelled task (`lib/eval/eval.ml`), which
`stdlib/task.march` documents; the compiled `task_result_ok` answered `Err("task cancelled")`.

## Fix

- `runtime/march_runtime.c`: `march_thunk_arg` carries the token (one reference, taken by
  `march_task_spawn_with_cancel_thunk`, which now spawns `march_thunk_trampoline` with plain
  `march_sched_spawn`). `march_thunk_trampoline` checks the token once before applying the
  closure and releases its reference; a cancelled token skips `apply`, releases the closure
  with `march_clo_release` (plain `march_decrc` freed the cell and leaked its captures: the
  first attempt showed 2 live objects per task, the captured string and the inner closure),
  stores `MARCH_TASK_CANCELLED`, and runs the normal completion path (done flag, waiter wake,
  the trampoline's Task hold). `g_tasks_cancelled` still counts drain-deadline unwinds only.
- `task_result_ok` answers `Err("cancelled")`, as the interpreter does. This applies to every
  cancelled task (`task_cancel_by_id`, a drain deadline), not only the pre-cancelled one. The
  unwrap panic text (`task cancelled`) is unchanged.
- `march_sched_spawn_with_cancel`/`cancel_trampoline` are left in place but have no caller now.

Verified with `--rc-trace` + `MARCH_TRACE_GC=1` + `scripts/gc-trace-report.py`: no Task, token,
closure or capture live at exit (the one live object is `main`'s returned `println` result,
which a bare `println("x")` program also shows).

Regression tests, `cancel_token_codegen` in `test/test_codegen.ml`:
- `pre-cancelled spawn: await completes, interp = compiled`: pre-cancelled capture-free and
  capturing tasks (`task_await` twice, `task_poll`), plus a token cancelled right after the
  spawn (Ok(5) or Err("cancelled"), racing the task's start compiled; Ok interpreted). Red
  before the fix: the binary hung until the test's 30 s alarm.
- `pre-cancelled spawn releases its closure (gauge)`: 2000 pre-cancelled tasks with a
  capturing closure must leave `march_live_allocs` flat (slack 50). Red before: hung; with
  the `march_decrc` first attempt: `GREW 4001`.

`test/stdlib/test_task.march` stays interpreter-only (its dune rule runs `march test`). Its
two pre-cancelled cases now pass compiled (`--compile --test`), but 7 other cases in the file
fail compiled for a different reason, filed as
`specs/todos/2026-11-22-compiled-task-cancel-by-id-races-task-start.md`.
