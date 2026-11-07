`[P3]` Export reflected definitions and unproved lemmas to Lean 4; admit Lean-proved lemmas by digest.

Medium step 8 of `2026-11-06-verification-ladder-roadmap`. How March gets Lean's proving power
(induction, `omega`, `simp`, mathlib) for the lemmas SMT cannot do, without becoming a proof
assistant. Aeneas (Rust to Lean) and F*'s Lean bridge do the same.

## Why it fits

A reflected March function is already total, pure and terminating with a known metric (R1-R11,
`@[decreases]`): exactly what Lean needs to accept a definition. Int is mathematical in the logic
(design D8), so it maps to Lean's `Int`. Float is opaque and stays excluded.

## Shape

1. `march --emit-lean FILE` writes, for a lemma and everything its theorem reaches: the datatypes,
   the reflected functions (by their logic definitions, with `termination_by` from the metric),
   and the theorem as a `theorem … := by sorry`.
2. Someone proves it in Lean. `march-language/march-lean` (which already re-implements March's
   static checks in Lean 4 and re-checks this repo's corpus) is the natural home and CI.
3. The proved statement's digest (over the exported text) goes into a `lemmas.verified`-style
   manifest with kind `lean`; the checker admits the lemma when the digest still matches, exactly
   as stdlib lemmas are admitted today, and reports it as `proved (lean)`.

## Risks

Semantic drift between the exporter and the checker's own logic definitions. Mitigation: export
from the same logic definitions the checker uses (not from source), and a parity test
(`reflect-parity` style) that evaluates the Lean definitions and March's interpreter on the same
inputs.

## Done when

- One lemma SMT cannot prove (e.g. the `zip`/`unzip` round trip, or an AVL rotation law) is
  exported, proved in Lean in march-lean, and admitted here by digest; editing the March function
  invalidates it.
