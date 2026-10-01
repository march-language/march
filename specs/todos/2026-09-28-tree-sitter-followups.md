# tree-sitter grammar: follow-ups after the 2026-09-28 sync

`[P3]` Leftovers from `specs/2026-09-23-tree-sitter-grammar-sync-design.md` once
the grammar reached 0 failures (`specs/progress/2026-09-28-tree-sitter-grammar-sync.md`).
None of these is a missing construct; `scripts/check-tree-sitter.sh` now catches
a new one.

- [x] ~~**Keyword coverage check (design D5).**~~ Done: step 5 of
  `scripts/check-tree-sitter.sh`, allowlist `tree-sitter-march/keyword-allowlist.txt`.
  See `specs/progress/2026-09-30-tree-sitter-followups.md`.
- [x] ~~**Who keeps it green (D6).**~~ Done: line added to CLAUDE.md "Keeping specs up to date".
- [x] ~~**`tree-sitter-march.wasm` (D3).**~~ Deleted (owner decision): nothing in the repo
  loads it and Zed builds the grammar from source. If a consumer ever needs a wasm, build it in
  the `tree-sitter` CI job rather than committing it.
- [x] ~~**Zed (Stage 5).**~~ Done: `zed-march/extension.toml` points at
  `https://github.com/march-language/march` with `rev` `f13d38501` (the commit that brought the
  grammar to 0 failures).
- [ ] **Permissiveness.** The grammar accepts things the compiler rejects (every
  lambda body in call position, `let?` spelled as one token, attributes as free
  declarations). Harmless for highlighting; tighten only if a consumer needs
  tree-sitter to reject.
