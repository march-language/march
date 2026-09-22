# Refinement: a non-linear call-site argument is reflected (`need_pos(y * y + 1)` proves)

**Landed 2026-09-22.** The original todo text is kept below.

## What changed

`Refine_resolve.reflect_scalar`'s `*` arm, the call-site ARGUMENT reflector,
required one literal factor and otherwise fell back to `plain`, which fails for
any variable, so the obligation had no subject (`unreflectable-subject`). A
product of two non-literal operands now reflects both operands through the same
function and builds `Smt.Mul`, as `Refine_scope.smt_of` has done for predicates
since 2026-09-16. If either operand fails to reflect, the whole actual still
falls back to `plain`, never to a partial term.

Nothing else needed teaching. `Obligation.Nonlinear_goal` / `nonlinear-goal`
already existed and `Undecided.diagnose` already classified goals containing
`Smt.Mul`. `Witness.eval_operand` already had a `*` arm, so a refuted
non-linear argument is confirmed with an executed counterexample (no witness
change was made).

## Tests (test/test_refinecheck.ml)

- `nonlinear-mul` group, 3 new cases:
  - `need_pos(y * y + 1)` proves: ledger (1, 0, 0), no `unreflectable-subject`.
  - `if y == 0 do need_pos(y * y - 1) ...` is a violation whose text carries
    `y = 0`.
  - An unguarded `need_pos(y * y - 1)` is a skip with reasons exactly
    `["nonlinear-goal"]`. An unguarded parameter is never a definite failure,
    and the linear `need_pos(y - 1)` is a `solver-undecided` skip for the same
    reason. This test exercises `Undecided.diagnose` on a real goal. It is not
    a pinned z3 `unknown`: no fixture reliably drives one without tying the
    test to a solver version (the existing slug test builds the VC by hand for
    the same reason).
- `demand-flow` group: design row l, `f(mapl(ys, fn y -> y * y + 1))`, proves
  (1, 0, 0).

**Red control** (`lib/refinecheck/refine_resolve.ml` swapped for origin/main's
copy): `nonlinear-mul` 7/8/9 FAIL (e.g. `proved` Expected `(1, 0, 0)`,
Received `(0, 0, 1)`), `demand-flow` 0 FAILS on the new
`fn y -> y * y + 1 proves` (Received `(0, 0, 1)`). All pass after the change.
Through the driver, the pre-change compiler reported `need_pos(y * y + 1)` as
"the argument `y * y + 1` could not be translated to SMT". With the real
stdlib, `f(List.map(ys, fn y -> y * y + 1))` went from 1 skipped
(`parametric-source-unproved`) to 1 proved.

## Verification

- `--check` on all 124 `stdlib/*.march` with the pre and post compilers
  (`MARCH_STDLIB` set): byte-identical. So is the `--refine-report` summary of
  each file with a cleared CAS (`list.march` is unchanged at 43 proved /
  40 skipped over user + stdlib).
- `scripts/refine-oracle.sh baseline` (pre) / `check` (post): IDENTICAL, 7373
  lines over 371 fixtures. The oracle corpus has no violation programs, so this
  only shows that nothing else moved.
- Docs: `nonlinear-goal` (and `parametric-source-unproved`, which was also
  missing) were added to the skip-reason lists in `docs/refinement-types.md`
  and `specs/lang/refinement-types.md`. Both now also note that a non-linear
  argument proves.

---

# `[P3]` Refinement: an argument using non-linear arithmetic is never translated

Filed 2026-09-18, found while landing the demand-driven element rule
(`specs/progress/2026-09-18-refine-demand-driven-element-instantiation.md`).

```march
fn need_pos(n : {Int | _ > 0}) : Int do n end
fn t(y : Int) : Int do need_pos(y * y + 1) end    -- skip: unreflectable-subject
```

The 2026-09-16 widening (`specs/progress/2026-09-16-refine-nonlinear-multiplication.md`)
admitted a product of two non-literal terms in a PREDICATE (`smt_of`), not in
an ARGUMENT: the call-site reflector still refuses it, so the obligation has no
subject at all. A postcondition over the same expression proves (a lambda
`fn y -> y * y + 1` against a declared `(Int) -> {Int | _ > 0}` codomain is
proved through `check_fn_post_verdict`), so the two translators disagree.

Consequence: `List.map(ys, fn y -> y * y + 1)` cannot meet a positive-element
demand (the design's row l). Admit `Smt.Mul` in the argument reflector with the
same `nonlinear-goal` skip reason for a goal the solver cannot settle, and make
sure `Witness.eval_operand` evaluates it (it handles `*` already).
