# Scoped proof-hint validation

Follow-up to `2026-11-06-proof-hints.md`, retaining the landed `EProof` representation and calc/reveal/fuel support. PR #1192 originally implemented scoped assertions independently; PR #1189 landed overlapping syntax while its checks were pending. This follow-up carries the additional verification boundary and regression coverage onto that implementation.

- Validate scoped hints with the lemma purity/termination/reflection rules, including with `MARCH_REFLECT=0`.
- Check static hint assertions before adding their facts. Require every contained obligation to pass before exporting the goal. Unproved goals warn normally and error under `cap verified`.
- Preserve lexical hint blocks and reject hint bindings that capture names used by the goal.
- Check tail branch exits independently, and export the proved goal from scopes used inside lemmas and let expressions.
- Restore proof results, assertion results, and proof depth across speculative walks and functions.
- Run proof erasure even in modules with no lemma declarations and in REPL declaration blanking.

Twenty-two scoped-assertion regressions are added to `reflect-lemma`; the existing proof-hints suite covers compatibility with calc, reveal, and local fuel. The focused compatibility run passed 40 cases; the final three lexical/reveal/fuel cases passed after review fixes, covering all 22 new cases and all 19 existing proof-hint cases. Both diagnostic fixtures and style validation passed. Generated docs, doc lint, production Jekyll, and the 296-page search index passed. Full CI remains the merge gate.

Review also preserved lexical scope in analysis walks and explicitly revealed opaque functions (only already validated revealable units), and kept the final goal inside trailing local-fuel scopes. A restoration regression uses a deeper goal so the previously exported conclusion cannot make the check vacuous.
