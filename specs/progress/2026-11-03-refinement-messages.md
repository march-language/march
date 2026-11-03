# DONE 2026-11-03: author-written messages on refinement conjuncts

Design: `specs/2026-11-03-refinement-messages-design.md` (item 6 of the OxCaml
review, `[@error_message]`).

## What landed

- Syntax `{Int | _ >= 0 else "msg" && _ < len(xs) else "msg"}`: parser rule
  `refine_pred`, AST node `ERefineMsg`, formatter round trip, tree-sitter
  `refinement_message`.
- `March_ast.Refine_msg`: desugar strips the wrappers and keeps the messages by
  conjunct span; the stdlib AST cache stores and restores them.
- A violated call leads with the broken conjunct's message and names that
  conjunct; an unproven call's partial-conjunct hint appends the missing
  conjuncts' messages.
- Stdlib two-sided bounds carry messages (`List.nth`, `Array.get`/`set`, `Simd`
  lane accessors, `DateTime.fixed_zone`/`fixed_zone_hm`, `Random.bernoulli`,
  `Stats.percentile`/`quantile`/`quantile_default`).

## Tests

- `test_refinecheck` group `refine-messages`: first and second conjunct broken,
  binder form, `else` binding tighter than `&&` (an unmessaged conjunct keeps the
  old text), the unproven-call hint, and a re-desugared file dropping a deleted
  message.
- `test_fmt`: messages print back, escaped quotes included.
- Golden corpus: `refinement_violated_14` (new, stdlib `List.nth` negative index)
  and `refinement_violated_12` (re-pinned: the stdlib message now leads).
- Tree-sitter corpus case; checked by hand that a warm stdlib cache keeps the
  messages (the first cut lost them: the cache stores desugared decls).
