# `[P2]` Stdlib: wrappers forward to a contracted callee without declaring the contract

Filed 2026-09-16, replacing `2026-09-16-refine-local-value-facts.md`, whose
let-flow phases landed (see `specs/progress/2026-09-16-refine-let-if-disjunction.md`
and `-refine-builtin-return-contracts.md`). The census that sized this is
`specs/progress/2026-09-16-refine-skip-census.md`.

**Status (2026-09-22):** the `Stats` row is done
(`specs/progress/2026-09-22-stats-wrapper-contracts.md`; 6 skips → 0).
`aho_corasick` is decided **no**. What remains open is the three
`seq`/`flow`/`gen` sites.

| Sites | Where | Shape | Status |
|---|---|---|---|
| 11 | `stdlib/aho_corasick.march` (`child_of`, `get_fail`, `get_outputs`, …) | `Array.get(nodes, state)` where `state` is an unannotated parameter of an internal helper. | **Decided: do not change.** The contract is relational (`_ < pvec_length(nodes)`); declaring it pushes obligations the helpers' callers cannot discharge. The skips stay, visibly. |
| 3 | `stdlib/seq.march:388`, `stdlib/flow.march:113`, `stdlib/gen.march:390` | A `batch`/`choice_weighted` wrapper forwarding an unrefined `n` / list. | **Open.** Not part of the 2026-09-22 decision. |

## Decision (repo owner, 2026-09-22)

- **`Stats`: yes, for the whole surface** — done, see the progress file.
- **`aho_corasick` (11 sites): decided separately — do NOT change it.** Its
  contract is relational (`_ < pvec_length(nodes)`) and would push unprovable
  obligations onto the helpers' callers.
- **`seq`/`flow`/`gen` (3 sites): not part of the decision** — still open. Each
  is a public-signature change of the same kind as `Stats` and needs its own
  call.

Start from `--refine-suggest <fn>`. Re-run the census with a **neutral entry
file**, not `stdlib/list.march` (see the progress file for why that entry
inflates `dataframe.march`).
