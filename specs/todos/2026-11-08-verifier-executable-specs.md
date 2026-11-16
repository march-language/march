`[P2]` Executable specifications: refinements and postconditions as `Check.all` oracles, and boundary checks for unverified callers.

Source: `specs/2026-11-08-auto-active-verifier-lessons.md` (research survey, 2026-11-08), recommendation 9.

## Why

In every AWS case, testing found more specification bugs than proofs did (Cedar 21 vs 4;
authorization engine 13 before the first useful proof). Project Everest's retrospective names
runtime checks at the verified/unverified boundary as its top unmet wish. March refinements
are already executable expressions, so they can serve as oracles at no extra spec cost.

## Wanted

- `march test --contracts`: for every function with a refined signature, generate inputs
  satisfying its parameter refinements (reusing the counterexample enumerator) and check the
  result refinement by execution. A failure is a real bug or a wrong contract, found before the
  prover is involved.
- Optional runtime checks at a `cap verified` module's public boundary for callers outside it
  (`--boundary-checks`). This is the dual of `2026-11-05-proved-preconditions-drop-runtime-checks`.

## Done when

Contract testing runs over the stdlib's refined functions in CI, and a seeded wrong contract is
caught by testing.
