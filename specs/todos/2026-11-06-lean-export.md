`[P3]` Export reflected definitions and unproved lemmas to Lean 4; admit Lean-proved lemmas by digest.

Medium step 8 of `2026-11-06-verification-ladder-roadmap`. How March gets Lean's proving power
(induction, `omega`, `simp`, mathlib) for the lemmas SMT cannot do, without becoming a proof
assistant. External proof is a separate backend with an explicit translation and admission boundary.

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

## Admission protocol and semantic boundary (2026-11-07)

[Refinement Reflection](https://nikivazou.github.io/static/popl18/refinement-reflection.pdf)
relies on a pure, terminating reflected fragment. Export that fragment, not unchecked source.
The following are March admission requirements; a matching text digest alone is not a proof.

- Generate a proof task with `sorry` only as an editor scaffold. Admission requires a successful
  Lean build and an audit of the theorem's transitive axioms: reject `sorryAx` and custom
  unapproved axioms; list any allowed foundational axioms explicitly. Prevent replacement of
  generated definitions or theorem statements by user proof files.
- Bind evidence to the canonical theorem, transitive reflected definitions, datatype layouts,
  measures/axioms, arithmetic encoding, exporter version and pinned Lean/dependency versions.
  Check the elaborated theorem against the generated statement. A changed callee or trusted
  assumption invalidates evidence even when the lemma's source text is unchanged.
- Publish the trust boundary: Lean checks a theorem about the translation; the exporter,
  admission verifier and source/logic correspondence remain trusted unless separately proved.
  Mathematical Int in the logic does not by itself justify machine integer behavior: export
  the checker's actual overflow/domain assumptions and test arithmetic edge cases.
- Start with structural recursion. A March termination metric is input to translation, not a
  promise that Lean accepts the definition automatically. Unsupported recursion, partiality,
  floats or effects produce explicit export failures. No `axiom` fallback for definitions.

Acceptance adds: reject a `sorry` proof; reject an extra axiom and an altered statement; invalidate
on a changed dependency; retain admission across irrelevant source formatting. Evaluate exported
functions against the interpreter on boundary and generated inputs, while stating that testing
is correspondence evidence, not a proof of the translator.
