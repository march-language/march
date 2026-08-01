`[P2]` **A refinement in a `sig` or `extern` signature is silently inert.**

```march
sig Store do
  fn put : Int -> {Int | _ > 0}
end
```

`--check` exits 0 with *zero* diagnostics. `A.DSig` carries
`sig_fns : (name * ty) list` and `A.DExtern` carries `extern_fn`'s
`ef_params`/`ef_ret_ty`, any of which can hold a `TyRefine`, but
`warn_predicate_decls` (`lib/refinecheck/refine_check.ml`) walks neither.

This is the same shape as the `interface`-method-signature case that was made
loud on 2026-07-30 — it parses, typechecks, reads like a working contract, and
enforces nothing. The concrete failure is an author who reads the new
`interface` warning, moves the contract into a `sig`, and gets silence again.

Worse, the decl list holding `DSig`/`DExtern` was labelled *"inert: no type
annotation or expression that can carry a refinement predicate"* — a comment a
future implementer would reasonably trust. The label is corrected; the hole is
not. This is the same family as the five decl walks that each produced a real
bug.

Minimum fix is a warning matching the `interface` one. Making these signatures
actually enforce is a larger question (a `sig` is a module-interface ascription;
an `extern` is an FFI boundary where the callee is not March code at all).
