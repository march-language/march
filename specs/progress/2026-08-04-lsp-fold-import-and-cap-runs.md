# LSP folds runs of imports and runs of capability declarations

`[P2]` - [x] Requested directly: "can we add an lsp feature to collapse groups of
imports and groups of caps?"

The editor-side counterpart to the `march fmt` change in
`specs/progress/2026-08-04-tree-sitter-grammar-and-fmt-runs.md`: the same two runs the
formatter keeps tight now collapse as a single fold.

## What it does

`collect_fold_ranges` (`lsp/lib/analysis.ml`) gains `add_compact_runs`, applied at every
declaration-list level — so it works inside a nested `mod` and inside `describe`, not just
at the top of a file. It emits one range per **maximal consecutive run** of:

| Run | Declarations | Fold kind |
|---|---|---|
| Imports | `DUse`, `DAlias` | `imports` |
| Capabilities | `DNeeds`, `DProofCap`, `DOpts` | `region` |

Imports and capabilities are different runs, so the two blocks fold independently.

`server.ml` previously wrapped every fold kind as `FoldingRangeKind.Other`. It now maps
`imports`/`region`/`comment` onto the standard constructors. This matters for imports
specifically: editors attach behaviour to the standard `imports` kind (VS Code's "Fold all
imports" is bound to it), and `Other "imports"` does not reliably reach that even though it
serialises to the same string.

## Details that took a decision

- **A lone import gets no fold.** There is nothing to collapse, and a chevron in the
  gutter that hides zero lines is noise. This falls out of the existing `add` guard
  (`el > sl`) rather than a special case, since a one-declaration run has
  `end_line = start_line`.
- **Runs must be consecutive.** Folding from the first compact declaration to the last one
  anywhere in the module is a tempting one-liner and is wrong: it collapses whatever sits
  between the two blocks.

## Tests

`lsp/test/test_lsp.ml`, under "~H element folding ranges":

- `import run folds as one range` / `cap run folds as one range` — exact spans.
- `runs do not span other decls` — the **REJECT witness**. Imports split by a function must
  produce two short runs, and no import fold may cover the function. The over-broad
  implementation described above passes both positive tests and fails only this one.
- `lone import does not fold` — asserts silence. Weakly discriminating (the guard it
  depends on is shared with every other fold kind), recorded here rather than overclaimed.

Mutation-checked in both directions: with `add_compact_runs` disabled the two positive
tests and the witness fail; with runs allowed to survive intervening declarations, **only**
the witness fails.

## Wire-level verification

The unit tests assert on `Analysis.fold_ranges`, which sits upstream of the kind-string →
`FoldingRangeKind` mapping in `server.ml` — they cannot see what an editor receives. A
JSON-RPC driver (initialize → didOpen → `textDocument/foldingRange`) against
`~/code/mgrep/lib/mgrep/search/stream.march` confirms the bytes: exactly one range of kind
`"imports"`, covering lines 8–14, which is precisely that file's four imports (blank lines
between them, since the file has not been through `march fmt`).

Also checked for the prelude leak that hit `semanticTokens` and `documentSymbol`
previously: 27 fold ranges on a 161-line document, max `endLine` 158 — nothing beyond the
document.

348 LSP tests pass.
