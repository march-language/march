# `forge new` scaffolded a project that failed its own first `forge build`

**Status:** Landed (2026-08-13). Task 2 of the capability-UX plan
(`specs/2026-08-13-capability-ux-plan.md`).

## The bug

`forge new x && cd x && forge build` exited 1 with two capability errors.
The `app` and `tool` templates in `forge/lib/scaffold.ml` emitted
`fn main() do println(...) end` — no `needs IO.Console` declaration and no
`Cap(IO.Console)` grant parameter on `main`. Since `println` requires
`Cap(IO.Console)`, typecheck rejected the freshly generated `main` with the
same missing-`needs` and missing-grant diagnostics `forge fix` (Task 1) now
knows how to repair, but a brand-new project shouldn't need `forge fix` run
against it before it even builds once. The generated test module
(`test_source`) had the identical problem.

The first command a new March user runs — `forge new` immediately followed
by `forge build` — failed on capabilities before they had written a line of
their own code.

## The fix

`forge/lib/scaffold.ml`:
- `lib_source`'s `App` and `Tool` arms now emit `needs IO.Console` in the
  module body and give `main` a `_cap : Cap(IO.Console)` grant parameter.
  The `Lib` arm is untouched — it stays pure, no `needs`, no `main`.
- `test_source` gets the same treatment: `needs IO.Console` plus a
  `_cap : Cap(IO.Console)` parameter on its `main`.
- The grant parameter is named `_cap`, not `cap`, so the unused-variable
  lint doesn't fire on generated code that never reads the capability value
  (capabilities are module-scoped; the parameter exists only to satisfy the
  grant, never to be read).

No change to capability-checking semantics — this only fixes the templates
`forge new` writes to disk.

## Test

`forge/test/test_cap_sandbox.ml`: `test_scaffolded_app_builds_clean` runs
`forge new`, `forge check`, `forge build`, and `forge test` end-to-end
against a freshly scaffolded temp-dir project and asserts each exits 0.
Written first and confirmed red (`forge check` exited 1) before the
scaffold.ml fix, then confirmed green after.

## Verification

```
dune build --root . bin/main.exe forge/bin/main.exe forge/test/test_cap_sandbox.exe
./_build/default/forge/test/test_cap_sandbox.exe -e
```

12 tests run, all green, including the new one.

Manual walkthrough (`forge new scaffold_check && forge build && forge run`)
printed `Hello from scaffold_check!` and exited 0.
