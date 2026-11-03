# Refinement types chapter restructured for first readers (2026-10-13)

`specs/lang/refinement-types.md` (rendered as `docs/refinement-types.md`) is 187 KB and 27
sections, so unlike the choreography, observe and capabilities chapters rewritten the same
day, the section *bodies* were left byte-for-byte intact and only the frame changed:

- a new opener: what a refinement is, the definite-failure bargain in two sentences, the
  Z3 note; then an **On this page** index grouping all 27 sections into Start here,
  Refining each kind of value, Finding out what was actually checked, Strict modes, and
  Limits and status (the old "New to this?" paragraph did this job in prose);
- **When to use refinements**: the real-bug test, a table from goal to feature, and the
  two "don't" cases (every `Int`; provenance facts, which are an opaque type's job);
- **How it fits with the rest of March**: type system, pattern matching (guards as facts),
  capabilities (`cap verified` / `cap no_panic` as behavioral caps), stdlib contracts,
  linear types, safety by construction, tooling;
- sections reordered into those groups: the teaching sections first (with `Postconditions`
  now directly before `Postconditions Flow to Call Sites`, and `Practical Rules` moved up
  from the tail), then the per-value-kind sections, then the report/audit/suggest tooling
  with `--no-measure-axioms`, then the two strict modes, then Limitations and Conformance
  status; `Next Steps` became `See also` with two more links.

Every in-page anchor resolves after the move (checked by script); every "above"/"below"
phrase in the bodies still points the right way under the new order (checked by grep); no
inline-code token was dropped; `scripts/check-docs.sh` passes. The explicit id on the
`cap no_panic` heading is unchanged. The dated notes inside section bodies (98 mentions
of 2026 dates) are untouched by this pass.
