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

(Parametric records reached through reflected functions and the `uses:` fallback are closed
since `specs/progress/2026-11-08-reflection-encoder-gaps-records-uses.md`.)

- **A tuple-typed return binder, and a reflected call over a tuple-typed record field.**
  Tuple-typed parameters, lemma parameters, caller values and tuple literals in a predicate are
  encoded since `specs/progress/2026-11-06-stdlib-lemma-sweep-s3-tuples.md`, and record-typed
  variables since `specs/progress/2026-11-06-reflection-record-predicate-variables.md`. Left:
  a tuple RETURN refinement (`fn mk(x) : {(Int, Int) | Tuple.first(_) == x}` is
  `unreflectable-subject` on the definition side; `return_refine_ext` / `return_refine_sorted`
  have no tuple arm, and it must go to `post_walk_verdict`, not `engine`, which would take
  `$Tup2` for a record sort), and a reflected call over a tuple-typed record field
  (`type Box = { v : {(Int, Int) | Tuple.first(_) > 0} }` is checked at every construction but
  `unreflectable-predicate`; a field predicate without a call, `_ == (1, 0)`, proves and is
  violated as it should).
- **A parametric record's field read directly in a predicate.** `p.fst` over `p : Pr(Int)` in a
  theorem or a callee refinement (`n : {Int | _ > p.fst}`) does not reflect: the record
  environment (`Refine_scope.recenv`, `(name, sort name)`) holds only records without type
  arguments, so the variable has no instance sort there. A theorem that reads the fields through
  a reflected function (`sum(p)`) proves. Closing it means carrying a full `Smt.sort` in
  `recenv` (about 80 sites, all compiler-checked).
- **`uses:` when a stage-2 query assumed nothing.** `Reflect_stage` still lists the whole run's
  frontier for a proof whose query assumed no unfolding literal at all.
