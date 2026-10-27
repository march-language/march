# Stdlib walks that never terminated on a bad step or size (termination design D5)

The termination design's COUNT sweep (`specs/2026-10-26-termination-checking-design.md`
§0.4, on the `claude/termination-design` branch) found four stdlib functions that
diverge on a bad argument, probes s1-s4. Decision D5 (settled 2026-10-27): each gets
a refinement precondition plus a runtime guard, or, where the arithmetic can be made
total, a fix. One commit per function.

Shared test pieces:

- `test/native/stdlib_step_guards.march` (+ `.expected`): one golden run both compiled
  and interpreted (`test/dune`), so the guard's panic text and Duration's output are
  pinned on both backends. Bad values reach the guard through `hidden_int(…)`
  (`string_to_int`), which the refinement checker cannot see through; a literal bad
  value is a compile-time refinement error now.
- `test/test_refinecheck.ml`, group `stdlib-step-guards`: runs the real driver
  (`--check --refine-report`, real stdlib prepended) on a good literal call
  (pinned as `1 proved, 0 violated, 0 skipped` in the user-code ledger, not merely
  silent) and a bad literal call (exit 1, one violation, the precondition named).
  Each case went RED with the precondition reverted in the staged stdlib.

## s1. `List.range_step(5, 0, 0)` looped

**Cause.** `range_step_go` (`stdlib/list.march`) stops when `i >= stop` (positive
step) or `i <= stop` (otherwise). A zero step takes the second branch; with
`start > stop` the test is false and `next = i + 0` recurses on the same `i`,
consing forever (TRMC makes it a loop, so it hangs rather than overflows). With
`start <= stop` it returned `[]`, which the doc stated.

**Fix.** `step : {Int | _ != 0}` and `if step == 0 do panic("List.range_step: step
must be non-zero")` in `range_step` (not in `range_step_go`, so the TRMC'd walk is
unchanged). Convention: List returns plain lists and panics on a bad argument
(`head`, `nth`, ...), and `Range.new_step` already panics on a zero step with the
same precondition, so a panic, not an `Option`/`Result`. Behaviour change: a zero
step with `start <= stop` now panics instead of returning `[]`.

**Tests.** `test/stdlib/test_list.march`: good paths unchanged; a zero step (passed
through `opaque_int`) gives `Err("panic: List.range_step: step must be non-zero")`
from `__try_call_val`. RED: the new test hung and was killed at 20 s. The
`stdlib-step-guards` refinecheck pair; the native golden's `s1` lines.

**TIR snapshots.** The five snapshot programs whose TIR includes `List`
(`trmc_modulo_cons`, `trmc_computed_arg_nested`, `nested_cons_ctor_heap`,
`tuple_param_borrowed_destruct`, `record_field_tail_projection`) were regenerated in
`test/snapshots/{lower,perceus}`: the guard in `List.range_step`, fresh-name
renumbering after it, and `__panic_site` line numbers shifted by 4. `range_step_go`
is unchanged. `metrics/trmc_modulo_cons`: perceus `dec` 53 -> 55, the two `dec_rc`
of the guard's Bool temporary, one per arm.
