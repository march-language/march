`[P4]` Proof scripts: compile-time March functions that produce hint lemma calls.

Large step 13 of `2026-11-06-verification-ladder-roadmap`. The useful part of tactics (Meta-F*),
kept small.

## Idea

Long proofs repeat the same pattern: call lemma L on every pair of adjacent arguments, unfold f
along a list, case-split on a constructor. A proof script is a March function, run by the
interpreter at check time, that receives the obligation (as a value) and returns the hint
statements (lemma calls, `assert … by`, `reveal`) to try. The checker still decides; the script
only proposes hints.

## Why P4

Most of the payoff comes from `calc`, `assert … by` and quantifiers. Revisit when several real
proofs show the same repetitive hints.

## Done when

One repeated proof pattern in the stdlib (say, accumulator lemmas for `*_onto` loops) is written
once as a script and used by three lemmas.
