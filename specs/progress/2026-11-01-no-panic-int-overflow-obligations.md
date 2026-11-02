# `cap no_panic` proves Int `+ - *` and negation cannot overflow

Road to 1.0, Phase 2 (`specs/plans/2026-09-28-road-to-1.0.md`). Filed 2026-10-30 as
the other half of the Int overflow trap (`specs/progress/2026-10-30-int-overflow-trap.md`):
the trap made the checker's unbounded-integer model sound for code that runs; this makes
`cap no_panic` code prove it never takes the trap. Before, `fn inc(x : Int) : Int do
x + 1 end` in a `cap no_panic` module was accepted and panicked at `int_max_value()`.

## What the pass does

`lib/refinecheck/overflow_safety.ml`, run right after `Division_safety` in both driver
paths (`bin/main.ml`). For every Int `a + b`, `a - b`, `a * b` and `negate(a)` in a
`cap no_panic` module it discharges `-2^62 <= result <= 2^62 - 1` with Z3; anything
short of `Verified` is an `int_overflow` error, and a `Refuted` model names the
user-visible values (`x = 4611686018427387903`). Literal-only operands settle without a
solver. Each site records an `Obligation.Overflow` entry (new kind, printed in
`--refine-report`'s by-kind line and `--refine-report-sites` only when present).

- **Same coverage as division.** `Division_safety`'s walker became `iter_sites ~site`
  and its module walk `check_decls_with ~clause`, so both passes visit exactly the same
  declarations (impl methods with the same adoptable-refinement rule, actor handlers,
  top-level lets, tests, nested modules re-deriving their own `cap`) with the same
  shadowing discipline.
- **Which sites.** `+ - *` are `Num`-polymorphic; the typechecker's span -> type table
  (now passed in) decides. A site recorded as a concrete non-Int type (Float) is
  skipped; Int, an unresolved type variable, or no table is checked (fail closed).
- **What a VC assumes.** Every Int variable and every unreflected sub-expression (a
  call, a field, an `if`) is a constant bounded to the Int range: the trap guarantees no
  held value is outside it. The site's operands, nested arithmetic included, were
  evaluated first, so they are in range too; so is a tracked `let` right-hand side. A
  guard contributes its comparison but no range fact for its own arithmetic (under
  `p && q`, `q` may not have run). Guards are read only when the typechecker recorded
  Int on a side of each comparison, so a Float guard (`0.0 < a && a < 1.0`, which has
  no integer solution) cannot make a goal vacuous. Refined parameters not rebound since,
  and `let` equations transitively for the names the VC mentions, provided nothing the
  right-hand side mentions has been rebound (`shadowed` does not record when).
- **Small models.** `/` and `%` by a positive literal (truncation mapped onto SMT's
  Euclidean `div`/`mod` through the dividend's sign); `string_byte_at` in [-1, 255];
  `string_byte_length` / `string_length` non-negative.

## A soundness bug it exposed

`Smt.render` printed `IntLit min_int` as `(- -4611686018427387904)` (`- min_int` wraps
to `min_int`), which Z3 reads as +2^62. The first version of this pass bounded every
constant below by that literal, so every query's assumptions were contradictory and
every site "proved". The printer now takes the magnitude from the decimal text. Any
other VC that ever carried `int_min_value()` as a literal had the same wrong number.

## A division hole the shared walker closed

`Division_safety.bind_let` recorded `let d = d - 1` as the `let` value of `d`, and the
divisor check reflected it with `d` meaning the NEW binding: `d = d - 1`, unsatisfiable,
so `10 / d` "proved" non-zero and `f(1)` divided by zero under `cap no_panic`. A `let`
whose right-hand side mentions its own binder is no longer recorded, and `retire` now
also drops every entry whose right-hand side mentions a retired name (`let a = x; let
x = 0` would otherwise read `a = 0`). Regression: the first case of
`divsafety-shadowing`.

## JsonStream

The stdlib's only `cap no_panic` module had 97 unprovable sites at first; the two small
models above brought that to 88, all byte indices (`i + 1`), stream offsets
(`base + i`), accumulated lengths and the nesting depth. Nothing ties them to the input
length across the helper functions, and none can reach 2^62 for a real input. Decided
2026-11-01 (user): spell them `int_wrapping_add` / `_sub` / `_mul` rather than thread
index refinements through every helper or drop `cap no_panic`. Same values, no panic
site; a comment under `cap no_panic` says why. Arithmetic the checker proves (bytes
under range guards, literals) keeps the plain operators.

## Tests

`overflow-safety` in `test/test_refinecheck.ml` (typechecked, as the driver runs it):
unbounded add reported with its witness; refinement, guard, `x >= 0` then `- 1`,
negation, multiplication, `let` chain, literal `/` and `%`, `string_byte_at`, each with
a reject control; Float and the wrapping builtins are not sites; the three soundness
traps above (a rebound name in a `let` equation, a rebinding retiring a guard, a
short-circuited guard's arithmetic, a Float guard) each rejected; the ledger records one
proved and one violated `Overflow` with the by-kind line. `test/errors/int_overflow_1`
pins the rendered diagnostic; `specs/lang/errors/int_overflow.md` is the `--explain`
page.

## Still open

`int_abs`, `int_pow`, `int_shl`, the `-2^62 / -1` quotient, `NativeArray.sum_int` and
the fused map-sum loop still wrap and are not sites (each its own decision, as the trap
note says). The reflection side (`specs/todos/2026-10-29-reflection-int-overflow.md`) is
separate.
