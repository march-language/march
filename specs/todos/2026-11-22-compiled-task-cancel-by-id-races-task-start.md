`[P3]` Compiled, `task_cancel_by_id` on a task that has not started yet is a no-op

Found 2026-11-22 while fixing
`specs/progress/2026-11-19-compiled-precancelled-spawn-await-hangs.md`.

`test/stdlib/test_task.march` passes interpreted (its only runner, the dune rule), but built with
`march --compile --test` 7 of its 24 cases fail: "cancelling a completed task makes await return
Err", the `Task.race` loser cases, the `Task.any` cases and `all_settled`. Each spawns tasks and
calls `task_cancel_by_id` on one right away, expecting `Err("cancelled")`, and gets `Ok(v)`.

The interpreter runs a task to completion at spawn, so a later `task_cancel_by_id` always finds
it finished and marks it cancelled. Compiled, `march_task_cancel_by_id` (`runtime/march_runtime.c`)
returns without doing anything while `task[2]` (the pid the trampoline records when it first
runs) is still 0, so a task cancelled before it was dispatched runs and completes normally.

Decide the intended semantics (cancel-before-start should at least make the task complete as
cancelled, as a pre-cancelled token now does), then make the file pass compiled and run it
compiled in CI.
