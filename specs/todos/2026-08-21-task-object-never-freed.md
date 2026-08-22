# Task objects are never freed: 2 heap objects leak per spawn+await, any result type

Filed 2026-08-21, found while probing the Float task_await sites
(`specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md`).

## Measured (Darwin arm64, `--compile --opt 2`, live_allocs delta)

```march
pfn spawn_await_int(n : Int, acc : Int) : Int do
  if n <= 0 do acc
  else
    let t = task_spawn(fn _ -> 2)
    spawn_await_int(n - 1, acc + task_await_unwrap(t))
  end
end
```

| | delta |
|---|---|
| plain arithmetic loop, 10k iterations (control) | 1 |
| spawn+await loop, 10k iterations, **Int** result | **20,000** |
| spawn+await loop, 100k iterations, Float result | 300,001 (2/iter + the Float box, see the 08-12 item) |

Exactly **two objects per spawn+await, independent of result type** — this is
NOT the Float-boxing leak (the Int leg has no boxes) and is 2× bigger than
it. Any loop that awaits tasks — a job queue, a supervisor, a
request-per-task server — leaks without bound.

## Where the references go

`march_task_spawn_thunk` (runtime/march_runtime.c): allocates the 48-byte
Task via `march_alloc` (RC=1, the caller's handle) and takes an extra
`march_incrc` for the trampoline. The trampoline drops its hold on exit
(`march_decrc(task)` after publishing the result), so the task ends life with
RC=1: the March-side handle `t`. **Nothing ever decs that reference** —
Perceus treats `t` as consumed by `task_await_unwrap`
(builtin arg conventions), but the emitted builtin call does not release it,
and no other holder exists after the await returns. The second leaked object
per iteration is the spawned thunk closure (`fn _ -> 2` under the REPL is
static, but the compiled capture-free spawn path still allocates the
`march_thunk_arg`-adjacent object — identify precisely when fixing; the
count says two, the task is provably one of them).

## Interaction with the Float task_await sites

The open Float unbox sites in the 08-12 item cannot be fixed by a
task-lifetime release **until this is fixed**: the natural owner of the
result box smuggled through `task[3]` is the Task object (double-await is
legal and works today — measured: two `task_await_unwrap` on one task both
return the value), so "release task[3]'s Float box when the Task dies" is
the sound design — but tasks never die. Fix this first, then the Float box
follows for free (a tag-guarded release of `task[3]` in the task's free
path, like #313's `fold_release_prev_acc`).

## Verification bar

live_allocs probe in the spawn_await_int shape above, RED (2/iter) →
GREEN (small constant); double-await witness stays correct; actor/task
suites + the vault concurrency Slow test.
