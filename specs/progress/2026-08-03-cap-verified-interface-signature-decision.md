## Decision (2026-08-03): escalate

Went with escalation. `cap verified`'s escalation machinery (`check_call`,
`check_post`) is scoped to undischarged *obligations* in the ledger, and an
inert `interface` signature raises none — so this genuinely is new machinery,
not a flipped flag, and the "for leaving it" argument below is correct as far
as it goes. But `cap verified`'s entire selling point is "no more silence, if
it compiles it is proved," and every other inert-refinement shape this
project has found (`sig`/`extern` signatures) already gets a warning
specifically because silence was judged worse than a false sense of
enforcement; an inert `interface` signature is exactly the shape `cap
verified` exists to catch, so leaving it a warning under that capability
specifically felt like the one gap in the promise the mode makes. Implemented
in `lib/refinecheck/refine_check.ml`: `warn_iface_method_refinement` now takes
an explicit `~strict` flag and emits `Err.error` instead of `Err.warning` when
set. Because `warn_predicate_decls` (the vocabulary pass this lives in) runs
*after* `visit_decls` has already restored the `strict_verified` ref via its
own `Fun.protect`, `strict` could not be read off that ref at the call site —
it had already gone back to `false` by the time this code runs, which would
have made the escalation silently inert. It is instead recomputed directly
from each decl list's own `cap verified` declaration (new helper
`decls_declare_verified`), threaded down through `warn_predicate_decls`
exactly like `strict_verified`'s own scoping rule: a nested `mod` does not
inherit and recomputes from its own decls, a `describe` block inherits
unchanged. See `test/test_refinecheck.ml`'s `iface_refine_suite` for the
paired escalate/non-escalate regression tests.

---

`[P3]` **Should `cap verified` escalate an inert `interface`-signature refinement to an error?**

Unexamined, and no test covers the combination either before or after the
2026-07-30 work. Today a `cap verified` module containing

```march
interface Runner(a) do
  fn run : a -> {Int | _ > 0} -> Int
end
```

exits 0 with a warning.

**For leaving it:** `cap verified`'s escalation machinery
(`check_call`/`check_post`'s `note`) fires on *undischarged obligations*, and an
inert interface signature raises no obligation at all — there is nothing in the
ledger to escalate. This would be new machinery, not a flipped flag.

**Against:** the mode's whole promise is "if it compiles, it is proved", and a
contract that provably enforces nothing sits awkwardly under that promise.

Filed rather than decided, so the next person does not have to re-derive the
tradeoff. Related: `2026-07-31-refine-sig-and-extern-signature-refinements-inert.md`
raises the same question for `sig`/`extern`.
