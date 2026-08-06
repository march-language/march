# Per-call-site refinement verdict index

Date: 2026-08-05

## What shipped

`Obligation` now keeps a span-keyed index of every obligation it records, so a
later pass can ask "what did the refinement checker conclude about THIS call
site" instead of only "how many obligations of each verdict does this module
have" (`Obligation.summary`).

New API in `lib/refinecheck/obligation.ml`:

```ocaml
val obligations_at : March_ast.Ast.span -> t list
val verdict_at     : March_ast.Ast.span -> verdict option
val verdict_name   : verdict -> string
```

`verdict_at` returns the **weakest** verdict recorded at that span
(`Violated < Skipped < Trusted < Proved`), never the first one: one call site
raises one obligation per refined parameter, and a consumer folding those
optimistically would admit exactly the calls it must not. `None` means the
checker said nothing about the site — an unrefined call, or one the walk never
reached — and is not a proof.

## Why the index lives in `record`

Every verdict in this subsystem already funnels through `Obligation.record`
(four call sites: `Refine_check`'s precondition `note`, its postcondition
`note`, its match-tail postcondition, and `Division_safety`). Populating the
index there rather than at any individual verdict site means it cannot go
partially stale as those paths change, and it cannot disagree with the ledger
`--refine-report` prints, because it holds the very same records. No new VC is
built and no verdict is re-derived — this is a second *view* of the existing
ledger, not a second discharge path.

## Lifecycle

The index is cleared by the existing `Obligation.reset ()`, which
`Refine_check.check_module` calls at its top — so its lifetime is exactly one
module. A verdict leaking across modules would let a later module read a
`Proved` that was never established for it; `verdict-query`'s "reset clears the
index" case pins that.

## Span keyed on

The obligation's own `span`. For a precondition that is the span
`Refine_check.visit` passes to `check_call` as `~span`, i.e. the `sp` of
`A.EApp (_, _, sp)` — the CALL EXPRESSION's span, **not** the callee name's
span. A consumer must key on the same thing.

## Tests

`test/test_refinecheck.ml`, suite `verdict-query` (6 cases): proved / violated /
skipped verdicts queryable at the call span, an unrefined call absent from the
index, `reset` clearing it, and every ledger entry reachable through the index.
The test derives the query span by walking the parsed AST, not by reading it
back off the ledger — a test that queried with a span taken from
`Obligation.all ()` would pass for any keying whatsoever.

Refinecheck suite: 474 → 480 tests, 0 failures, 0 skips; the 474 pre-existing
results are byte-identical before and after.

No CHANGELOG entry: this is internal plumbing with no user-visible behaviour
change (no diagnostic, no accepted/rejected program changes).
