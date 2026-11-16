`[P3]` Classify failed VCs (fast `unknown` vs budget exhausted) and profile quantifier instantiations on exhaustion.

Source: `specs/2026-11-08-auto-active-verifier-lessons.md` (research survey, 2026-11-08), recommendation 5.

## Why

Failures come in two kinds (Cazamariposas). A fast `unknown` means a fact or instantiation is
missing. Running out of budget means an instantiation storm: a median of about 270k
instantiations, against about 4.6k for healthy queries. In 61% of unstable queries a single
quantified formula is to blame. Verus ships a profiler that launches automatically on timeout
and names the culprit quantifier.

## Wanted

- Each `refinement_unverified` diagnostic says which kind of failure it was and gives matching
  advice. Missing fact: suggest a lemma, a `reveal`, or an `assert … by`. Instantiation storm:
  name the axiom/measure/lemma with the most instantiations (z3 `smt.qi.profile`) and suggest
  opaque or a narrower trigger.
- Low-confidence automatic trigger choices print a note (Verus) once unbounded quantified
  lemmas land.

## Done when

Both kinds are reproduced by fixtures, and the error corpus pins the advice text.
