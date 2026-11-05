`[P2]` Refinement reflection: what the body translator still does not encode (each sound, each
loses proofs).  (The `[P1]` constructor-registry bug filed here is fixed:
`specs/progress/2026-11-02-reflection-ctor-registry-by-datatype.md`.)

Filed by phase 1b (`specs/progress/2026-10-31-reflection-phase1b.md`) from the 1a/1b todos; the
design is `specs/2026-10-29-refinement-reflection-design.md`.

(Metric-certified functions (R2) and division by a non-literal (R4) are encoded since
`specs/progress/2026-11-05-reflection-metric-and-division.md`.  What is left of R4: a divisor
shown non-zero only by the solver, such as a refinement `v * v > 0`, still declines.)

- **Float and String.** A function whose signature mentions either has no logic symbol (§2.3's
  opaque Float operators and distinct `$Str` literals are not built).
- **Records and tuples** as parameters or results, and `let` patterns other than a variable:
  the body translator declines (the symbol stays uninterpreted, no equations). (A `match` or
  `if` as a `let`'s right-hand side unfolds since
  `specs/progress/2026-11-04-reflection-let-match-value-position.md`; one nested inside an
  expression, such as an argument, still declines.)
- **`uses:` over-approximation.** When a stage-2 proof's unsat core names no unfolding
  (congruence, I8), `uses:` lists the whole frontier.
- **Predicate display-name resolution in the propagation pre-pass.** A predicate's bare
  spelling resolves in the enclosing function's module only for obligations checked inside
  `visit_fn`; the pre-pass resolves exact display names only.
- **Guard calls are not unfolded.** A guard that calls a reflected function (phase 1b) is part
  of the unfolding's condition; the call it produces is not unfolded again (D12), so the
  equation fires only when the caller's own facts (a path condition naming the same call) decide
  the guard.
