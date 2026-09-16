# Refinement predicates: non-linear multiplication

**Landed 2026-09-16.** Plan: `specs/plans/2026-09-16-refinement-precision-plan.md`
(Part B, phase B1). Open item:
`specs/todos/2026-09-16-refine-predicate-language-widening.md` (items 2 and 3
remain).

## What changed

`Refine_scope.smt_of`'s `*` arm required one literal factor and returned
`Error` for two non-literal ones, so `{Int | _ * _ >= 0}` — a tautology over
the integers — was an `unreflectable-predicate` skip. It now falls through to
`Smt.Mul`.

Nothing downstream needed teaching: `Smt.Mul` already existed and
`division_safety.ml` has emitted it since it shipped, with a note recording
that refusing general products "was a REGRESSION source, not a safety
measure"; every `Smt.term` traversal already had an arm; `witness.ml`'s
predicate evaluator already handled `*`; `"*"` was already in
`predicate_operators`.

`Obligation.Nonlinear_goal` — written, then cut in 2026 before it first
shipped because no `smt_of` could produce a two-operand `Smt.Mul` in a goal —
is revived and reachable. `Undecided.diagnose` reports it when the GOAL (never
the assumptions: a non-linear fact the author supplied is not why their goal
went undecided) multiplies two non-constant terms. It ranks below
`Unconstrained_subject`, which is the more actionable of the two, and it is
throttled with the residual family at the call-site hint, since the sentence
is a fact about the predicate's shape and reads identically at every call site.

## Why this is not a soundness change

The solver is incomplete on non-linear integer arithmetic, not unsound. A goal
z3 cannot settle returns `unknown`, which every caller already treats as
not-proved, and the 3 s per-query timeout (`lib/refine/solver.ml`) bounds what
that costs. A definite failure stays definite: the witness evaluator executes
the candidate and confirms it before anything is reported.

## Two fixtures had to move

Both used a non-linear expression as a stand-in for "true but unprovable", and
both now prove:

- `postcond-ledger` "an UNDECIDABLE postcondition stays silent" used
  `z * z + 1 > 0`.
- `record-postcond-propagation` "an UNPROVEN record postcondition does not
  propagate" used `{ port: x * x + 1 }`; once proved, it propagated
  `v.port >= 1` and turned the downstream `needLow` call into a definite
  violation.

Both are re-based on an uncontracted callee (`av(x)`), which keeps the
property they were written to test: the value reflects to an unconstrained
constant so the goal is unprovable, while the predicate really does hold for
every input so no witness can confirm a violation. A fixture asserting that
the old stand-in now proves is registered in the new `nonlinear-mul` group, so
the next reader can see where it went.

## Measurements

- `nonlinear-mul` group: 7 cases; the three behavioural ones are RED on the
  previous translator (verified by reverting the arm and re-running) and green
  after.
- `--refine-report stdlib/list.march`: unchanged at 38 proved / 31 trusted /
  46 skipped — no stdlib predicate is non-linear, so no ceiling moves.
- `--refine-audit stdlib/list.march`: unchanged at 114 enforced, 0 unenforced.
- Cold check of a trivial module: 0.38 s, against the ~0.4 s baseline.

## Docs

`specs/lang/refinement-types.md` and `docs/refinement-types.md` both used
`x * x >= 0` as the canonical example of a predicate the checker cannot
translate. That is no longer true, and a doc example that the checker now
proves would teach the opposite of the lesson, so both are re-written around
an uncontracted call, and both fragment descriptions now say what is and is
not linear.
