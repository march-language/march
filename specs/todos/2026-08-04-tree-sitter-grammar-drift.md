# The tree-sitter grammar still fails on 150 of 199 real March files

`[P2]` - [ ] **`tree-sitter-march/grammar.js` lags the compiler's parser by more than the
six constructs fixed on 2026-08-04.** Editors highlight from this grammar, so every gap
shows up as a file that renders as one long error region.

## Measurement

Corpus: 199 `.march` files — `stdlib/` plus `~/code/mgrep/lib` and `~/code/forgepm/lib`.

| | files containing an ERROR node |
|---|---|
| before 2026-08-04 | 188 / 199 |
| after | 150 / 199 |

See `specs/progress/2026-08-04-tree-sitter-grammar-and-fmt-runs.md` for what that fix
covered (dotted module names, `import`/`alias`/`needs`/`cap`, `pfn`/`ptype`, refinement
types, qualified paths).

## How to measure without fooling yourself

`tree-sitter parse` resolves the grammar via `parser-directories` in
`~/.config/tree-sitter/config.json`, which lists `/Users/80197052/code/march` — the **main
repo**. Editing the grammar in a worktree and running `tree-sitter parse` silently
measures the main repo and reports no change. Write a config whose `parser-directories`
is the worktree and pass it as a *subcommand* flag:

```bash
tree-sitter parse --config-path /tmp/myconf/config.json file.march
```

The compiled grammar is also cached at `~/.cache/tree-sitter/lib/march.dylib` and is not
reliably invalidated by `tree-sitter generate`. Delete it between measurements.

## Confirmed minimal repros

Each of these parses cleanly in the compiler and produces 3 ERROR nodes in the grammar:

```march
-- 1. record literal as an expression
let x = { a: 1, b: 2 }

-- 2. tuple pattern mixing an atom and a list literal
match xs do
(:get, ["a", "b"]) -> 1
_ -> 0
end

-- 3. `resource` declarations — no rule in the grammar at all
resource R do
  1
end
```

Record literals are the likely big win: `record_expression` exists in the grammar, so this
is a `{`-disambiguation problem against blocks/refinements rather than a missing rule, and
record literals are everywhere in the corpus.

## Approach

Do **not** work file-by-file. Run the corpus sweep, cluster the innermost ERROR sites by
the construct on that line, and fix the largest cluster first — that is how the six
constructs above were found. Re-run the sweep after each change and assert two things:
the failing count went down, **and** the set of failing files is a subset of the previous
set. A grammar change that fixes ten files and breaks two nets out positive on a count
alone; only the subset check catches it.

## Acceptance

- The failing-file count drops materially from 150/199, with zero regressions (subset
  check, not just the count).
- Each newly supported construct gets a case in `tree-sitter-march/test/corpus/`, and no
  expectation in that directory contains an `ERROR` node.
- `tree-sitter-march.wasm` is regenerated — it is committed and hand-synced, so a grammar
  change that skips it ships stale to editors.

## Note

`tree-sitter test --update` reflows *every* expectation in the corpus, so its diff is
mostly whitespace and cannot be eyeballed. Verify semantically instead: normalise
whitespace on both the old and new s-expressions, undo the one change you intended, and
assert the two are then identical.
