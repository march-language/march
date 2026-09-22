# Refinement predicates: `/` and `%` in the truncation-safe fragment

**Done 2026-09-22** (increment 1 of
`specs/todos/2026-09-16-refine-predicate-language-widening.md`, which stays
open for increment 2, general truncation).

## What

`/` and `%` in a refinement predicate (and in a path-condition guard, which
goes through the same reflector) now translate to SMT when the divisor is a
non-zero integer literal and the dividend is known to be non-negative. There
March's truncating division and SMT-LIB's Euclidean `div`/`mod` agree: for
`a >= 0` and `k != 0` of either sign, truncation gives `q = sign(k)*(a div |k|)`
and `r = a mod |k|`, which satisfy `a = k*q + r, 0 <= r < |k|`, the unique
Euclidean pair. Checked empirically too: every `a` in [-200,200] times `k` in
[-13,13]\{0}: 0 disagreements for `a >= 0`, 3934 for `a < 0`. So negative
literal divisors (`_ / -2`, parsed as `negate(2)`) are admitted.

- `lib/refine/smt.ml`: `DivLit of term * int` / `ModLit of term * int`,
  rendered `(div a k)`/`(mod a k)`; arms added to every exhaustive term walk
  (`refine_encode.ml`, `undecided.ml`, `return_infer.ml`). They are not
  `nonlinear`.
- `lib/refinecheck/refine_encode.ml`: `nonzero_int_literal`, now shared by the
  `@[measure]` totality gate (which as a result also accepts a negative-literal
  divisor) and the reflector; `/` and `%` join `predicate_operators`.
- `lib/refinecheck/refine_scope.ml`: the division arm of `smt_of_r_marked`,
  `known_nonneg` (non-negative literal; `+`/`*`/in-fragment `/`/`%` of
  non-negatives; a measure in `is_nonneg_measure`; `card`; or an atom
  (variable, `x.f`, `m(x)`) a conjunct of an enclosing `&&` chain bounds by
  `>= c`/`> c`/`== c` with the literal non-negative). The `&&`-context rule is
  sound because the fact conjunct itself contains no division: where it holds
  the guarded divisions are exact, and where it fails the chain is `false`
  both in the logic and in fact. Chosen over an SMT side query for being
  syntactic, local and obviously sound; the side query is noted for increment 2.
- Outside the fragment: still an `unreflectable-predicate` skip, but
  `Obligation.Unreflectable_predicate` now carries an optional why-sentence
  (`division_outside_fragment_hint`: the divisor is not a non-zero literal /
  the dividend is not known non-negative), and the vocabulary warning at the
  definition says the same instead of the misleading "`/` is not a measure or
  known predicate".
- `lib/refinecheck/witness.ml`: `eval_operand` evaluates `/`/`%` with
  OCaml's (March's) truncating semantics and returns `None` on a zero divisor.

## Verification

- New tests in `test/test_refinecheck.ml` (`obligation-reasons`: UP2 rewritten
  plus eight division cases; `gate-mb`: two literal-divisor gate cases).
- Red control (lib/ at origin/main, new tests): 8 failures in
  `obligation-reasons` and 1 in `gate-mb`, e.g. "no skips" expected `[]`,
  received `["unreflectable-predicate"; "unreflectable-predicate"]`; the violated
  literal call expected `(0, 1, 0)`, received `(0, 0, 1)`. Old message on the
  accepting fixture: "the predicate's `_ / 2` has no SMT translation".
- Witness mutation (delete the `/`/`%` arm of `eval_operand`): the
  postcondition-witness case goes red ("f's counterexample is executed and
  shown": expected true, received false). The refutation then lands as a silent
  solver-undecided skip, so outside `cap verified` nothing is reported.
- Soundness mutation (`known_nonneg` always true): UP2 and the
  "possibly-negative dividend" case go red.
- `--check` of all 124 `stdlib/*.march` with pre/post compilers (private HOME):
  byte-identical. `scripts/refine-oracle.sh` baseline (pre) / check (post):
  identical over 371 fixtures. The corpus has no division predicates, so that
  GREEN means only that nothing else moved.
