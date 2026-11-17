# ocap: doctests run with the full authority, so a library's scoped `needs` is not enforced

Logged 2026-11-17 by ocap phase 4, Task 3 review (specs/plans/2026-11-15-ocap-p4-runtime-plan.md).

`march test` runs every documented function's `march>` doctests in the interpreter after the
file's tests (`Eval.run_doctests`, lib/eval/eval.ml). Doctests belong to every documented
function in the merged module, the stdlib's included, not to the test file, so they launch
as the REPL does: `("IO", false)`, the full authority, narrowed only by `MARCH_GRANT` /
`--grant`. Under the test file's own request 83 stdlib doctests failed (they need `Vault`,
`Env`, `Task`).

The cost: a library module whose `needs` line or `main` is scoped has its doctests run
unscoped, so a doctest that reaches outside the library's own request passes.

What to do: launch each documented function's doctests under the request of the module that
declares it (its `needs` line), not one launch for all of them; stdlib modules then get their
own lines, which is what their doctests need.
