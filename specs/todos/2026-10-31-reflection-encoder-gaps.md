`[P2]` Refinement reflection: what the body translator still does not encode (each sound, each
loses proofs).  (The `[P1]` constructor-registry bug filed here is fixed:
`specs/progress/2026-11-02-reflection-ctor-registry-by-datatype.md`.)

Filed by phase 1b (`specs/progress/2026-10-31-reflection-phase1b.md`) from the 1a/1b todos; the
design is `specs/2026-10-29-refinement-reflection-design.md`.

(Metric-certified functions (R2) and division by a non-literal (R4) are encoded since
`specs/progress/2026-11-05-reflection-metric-and-division.md`; a divisor shown non-zero only by
the solver, a `match` nested in value position, and guard calls are encoded since
`specs/progress/2026-11-05-reflection-value-match-solver-divisor-guard-calls.md`.  Predicate
display-name resolution in the propagation pre-pass was closed by 71f112f4a, which resolves every
reflected call by its site, and is pinned by the `pred-names` suite:
`specs/progress/2026-11-06-predicate-names.md`.)

- **Float and String.** A function whose signature mentions either has no logic symbol (§2.3's
  opaque Float operators and distinct `$Str` literals are not built).
- **Records and tuples** as parameters or results, and `let` patterns other than a variable:
  the body translator declines (the symbol stays uninterpreted, no equations).
- **`uses:` over-approximation.** When a stage-2 proof's unsat core names no unfolding
  (congruence, I8), `uses:` lists the whole frontier.
