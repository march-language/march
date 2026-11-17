# `on` / `loop` / `by` / `opaque` as names, and float exponents — DONE (2026-11-16)

Reported by the Strata project (GAPS S1, S2, S4, S7, S13):
- `let opaque = …` was "I got stuck here".
- A pattern variable `by` was a parse error.
- A parameter `on` parsed, but any later use of it did not.
- `pfn loop(…)` was a syntax error at the name.
- `1.0e-12` was "I was expecting `do` after the condition".

Cause: `on`, `loop`, `by` and `opaque` are lexer keywords. `on` and `loop` were in
`soft_lower_name`, so they could be *bound* but never *referenced* (the "soft-keyword
imbalance" in surface-syntax.md). `by` and `opaque` could be neither. The FLOAT lexer rule
had no exponent.

Fix:
- `lib/parser/token_filter.ml` demotes the four words to `LOWER_IDENT` unless the
  surrounding tokens show the keyword use. This is the same one-token-lookahead mechanism
  `restart`, `backoff` and `role` already use, plus a two-token look-behind.
  - `on`: kept only before an upper-case name (`on Msg(…)`).
  - `loop`: kept only before `do` or a name (a protocol loop).
  - `by`: kept only before a name or `do` (`choose by C:`, `assert P by lemma(…)`,
    `by do`). A proof hint is a lemma call or a `do` block (lemmas.md), so `by(…)` is a call.
  - `opaque`: kept only before `type`, or inside `@[ … ]`.
  - `loop do` / `by do` directly after `if` or `match` read the word as the condition.
- `lib/lexer/lexer.mll`: `FLOAT` accepts `([eE][+-]?digit+)?` after the fraction.
- The parser grammar is unchanged.

Evidence: all 2,466 tracked `.march` files produce a byte-identical AST (marshalled digest)
before and after, so no existing keyword use changed meaning. The refinement checker reflects
exponent literals (`_ > 1.0e-12` proves `tiny(1.0)` and rejects `tiny(1.0e-13)`).

Tests: `test/test_compiler.ml` group `soft_keyword_names`.
- All four words as names, typechecked and evaluated.
- The keyword forms still parsing.
- Float exponent values.
The first and third fail with the fix reverted.

Tree-sitter: `loop` removed from the grammar's reserved words, `float` takes an exponent,
and new corpus cases were added. `scripts/check-tree-sitter.sh` is green.

Spec: surface-syntax.md ("Reserved soft-keyword imbalance") and grammar.md (keywords, FLOAT).
