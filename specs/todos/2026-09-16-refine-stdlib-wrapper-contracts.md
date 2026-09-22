# `[P2]` Stdlib: wrappers forward to a contracted callee without declaring the contract

Filed 2026-09-16, replacing `2026-09-16-refine-local-value-facts.md`, whose
let-flow phases landed (see `specs/progress/2026-09-16-refine-let-if-disjunction.md`
and `-refine-builtin-return-contracts.md`). The census that sized this is
`specs/progress/2026-09-16-refine-skip-census.md`.

**The dominant remaining skip category: 20 of the 42 `unconstrained-subject`
skips**, all the same shape — a function forwards a value to a callee with a
declared contract, without declaring the same contract on its own parameter.
The contract is already true and usually already documented in prose; it is
simply not stated in the signature, so the checker has nothing to carry.

| Sites | Where | Shape |
|---|---|---|
| 11 | `stdlib/aho_corasick.march` (`child_of`, `get_fail`, `get_outputs`, …) | `Array.get(nodes, state)` where `state` is an unannotated parameter of an internal helper. The contract is relational (`_ < pvec_length(nodes)`), which the checker supports at call sites but which pushes the obligation out to the helper's own callers — check whether they can discharge it before committing to this shape. |
| 6 | `stdlib/stats.march` (`median`, `quantile`, `quantiles`, `variance`) | `median(xs : List(Float))` calls `percentile(xs, 50.0)`, whose parameter is `{List(Float) \| len(_) > 0}`. The doc string already says "Panics on empty list"; the signature does not. |
| 3 | `stdlib/seq.march:388`, `stdlib/flow.march:113`, `stdlib/gen.march:390` | Same: a `batch`/`choice_weighted` wrapper forwarding an unrefined `n`. |

**This is an API decision, not an encoder change, and it is why it is filed
rather than done.** Declaring `{List(Float) | len(_) > 0}` on `Stats.median`
makes a currently-accepted call a compile error wherever the caller cannot
prove non-emptiness. That is the point — it is how `DataFrame.col_describe`'s
panic (`specs/todos/`, its own item) would have been caught at compile time —
but it is a breaking change to a public signature and should be decided
deliberately, ideally for the whole `Stats` surface at once.

## Decision (repo owner, 2026-09-22)

- **`Stats`: yes, for the whole surface.** Every `Stats` function whose callee
  requires a non-empty list restates `{List(Float) | len(_) > 0}` (and any other
  forwarded contract, e.g. `quantile_default`'s `q` range) on its own
  parameter, so the public API is consistent. Shipped with `--refine-suggest`
  as the documented migration path for callers.
- **`aho_corasick` (11 sites): decided separately — do NOT change it.** Its
  contract is relational (`_ < pvec_length(nodes)`) and would push unprovable
  obligations onto the helpers' callers.
- **`seq`/`flow`/`gen` (3 sites): not part of the decision** — still open.

`--refine-suggest <fn>` already proposes these; start there rather than by
hand. Re-run the census afterwards: the expectation is that these skips turn
into PROVED at the wrapper and reappear at whichever caller genuinely cannot
establish the precondition, which is where they belong.
