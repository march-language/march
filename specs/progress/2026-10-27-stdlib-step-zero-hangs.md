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

## s2. `Range.to_list({start: 5, stop: 0, step: 0})` looped

**Cause.** `Range.new_step` checks `step != 0`, but a range is a plain record, so a
literal (or any computed record) bypasses it. `to_list`'s `go` takes the `else`
branch for a zero step, `i <= r.stop` is false when `start > stop`, and
`go(i + 0, Cons(i, acc))` loops, growing `acc`. `Range.each` has its own copy of
the walk and the same hang. `map`, `filter`, `reduce`, `reverse`, `all`, `any` and
`sum` reach it through `to_list`.

**Fix.**
- A named record type, `type IntRange = { start : Int, stop : Int, step : Int }`, so
  a refinement can read `step`. The precondition `{v : {start: Int, ...} | v.step != 0}`
  on an anonymous record type raised no obligation at all (probed: 0 obligations), so
  the name is needed. Records are structural, so every existing literal and
  annotation still fits. The name avoids `Rng`: `Random.Rng` is a different record,
  and reusing a type name gives `sort-conflict` skips (probed).
- `to_list`, `each`, and the seven functions that go through `to_list` take
  `r : {v : IntRange | v.step != 0}`, so their internal `to_list(r)` calls prove
  rather than adding stdlib skips, and a literal bad range is caught at whichever
  entry point the caller uses.
- `to_list` and `each` panic on a zero step (`Range.to_list: step must be non-zero`,
  `Range.each: step must be non-zero`), matching `Range.new_step`'s convention.
- `new` and `new_step` return `{v : IntRange | v.step != 0}`. `new_step`'s guard became
  a `let _ = if step == 0 do panic(…) else () end` statement before the literal: with
  the old `if … do panic(…) else {…} end` the return contract was an
  `unreflectable-subject` skip (probed), so `to_list(new_step(…))` could not prove.
  Runtime behaviour is unchanged.
- Not changed: `size`, `contains`, `is_empty`, `first` and `last` divide by the step;
  on a zero step they fail with a division by zero rather than hang, so they are out
  of D5's scope and keep their plain record type.

Behaviour change: a zero-step range with `start <= stop` used to give `[]` from
`to_list` (and do nothing in `each`); it now panics.

**Tests.** `test/stdlib/test_range.march` (new, registered in
`test/test_stdlib_march.ml`, with `range.march` added to its load list): good paths
for `to_list` and every function built on it, `each`'s visiting order, and the two
panics. RED: the `to_list` panic test and the `each` panic test each hung (killed at
20 s). Refinecheck: the good/bad literal pair for `Range.to_list`, plus
`to_list(new_step(3, 0, -1))` pinned as 2 proved (new_step's own precondition and
to_list's); all three RED with `range.march` reverted. Native golden `s2` lines.

**Existing tests whose pinned counts moved.** `abstract-leftovers-d` (#17, #18) pins
ledger triples for `sum_pos(Range.filter(Range.new(0, n), …))`: the user module now
has one more proved obligation (Range.filter's `v.step != 0` on `Range.new`'s
result): `(1, 0, 0)` -> `(2, 0, 0)` and `(0, 0, 1)` -> `(1, 0, 1)`. Range.filter's own
definition side is `(8, 0, 0)` -> `(9, 0, 0)` (its `to_list(r)` call). Each has a
comment. The refine-audit baselines gain 11 enforced sites (9 parameters, 2
returns) per fixture; `stdlib_range`'s user code goes 7 -> 18; nothing is unenforced.

## s3. `Control.chunks("abcdef", 0)` looped

**Cause.** `chunks` returns one last chunk when `byte_size(hex) <= size`; otherwise
`chunks_from(hex, size, off + size, n)` advances `off` by `size`. A size of 0 never
moves `off`, and a negative size walks it backwards, so `off + size >= n` never holds.
The probe `Control.chunks("abcdef", 0)` ran until killed (10 s) both interpreted and
compiled. There was no precondition.

**Fix.** `size : {Int | _ > 0}`, as `List.chunks` already has, and
`if size <= 0 do panic("Control.chunks: size must be positive")` before anything
else. Convention ruling: Control's *parsers* return `Result` for bad input documents,
but `chunks` takes a size the program chooses (a protocol constant), returns a plain
`List`, and has one caller (`test/session/control_peers.march`, which passes 4 and
16 through an unrefined `size : Int` parameter, so its obligation is a silent skip
and the runtime guard is what protects it). A `Result` would push error handling into
that caller for a programming error, so a panic. Behaviour change: an empty artifact
with size 0 used to give one empty last chunk (`0 <= 0`); it now panics too, since
the precondition does not depend on the artifact.

**Tests.** `test/stdlib/test_control.march` (`chunks` group): a size of 1, and sizes
0 and -2 (through `chunk_size`, which hides them from the checker) give
`"panic: Control.chunks: size must be positive"`. The comparison goes through a
`String` helper (`chunks_err`) rather than `Result(List(CtlChunk), String) ==`,
which does not typecheck (`CtlChunk` has no `Eq`; the file's older tests compare
such values too, which the untyped stdlib_march evaluator allows and `march test`
rejects). RED: on the pre-fix stdlib the stdlib_march `control` group failed
(`FAIL: "chunks a size that is not positive panics instead of hanging"`) rather than
hang. Refinecheck good/bad literal pair (RED with `control.march` reverted). Native
golden `s3` lines (0 and -2).

**Found, not fixed:** `List.chunks(xs, 0)` has the precondition but no runtime guard
and hangs on a size the checker cannot see (killed at 10 s both modes). Filed as
`specs/todos/2026-10-27-list-chunks-zero-size-hang.md`; it is not one of s1-s4.
