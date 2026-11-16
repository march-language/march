# `&&` / `||` short-circuit — DONE (2026-11-11)

Reported as GAPS S17 by the Strata project: `i >= 0 && ... && i < sx && ... &&
NativeArray.get_u8(a, i + ...) == 1` died with "native_u8_arr_get: index -11 out of bounds"
under `forge test` when the point lay outside the window.

Cause: the parser builds `a && b` / `a || b` as an ordinary `EApp (EVar "&&"/"||", [a; b])`,
and both the interpreter's generic application arm and TIR lowering evaluated every argument
before applying the builtin. Nothing short-circuited, interpreted or compiled. The spec had
recorded that as fact (core-march.md §4.4.1, "strict, not short-circuiting"), but the
refinement and division-safety checkers already assumed short-circuiting: `d != 0 && 10 / d > 1`
passed `--check` and then divided by zero. So this was also a soundness hole in the checker's
model of the runtime.

Fix:
- `lib/eval/eval.ml`: an `eval_expr` arm for `EApp (EVar "&&"|"||", [a; b])`, ahead of the
  generic application arm, evaluates `b` only when `a` does not decide the result.
- `lib/tir/lower_expr.ml`: the same shape lowers to an `ECase` on `a` (as `if` does), so the
  LLVM, JS and JIT backends all short-circuit. An *eager-safe* right operand keeps the strict
  builtin (one `and`/`or`, no branch): a variable, a literal, or an Int/Float/Bool comparison,
  `+ - *`, `not` or `&&`/`||` over those, plus `/`/`%` by a non-zero integer literal.
  Evaluating it early can neither fail nor have an effect. Without that rule a guard chain
  like `i >= 0 && i < n` became a branch per test, and a tight pure-`&&` loop ran ~10% slower;
  with it, that loop matches the old timing (0.60 s both, best of 7, `--opt 2`).
- The AST, the typechecker and refinecheck are unchanged.
- The operator symbols cannot be rebound by a program, so the shape alone identifies them. A
  first-class use of the builtin value still sees two evaluated operands (δ-And/δ-Or).

Spec: core-march.md §4.4.1 rewritten (E-And-F/T, E-Or-T/F), with the δ-table note and the
cross-references in core-march-types.md, grammar.md and golden/INDEX.md updated. The golden
witness `g13_strict_bool.march` became `g13_short_circuit_bool.march` and now checks that the
decided operand's `println` never fires.

Test: `test/test_codegen.ml` `test_and_or_short_circuit_parity` (group "short-circuit bool
ops") runs one program interpreted and compiled and requires both outputs to equal the
expected trace. It covers skipped and evaluated operands of both operators, a chain, a mixed
`(&&) || ...`, a guarded division, the S17 guarded `NativeArray.get_u8`, a `String ==` left
operand, and `&&` as an `if` condition. `test_and_or_lowering_shape` pins which right operands
stay a strict builtin and which branch.

TIR snapshots regenerated (lower and perceus): `tuple_param_borrowed_destruct`,
`nested_cons_ctor_heap`, `record_field_tail_projection`, `trmc_computed_arg_nested` and
`trmc_modulo_cons`. Their stdlib code is lowered without a type map in that harness, so every
`&&`/`||` with a computed right operand now shows as a `case`; the rest is temp renumbering.
For example `List.pmap`'s `length(xs) <= t || not(spawn_allowed())` now calls
`spawn_allowed()` only when the length test fails.
