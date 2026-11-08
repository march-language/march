# Reflection encoder gaps: parametric records, tuple literals, `uses:` (2026-11-08)

Three items from `specs/todos/2026-10-31-reflection-encoder-gaps.md`. The tuple-variable item
is on branch `claude/s3-tuples-finish`, and the two pieces left are listed in the todo.

## What changed

- **Parametric records (`refine_reflect.ml`).** `record_of_fields` matched a structural record
  type (the typechecker keeps records by their field set, not by name) only against a
  declaration with no type parameters, so a call `sw(p)` with `p : Pr(Int)` resolved to no logic
  symbol and every predicate over it was `unreflectable-predicate`. The new
  `record_of_fields_inst` reads each type parameter off the field that holds it (every
  occurrence must agree, and every parameter must be held by some field) and answers the
  instance. `poly_sort` gives the record `SData (M_Pr, [Int])`. Lemmas `sw(sw(p)) == p`,
  `swg(swg(p)) == p` for a generic `swg : Pr(a) -> Pr(a)`, and `sum(sw(p)) == sum(p)` are admitted.
  `sw(p) == p` is not.
- **Tuple literals in reports (`refine_scope.ml`).** `pred_str` prints `(a, b)` instead of
  `<predicate>`. The same arm exists on the S3 branch, so the two branches merge by keeping one.
- **`uses:` (`refine.ml`, `obligation.ml`, `reflect_stage.ml`).** `Refine.last_assumed` keeps the
  unfolding literals the last query assumed. A proof whose core names none of them records
  the definitions its own query assumed, not every definition the stage-2 run unfolded.

## Verification

| Check | Result |
|---|---|
| `pred-names`: a tuple literal prints as written | RED (`_ == <predicate>`) → GREEN, 26/26 |
| `reflect-record-vars`: three parametric-record lemmas admitted, a false one not | RED (3 fail) → GREEN, 22/22 |
| `reflect-1b`: an empty core reports the query's frontier; a core still wins; a stage-1 proof records nothing | RED (1 fail) → GREEN, 14/14 |
