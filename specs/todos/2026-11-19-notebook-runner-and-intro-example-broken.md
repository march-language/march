# `forge notebook` cannot run `examples/intro_notebook.mnb` (2026-11-19)

Found while migrating the notebook's `print` cells to `println` (ocap phase 4
PR B final review, Minor 10). `forge/tasks/notebook.march` wraps every cell in
`mod NotebookRunner do fn main() do ... end end`:

- the generated module declares no `needs`, so any cell that prints is rejected
  (`cap_needs`: `main` is granted nothing);
- cells that define functions (`fn square(n) do ... end`) land inside `main`'s
  body, so they are local functions, not declarations later cells can share by
  name across a module boundary (worth checking once the rest typechecks);
- the example's `List.fold_left(0, nums, ...)` cells pass arguments in the wrong
  order for today's `List.fold_left` and fail to typecheck.

What to do: have the runner emit `needs IO.Console` (or the union the cells
need), fix the example, and add a test that
runs the example notebook.
