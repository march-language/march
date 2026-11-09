`[P2]` Validate the SMT encoding against the interpreter, and label counterexamples "confirmed by execution" vs "not reproduced".

Source: `specs/2026-11-08-auto-active-verifier-lessons.md` (research survey, 2026-11-08), recommendation 7.

## Why

In the cases surveyed, false assurance came from the encoding and the specifications, never
from a solver bug. Cedar's differential testing found 21 bugs where proofs found 4. AWS's
authorization engine found 13 spec errors by testing before any proof gave useful feedback.
A checked solver proof (`2026-11-06-checked-solver-proofs`) cannot catch a wrong encoding.
March has a reference semantics of its own, the interpreter, which no other surveyed tool has.

## Wanted

- An encoding fuzzer. Generate small closed terms over reflected functions, measures and the set
  vocabulary, then compare z3's verdict on `term == value` with the interpreter's evaluation.
  Any disagreement is an encoding bug. Run it in CI over a fixed seed corpus.
- Counterexample labels. When the solver's model is replayed (`lib/refinecheck/witness.ml`),
  say whether the failure was reproduced by execution (a real bug) or not (a missing hint or a
  solver limit). The ETH survey found users cannot tell tool failures from program failures.
- A negated-postcondition smoke test. For each proved contract, check that the negation is not
  also provable. If it is, the contract is vacuous.

## Done when

The fuzzer runs in CI and has found or ruled out a seeded encoding bug (proved RED on a
perturbation). Labels appear in the CLI, JSON and LSP, and are pinned in the error corpus.
