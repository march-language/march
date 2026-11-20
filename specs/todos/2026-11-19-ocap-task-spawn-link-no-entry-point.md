# `task_spawn_link` has no checked entry point (2026-11-19)

Found by the ocap phase 4 Task 8 review (Minor 3). `task_spawn_link` is
stdlib-only since Task 8, and its `Cap_ops` row names `Task.async`, which links
nothing (`Cap_ops.rename_differs` says so, and the `stdlib_internal` hint now
carries that reason). User code has no way left to spawn a linked task. The
builtin is interpreter-only (the compiled task runtime has no task/actor link,
`lib/tir/lower_expr.ml`), which limits the impact.

What to do: add `Task.async_link(f)` checking `IO.Spawn` like `Task.async_steal`
and `Task.async_cancellable`, point the row at it and drop its `rename_differs`
entry; or, if linking is not wanted, say in the row's hint that there is no
replacement.
