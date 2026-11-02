`[P2]` Refinement reflection: what the body translator still does not encode (each sound, each
loses proofs), and one encoder registry bug found on the way (`[P1]` item below).

Filed by phase 1b (`specs/progress/2026-10-31-reflection-phase1b.md`) from the 1a/1b todos; the
design is `specs/2026-10-29-refinement-reflection-design.md`.

- **`[P1]` The constructor field registry is keyed by constructor NAME.** `Refine_encode`'s
  `set_ctor_fields` / `ctor_field_sorts` hold one entry per name, so a user type declaring
  `Some(Int)` overwrites `Option`'s `Some(a)`. Every `Option` instance of such a program is then
  declared with an `Int` payload (z3 log of the phase-1a review's `ctor2.march`:
  `(declare-datatypes ((M_Option$M_Supervision 0)) (((None) (Some (Some_0 Int)))))`), stage-1
  queries included. Not unsound in any probe (an ill-sorted term makes z3 reject the query), but
  it is wrong, and it is why phase 1b did not resolve constructors by the scrutinee's type
  (ruling there): a body's `Some` resolved to `Option` would still be built against the user
  type's fields. Fix: key fields, testers and selectors by (datatype, constructor), with
  qualified SMT names for a name two datatypes declare. Then resolve a body's constructors by
  the scrutinee's type (decline when the type does not pin one datatype), and the stdlib `Option`
  functions are reflected in programs that declare their own `Some`/`None`.
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
