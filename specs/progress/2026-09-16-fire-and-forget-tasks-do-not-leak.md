# Fire-and-forget tasks do not leak — `task_yield()` does not drain the queue

Closes `specs/todos/2026-09-13-fire-and-forget-tasks-retain-objects.md`, filed
2026-09-13 while fixing the Float task result box. It reported `live_allocs`
growing by 3,540 / 4,452 / 3,595 over 5,000 fire-and-forget spawns and named
the open question: a leak, or tasks not yet run?

**Tasks not yet run.** Measured 2026-09-16 at `0a4275849`, `--compile --opt 2`,
Darwin arm64, 5,000 spawns:

| method | grew |
|---|---|
| capture-free thunk + 2,000 `task_yield()` (the todo's method) | 3,115 / 3,700 / 3,297 |
| the same run, continued with `run_until_idle()` | 4 |
| capture-free thunk + `run_until_idle()` | 1 |
| thunk capturing a fresh heap `String` + `run_until_idle()` | 2 |
| thunk capturing one shared heap `String` + `run_until_idle()` | 2 |

The first row reproduces the original numbers, run-to-run variance included.
The second is that same run continued: the pending work drains and the count
collapses to 4.

The todo's reason for doubting "not yet run" — *"a hundredfold more yields did
not reduce it, which argues against 'not yet run' but does not rule it out,
because `task_yield` may not drain other schedulers' queues"* — was the right
observation and the wrong inference, and its own caveat was the answer.
`task_yield()` yields the current green thread; it does not run the pending
queue to completion, so more of them do not help. `run_until_idle()` does.

Completion was proved rather than assumed: a variant whose thunks each
`println` a line emitted all 10,100 expected lines while reporting `grew=0`
over the spawn window.

Nothing was changed in the compiler or runtime. What this closes is an
apparatus trap, and it is worth stating on its own:

> A `live_allocs()` delta sampled after `task_yield()` alone measures the
> scheduler's queue depth, not retention. Drain with `run_until_idle()` — and
> prove completion with an observable side effect — before reading a task
> probe's number as a leak.

Ownership of the three things the todo listed to check (the thunk's closure,
the `malloc`'d `march_thunk_arg`, the Task's two references) was therefore not
investigated: there is no discrepancy left to explain. A capture-free thunk is
flat, and a capturing one retains 2 objects over 5,000 spawns, which is noise
at that scale rather than a per-spawn cost.

Full current picture of the remaining RC work:
`specs/2026-09-16-remaining-rc-leaks-design.md`.
