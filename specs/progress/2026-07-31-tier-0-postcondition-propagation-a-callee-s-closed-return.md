- Tier 0 postcondition propagation: a callee's closed return refinement is
  recorded in `fn_sig.ret` and consumed at call sites, for both `let`-bound and
  inline-argument forms. Relational (parameter-mentioning) postconditions
  remain definition-only. Only postconditions the definition side POSITIVELY
  VERIFIED propagate (an unproven one stays legal but tells callers nothing —
  trusting it would flag correct code); binding constructs now clear shadowed
  refined-scope entries (lambda/`let fn` params, `let` bindings, `match`
  pattern binders); counterexamples render `f$retN` as `f() returns v`.
