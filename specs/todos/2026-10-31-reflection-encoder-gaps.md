`[P2]` Refinement reflection: what the body translator still does not encode (each sound, each
loses proofs).  (The `[P1]` constructor-registry bug filed here is fixed:
`specs/progress/2026-11-02-reflection-ctor-registry-by-datatype.md`.)

Filed by phase 1b (`specs/progress/2026-10-31-reflection-phase1b.md`) from the 1a/1b todos; the
design is `specs/2026-10-29-refinement-reflection-design.md`.

(Metric-certified functions (R2) and division by a non-literal (R4) are encoded since
`specs/progress/2026-11-05-reflection-metric-and-division.md`; a divisor shown non-zero only by
the solver, a `match` nested in value position, and guard calls are encoded since
`specs/progress/2026-11-05-reflection-value-match-solver-divisor-guard-calls.md`; Float,
String, records, tuples and destructuring `let`s since
`specs/progress/2026-11-06-reflection-float-string-records-tuples.md`.  Predicate
display-name resolution in the propagation pre-pass was closed by 71f112f4a, which resolves every
reflected call by its site, and is pinned by the `pred-names` suite:
`specs/progress/2026-11-06-predicate-names.md`.)

- **A tuple-typed variable in a predicate.** A lemma parameter or caller variable of tuple
  type gets no sort in the predicate encoder (the sort-marker channel has no tuple marker), so
  `swap(swap(t)) == t` over `t : (Int, Int)` is a `sort-conflict` skip. Literals at a reflected
  call's parameter do translate. (The record half is done:
  `specs/progress/2026-11-06-reflection-record-predicate-variables.md`.)
- **Parametric records.** A record type is matched to its declaration by its field set; a
  record with type parameters declines (its instance is not recovered from the structural
  type).
- **A tuple literal printed in a report** reads `<predicate>` (`pred_str` has no arm for
  `ETuple`; a record literal prints as written since 2026-11-06).
- **`uses:` over-approximation.** When a stage-2 proof's unsat core names no unfolding
  (congruence, I8), `uses:` lists the whole frontier.
