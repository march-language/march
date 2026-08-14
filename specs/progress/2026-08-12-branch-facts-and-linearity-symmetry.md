# `if` vs `match`: branch-exclusive linearity and Bool path facts

**Date:** 2026-08-12
**Status:** shipped

## What was wrong

Three gaps, found while scoping a cookbook chapter that combines session types,
refinement types, capabilities and actors. Two of them are exact mirrors of each
other, which is why the combination had no workaround inside a single construct:

|                          | refinement path facts | linear branch-exclusivity |
|--------------------------|-----------------------|---------------------------|
| `if cond do … else … end`| yes                   | **no**                    |
| `match b do true/false`  | **no**                | yes                       |

1. **Linearity.** `iter_arms_linear` (snapshot / reset-per-arm / union) gave
   `EMatch` the mutually-exclusive-paths rule. `EIf` and `ECond` inferred their
   branches sequentially against the shared `le_used` flag, so consuming one
   linear value once per branch was reported as "used more than once". That the
   intended semantics is the other way round was already written down — in the
   comment on `test_linear_match_arms_each_consume_once_ok`, an explicit
   regression guard for the match-arm snapshot. `if` was simply never wired to
   it.

2. **Field as a refined actual.** `reflect_scalar`'s `plain` fallback called
   `smt_of` with no `resolve_field`, so the (already-present) `EField` arm always
   hit the `None` default. `takepos(a.rem)` therefore produced an unreflectable
   goal, and an undecidable obligation is accepted in silence. Note this was
   never actor-specific: a plain record behaved identically, and the actor
   `state.field` case was one instance of it.

3. **Bool-scrutinee match.** `visit`'s `EMatch` arm narrows only on constructor
   patterns over a variable scrutinee, so `match cond do true -> …` pushed no
   path condition at all while `EIf` pushed `(c, negated)`.

## What shipped

- `iter_arms_linear` generalised to `iter_paths_linear` over a list of path
  thunks; `EMatch` keeps its behaviour as a pure refactor. `EIf` runs its two
  branches as paths — **after** checking the condition, so a value consumed in
  the condition still counts on both paths. `ECond` gets a hand-rolled variant
  because only its *bodies* are mutually exclusive: its conditions chain, so a
  later condition genuinely co-occurs with earlier ones on the fall-through
  path and they must share use-state.
- `reflect_scalar` gained an optional `foreign_field`; `check_call` supplies
  `arg_resolve_field`, deliberately building the *same* selector term
  `path_resolve_field` builds for path conditions — the guard and the goal only
  close if both land on one symbol. A receiver outside `recenv` still yields
  `None` (skipped, never guessed).
- `visit` pushes `(subj, not bv)` for a Bool-literal arm, and `(subj, bv)` for
  each earlier Bool-literal arm that failed, giving a `_` fallback the negation.
  A guarded earlier arm licenses nothing — it can fail with the literal still
  matching.

## Why it is not over-permissive

Each fix ships with a negative control, because "the obligation now passes" and
"the obligation now proves nothing" look identical from a green test:

- a value used in an `if` condition *and* a branch is still a double-use;
  two uses within one branch are still a double-use;
- an unguarded `takepos(a.rem)` is still reported, and a guard on a *sibling*
  field proves nothing about this one;
- the `false` arm does not inherit the `true` arm's fact.

The refinement tests run under `cap verified`, which turns an undischarged
obligation into a hard error — so "no error" there means *proved*, not merely
*unreported*.

## Verification

Full suite (incl. Slow) green; `dune build @types-check` 291/291 with a
deliberately cold `.march/cas/vc` (a warm VC cache content-addresses verdicts
and would have masked a changed one).

## Consequence for the cookbook

The pure-decision-core / effectful-shell split that the actor+session+refinement
chapter was forced into is now a design *choice* rather than a workaround: `if`
carries both properties, so refined arithmetic and linear channel branching can
live in the same construct.
