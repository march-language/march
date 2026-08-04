# Syntax highlighting repaired for six missing constructs; `fmt` keeps import/cap runs tight

`[P1]` - [x] Reported as "syntax highlighting breaks on this file"
(`~/code/mgrep/lib/mgrep/search/stream.march`), plus a formatting request to stop
putting a blank line between consecutive imports and between consecutive capability
declarations.

## The highlighting failure

The tree-sitter grammar produced **22 ERROR nodes** on a 161-line file the compiler
parses without complaint. Editors highlight from that tree, so one error near the top
poisons everything below it.

The first and largest error was at line 1. `module_def` was

```js
'mod', field('name', $.type_identifier),
```

— a *single* segment. `mod Mgrep.Search.Stream do` therefore failed immediately, and the
recovery region swallowed the next 39 lines. Six constructs the compiler has accepted for
a long time were absent from the grammar altogether:

| Construct | Example | Was |
|---|---|---|
| Dotted module name | `mod A.B.C do` | ERROR |
| `import` / `alias` | `import A.B.{c, D}` | ERROR (no rule at all) |
| `needs` / `cap` / `proof cap` | `needs IO.Foreign` | ERROR (no rule at all) |
| `pfn`, `ptype` | `pfn f() : Int do` | ERROR |
| Refinement types | `{ Int \| _ > 0 }` | ERROR |
| Qualified type path / call | `A.B.Mode`, `A.B.C.go(x)` | ERROR |

Refinement types needed a `refinement_placeholder` node for the `_` that stands for the
refined value — it exists only as a *pattern* elsewhere, and the predicate is an
expression. Qualified value paths were cheapest to express by letting
`field_expression`'s field be a `type_identifier`, so `A.B.C.go` is nested field access.

## Measurement

Corpus: 199 `.march` files — the stdlib plus `~/code/mgrep` and `~/code/forgepm`.

| | files with an ERROR node |
|---|---|
| before | 188 / 199 |
| after | 150 / 199 |
| regressions | **0** |

The reported file goes 22 ERROR nodes → 0.

**Apparatus trap worth remembering:** `tree-sitter parse` resolves the grammar through
`parser-directories` in `~/.config/tree-sitter/config.json`, which lists
`/Users/80197052/code/march` — the *main repo*. Editing the grammar in a worktree and
running `tree-sitter parse` measures the main repo's grammar and shows no change
whatsoever. Point it at the worktree with `--config-path` (note: it is a *subcommand*
flag, `tree-sitter parse --config-path ...`, not a global one). Separately, the compiled
grammar is cached at `~/.cache/tree-sitter/lib/march.dylib` and is not always invalidated
by a regenerate — delete it between measurements.

## `fmt`: runs of imports and caps stay tight

`emit_decls` put one blank line between every pair of top-level declarations, so a block
of eight imports formatted as eight paragraphs. Now a run of `DUse`/`DAlias`, or a run of
`DNeeds`/`DProofCap`/`DOpts`, is emitted with no blank line inside it. The two kinds are
*different* runs, so an import block and a cap block stay separated from each other, and
everything else is unchanged.

Found while testing that: **`march fmt` re-emitted `cap no_panic` as `opts no_panic`**.
There is no `opts` keyword in March — the only surface spelling is `cap <name>`, and the
lexer maps it to a single token. So formatting any file with a capability declaration
produced a file that no longer parsed, and `fmt` was not idempotent on it. Pre-existing;
fixed here since it sits squarely in the requested area.

## Tests

- `test/test_fmt.ml`: `import run is tight`, `cap run is tight` (which also pins the
  `cap no_panic` round-trip), and `unrelated decls keep blank line`.
- The third is the **REJECT witness**: a formatter that simply dropped every blank line
  would pass the first two. Mutation-checked in both directions — with tightening
  disabled only the first two fail; with tightening applied unconditionally only the
  third fails.
- `tree-sitter-march/test/corpus/`: new cases for dotted module names, imports, aliases,
  capabilities, `pfn`/`ptype`, all three refinement forms, and qualified paths. 56/56
  parse, with no `ERROR` baked into any expectation.
- The corpus update reflowed all 47 pre-existing expectations. Verified mechanically
  (whitespace-normalise both sides, undo the `module_path` wrapper, compare) that **0 of
  10 files** changed semantically beyond that one intended wrapper.
- `tree-sitter-march.wasm` regenerated — it is committed and hand-synced with the grammar.

Full suite: 2 failures (`cap_strip` #3, `adversarial-regressions` #40), both reproduced
with `lib/format/format.ml` reverted to HEAD, so both are pre-existing and unrelated. The
control run also surfaced `adversarial-regressions` #34, which the main run passed — that
one is flaky.

## Not done

150 of 199 corpus files still contain a parse error, from constructs unrelated to this
report. Tracked in `specs/todos/2026-08-04-tree-sitter-grammar-drift.md`.
