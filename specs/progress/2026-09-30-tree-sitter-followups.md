# tree-sitter follow-ups: keyword check, D6 rule, wasm removed, Zed URL

Four of the five items in `specs/todos/2026-09-28-tree-sitter-followups.md` (the
permissiveness item stays open).

- **Keyword coverage (D5).** `scripts/check-tree-sitter.sh` step 5 extracts the
  `keyword_table` entries from `lib/lexer/lexer.mll` and requires each to appear as a quoted
  literal in `grammar.js` or in `tree-sitter-march/keyword-allowlist.txt`. A stale allowlist
  line (now in the grammar, or no longer a keyword) is red too, so the list only shrinks, and
  an extraction of fewer than 40 keywords is itself an error (layout change must not make the
  check vacuous). Today 9 are allowlisted: `dbg invariant offer one_for_all one_for_one
  permanent rest_for_one temporary transient` (the todo's list predates `offer`).
- **D6.** CLAUDE.md "Keeping specs up to date" now says who keeps the grammar green.
- **D3.** `tree-sitter-march/tree-sitter-march.wasm` deleted; any future wasm consumer should
  get it from a CI build, not a committed binary.
- **Zed.** `zed-march/extension.toml` uses the GitHub URL and `rev` `f13d38501`.
