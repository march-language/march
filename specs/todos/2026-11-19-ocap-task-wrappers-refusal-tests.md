# No refusal test for `Task.async_steal` / `Task.async_cancellable` (2026-11-19)

Found by the ocap phase 4 Task 8 review (Minor 8). The two wrappers Task 8 added
(`stdlib/task.march`) check `IO.Spawn`, but no test exercises their refusal
(`Err(CapError(...))`). Separately, `test/test_cap_ceiling.ml`'s "route 3" now
pins the typecheck gate rather than the compiled ceiling (the TIR function-value
route is tracked in `specs/todos/2026-11-17-ocap-tir-ceiling-misses-function-values.md`).

What to do: one `test/cap_conformance` fixture each (a launch granting no
`IO.Spawn`, the call's `Err` printed via `Authority.describe`), skipped on the JS
target, which has no tasks.
