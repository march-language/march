`[P2]` Diagnostics: one root cause, one report. Poison types/bindings after a failed check, a
`(primary, suppressed, scope)` table next to `lib/errors/code.ml`, and merging of capability findings about one
fact. 103 `test/errors/` cases have >1 ERROR; 35 non-capability cases carry a follow-on `cap_grant`. specs/plans/2026-11-02-diagnostics-depth-plan.md §X3.

Partly done 2026-11-02 (`specs/progress/2026-11-02-diag-hints-cascades-internals-lint.md`): `Errors.suppress_cascades`
with four rules (arity→mismatch, typo→unused, cap_grant while other errors, cap_ceiling+cap_needs). Open: poison types,
merging the reach-chain HINT into its error, the session/linearity follow-ons, the multi-error corpus review, and the
LSP path.

2026-11-03: the multi-error review, seven more rules and the LSP path landed
(`specs/progress/2026-11-03-diag-x3-x4-finish-x7-traces.md`). Open: poison types (do before the
choreography item), the swapped-pair mismatch on `x ++ "no"` (a blame question, §X1).
