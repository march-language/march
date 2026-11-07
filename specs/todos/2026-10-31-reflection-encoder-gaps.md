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
`specs/progress/2026-11-06-reflection-float-string-records-tuples.md`.)

- **A record-typed variable in a predicate, and a tuple-typed return binder.** Tuple-typed
  parameters, lemma parameters, caller values and tuple literals in a predicate are encoded since
  `specs/progress/2026-11-06-stdlib-lemma-sweep-s3-tuples.md`. Left: a RECORD-typed variable
  (`px(p) == p.x + p.y` over `p : Pt` is `unreflectable-predicate`; records have their own
  field-flattening mode), and a tuple RETURN refinement (`fn mk(x) : {(Int, Int) |
  Tuple.first(_) == x}` is `unreflectable-subject` on the definition side; `return_refine_ext` /
  `return_refine_sorted` have no tuple arm, and it must go to `post_walk_verdict`, not `engine`,
  which would take `$Tup2` for a record sort).
- **Parametric records.** A record type is matched to its declaration by its field set; a
  record with type parameters declines (its instance is not recovered from the structural
  type).
- **A record literal printed in a report** reads `<predicate>` (`pred_str` has no `ERecord`
  arm; a tuple literal prints since the S3 tuples change).
- **`uses:` over-approximation.** When a stage-2 proof's unsat core names no unfolding
  (congruence, I8), `uses:` lists the whole frontier.
- **Predicate display-name resolution in the propagation pre-pass.** A predicate's bare
  spelling resolves in the enclosing function's module only for obligations checked inside
  `visit_fn`; the pre-pass resolves exact display names only.
