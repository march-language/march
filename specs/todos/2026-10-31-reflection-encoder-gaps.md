`[P2]` Refinement reflection: what the body translator still does not encode (each sound, each
loses proofs).  (The `[P1]` constructor-registry bug filed here is fixed:
`specs/progress/2026-11-02-reflection-ctor-registry-by-datatype.md`.)

Filed by phase 1b (`specs/progress/2026-10-31-reflection-phase1b.md`) from the 1a/1b todos; the
design is `specs/2026-10-29-refinement-reflection-design.md`.

- **Metric-certified functions (R2).** The encoder reads only the termination graph's own
  certificate; a `metric` certificate is decided by the refinement walk, after the encoder is
  built, so such a function (design probe r1's `p`) is not unfolded.
- **Division by a non-literal (R4).** Its `Division` obligation is filed after the check, so
  every `/` or `%` by a non-literal blocks reflection.
- **Float and String.** A function whose signature mentions either has no logic symbol (§2.3's
  opaque Float operators and distinct `$Str` literals are not built).
- **Records and tuples** as parameters or results, `let` patterns other than a variable, and a
  `match` in a non-tail value position: the body translator declines (the symbol stays
  uninterpreted, no equations).
- **`uses:` over-approximation.** When a stage-2 proof's unsat core names no unfolding
  (congruence, I8), `uses:` lists the whole frontier.
- **Predicate display-name resolution in the propagation pre-pass.** A predicate's bare
  spelling resolves in the enclosing function's module only for obligations checked inside
  `visit_fn`; the pre-pass resolves exact display names only.
- **Guard calls are not unfolded.** A guard that calls a reflected function (phase 1b) is part
  of the unfolding's condition; the call it produces is not unfolded again (D12), so the
  equation fires only when the caller's own facts (a path condition naming the same call) decide
  the guard.
