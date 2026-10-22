# Inference-lite, phase 4: fold accumulators (K7)

Landed 2026-10-21. Design §1.2 row K7, §2, §4.3. Plan Task 9. Not yet reachable from the CLI (Task 11).

## What landed

- `Infer_slot.k7_slots`: a fold-shaped call — the callee (found among the unit's functions) returns
  a bare type variable `b`, a lambda argument's FIRST parameter is unannotated and sits at a
  callback position whose domain is `b`, and the `b`-typed argument is an Int literal (v1 reads the
  accumulator's base type from it) — gives a `Lambda_param { line; col; param }` slot.
- `Infer_slot.install` writes `acc : {Int | I}` into that lambda; `map_expr`/`iter_expr` traverse
  the common expression forms.
- `Infer_oracle.accumulator`: rejected when the annotation's own base or step obligation skips
  (`accumulator-base-unproved` / `accumulator-step-unproved`) or a violation appears; accepted when a
  site closes and none opens.
- `Refine_edit.splice_lambda_param`: writes the annotation into a parenthesised lambda parameter
  list; `fn acc -> …` returns `None` ("apply by hand").

## Tests

Group `infer-accumulator` (5): F1 proposes `acc : {Int | _ > 0}`; a failing base (init `0`) and a
failing step (`acc - 1`) propose nothing; the splice, parenthesised and unparenthesised.
