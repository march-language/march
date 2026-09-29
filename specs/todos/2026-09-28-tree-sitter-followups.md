# tree-sitter grammar: follow-ups after the 2026-09-28 sync

`[P3]` Leftovers from `specs/2026-09-23-tree-sitter-grammar-sync-design.md` once
the grammar reached 0 failures (`specs/progress/2026-09-28-tree-sitter-grammar-sync.md`).
None of these is a missing construct; `scripts/check-tree-sitter.sh` now catches
a new one.

- [ ] **Keyword coverage check (design D5).** Not built. Today the `lexer.mll`
  keywords with no literal in `grammar.js` are `dbg invariant one_for_one
  one_for_all rest_for_one permanent transient temporary`; they parse as
  identifiers, which is fine for highlighting, but a check would catch the next
  new keyword before it becomes an ERROR.
- [ ] **Who keeps it green (D6).** Add a line to CLAUDE.md "Keeping specs up to
  date": a PR that changes `parser.mly`/`lexer.mll` either extends `grammar.js`
  or lists its new fixtures in `tree-sitter-march/known-failures.txt` with a todo.
- [ ] **`tree-sitter-march.wasm` (D3).** Still committed and hand-regenerated;
  nothing in the repo loads it. Delete it, or build it in CI, depending on
  whether anything outside the repo consumes it.
- [ ] **Zed (Stage 5).** Bump `zed-march/extension.toml`'s grammar `rev` to a
  commit with the new grammar, and replace the machine-local
  `file:///Users/...` repository URL if Zed support is meant for anyone else.
- [ ] **Permissiveness.** The grammar accepts things the compiler rejects (every
  lambda body in call position, `let?` spelled as one token, attributes as free
  declarations). Harmless for highlighting; tighten only if a consumer needs
  tree-sitter to reject.
