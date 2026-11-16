`[P3]` Ghost code follow-ups.

Ghost code landed 2026-11-08 (`specs/progress/2026-11-08-ghost-code.md`). Open:

- **A ghost-set worked proof.** The milestone's tree-to-set example
  (`insert` proved against the set a tree holds) is blocked by two checker
  limits, not by ghost code: a user `@[measure]` returning a set that uses
  `empty` is refused, "names empty as a value" (R7 in
  `lib/refinecheck/refine_reflect.ml`; filed as
  `2026-11-08-set-measure-empty-invalid-measure`), and a result contract that
  is not an `Int` (`{Bool | _ == mem(t, x)}`, a constructor-valued
  `{Tree | bst(_, lo, hi)}`) does not use its body's facts or the matched
  constructor (`specs/lang/lemmas.md`, "What lemmas don't do (yet)").
- **Pattern links outside ghost hypotheses.** A match arm in an ordinary
  function gets the scrutinee's constructor links only when a scope
  hypothesis mentions a `ghost fn` (or inside a lemma, or under a bounded
  quantifier). The same fact would help `{Tree | pos(_)}` with a plain
  reflected `pos`; widening the gate changes existing SMT, so measure the
  refine oracle and solver time first.
- **Ghost parameters where the desugarer merges clauses**: several clauses, a
  pattern parameter or a `when` guard. The merged clause matches on a tuple
  of every argument, so the ghost one would need to be left out of it.
- **Ghost parameters on impl and interface methods**, and a function with
  ghost parameters passed as a value (it would need an erased wrapper).
- **The REPLs.** `Lemma_erase.blank_lemma_decl` is all they run per input, so a
  ghost declaration entered there is not erased: the interpreter evaluates
  ghost arguments (pure, so harmless), and the JIT compiles a `ghost fn`.
  Erase per input with the session's declarations as the whole program.
- **Actor ghost state** (a handler's message history), after
  `2026-11-06-two-state-specs`; name the conformance assumptions any bridge to
  the runtime makes.
