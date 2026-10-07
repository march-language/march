# Refinement: callback argument binders, and the abstract-refinement definer at pass sites

Landed 2026-10-06. Plan: `specs/plans/2026-10-06-abstract-refinements-phase2-plan.md`
(PR A, tasks A1-A5). Prerequisite of abstract refinements phase 2
(`specs/2026-09-20-abstract-refinements-design.md`, §0 "Re-probed 2026-10-06").

## The problem

A callback type's codomain may name its domain's argument:
`keep : ({x : Int | true}) -> {Bool | _ == (x > 0)}`. Three places never
renamed that argument, and the checker had no notion of an abstract-refinement
definer at a pass site.

| Probe (2026-10-06, `24c7eb543`) | Before | After |
|---|---|---|
| `if keep(h) do Cons(h, …)` against a `List({Int \| _ > 0})` return | 3× skipped | proved |
| `let b = keep(h)`, then `if b do pos(h)` | skipped | proved |
| `ap(fn y -> y > 0, 3)` where `({x : Int \| true}) -> {Bool \| _ == (x > 0)}` is expected | `solver-undecided` | proved |
| `ap(is_pos, 3)`, `is_pos(n) : {Bool \| _ == (n > 0)}` | **violated: build error**, witness `n = 0, x = 1` | proved |
| phase-1 `filt(ys, fn y -> y > 0)` / `filt(ys, is_even)` / the body's own `filt(t, keep)` | 4× `unreflectable-predicate`; **error** under `cap verified` | nothing recorded; compiles under `cap verified` |

The fourth row was a false positive on main: a correct program was rejected.

## Causes and fixes

1. **`callback_sig_of_ty`** (`lib/refinecheck/refine_scope.ml`) named the
   parameter `$cb_arg` but kept `x` in the return predicate. `postcond_of`
   therefore classified the predicate as `Unusable`, and the path fact
   `keep(h)` was dropped silently. Fix: the new `dom_binder` reads `x`, and the
   return predicate is rewritten with `subst_params [x ↦ $cb_arg]`. A codomain
   binder spelled like `x` shadows it and is left alone.
2. **`check_pass_sites`, lambda arm** (`refine_check.ml`): the lambda was
   verified against `cod` with `x` free, and `check_post` made it a fresh
   constant. Fix: rename `x` to the lambda's own parameter in `cod`.
3. **`check_pass_sites`, named-callable arm**: the callable's proved return
   `rq` mentions its own parameter `n`, while the goal mentions `$cb_arg`
   (after 1). The two were independent constants, so `n = 0, x = 1` refuted
   the implication, and a `Callback_codomain` refutation is definite. Fix:
   rename `n ↦ $cb_arg` in `rq` when the callable has exactly one parameter.
   A forwarded callback's signature already names `$cb_arg`.
4. **Definer exemption**: a codomain that applies one of the *callee's*
   abstract refinements (`_ == p(x)`) is satisfied by any callable, because
   `p` is whatever the callable returns. `check_pass_sites` takes the new
   `~callee_name` and skips the codomain obligation when it applies a name in
   `callee_abstracts ctx callee_name`. That function wraps
   `Refine_abstract.names` over the callee's definition, memoised in
   `abstracts_tbl`, which is reset per `check_module`. A concrete codomain
   still obliges the callable (AP3).

## Tests

- `callback-binder`:
  - CB1: guard fact proves the element return.
  - CB2: the else branch gets the negation, so `Cons(h, …)` there is a *definite violation*, which is correct.
  - CB3/CB4: lambda.
  - CB5/CB6: named callable.
  - CB7/CB8: the let-bound value route and its unguarded control.
- `abstract-pass-sites`:
  - AP1: no definer skips.
  - AP2: compiles under `cap verified`.
  - AP3: a concrete codomain still errors.
- Non-vacuity: disabling the A1 rename (`when false && …`) reddens CB2, CB5 and CB7 (and CB1).

## Verification

- `scripts/run-tests.sh refinecheck compiler`: 984 + 1367 tests, all passing.
- `scripts/refine-oracle.sh check`: **IDENTICAL** (7547 lines, 468 fixtures).
  This is expected, not vacuous: no program in its corpus (`test/native`,
  `stdlib`) writes a callback domain with a named binder, so none reaches the
  changed code. The unit tests and the perturbation above are what exercise it.
- CI ratchet (`stdlib/list.march`, user + stdlib): 55 proved, 0 violated, 33 trusted, **37 skipped** (limit 42); `--refine-audit`: 0 unenforced.
