# `[P2]` Parser: string-literal spans cover only the opening quote

- [ ] **Fix `EString` spans to cover the literal's full extent.** A string
  literal beginning at column 24 records span 24–25 — just the opening `"` —
  so slicing source text by a string-bearing expression's span yields a bare
  quote character. Integer and other literal spans are correct; this is
  specific to strings. Mechanism: the main `token` rule in
  `lib/lexer/lexer.mll` matches only `'"'` (line ~121) and hands off to the
  separate `read_string` entry (~205); each recursive call into that entry
  resets `lexeme_start_p`, so the opening quote's position is lost by the time
  the `STRING` token is produced. Fix shape: capture the start position before
  entering `read_string` and patch `lexbuf.lex_start_p` back when the token is
  returned (same for `read_string_interp` and triple-quoted forms).

  Three consumers have independently worked around it instead of fixing it:

  1. `forge refactor bundle` (`lib/refactor/refactor.ml`) — call-site arg
     rewriting produced corrupted `a = "` output; worked around with a
     string-aware top-level-comma splitter that avoids trusting spans.
  2. Diagnostics pointing at string literals underline only the quote.
  3. **Blocks** the in-sample diagnostic squiggle of the inline parser-probe
     design — `specs/plans/2026-08-09-parsing-and-string-search.md` §8.2 —
     which needs to offset a `ParseErr` byte position into the sample
     literal's extent and currently has nothing correct to offset from.

  After fixing, audit for workarounds that can be simplified (the refactor
  splitter can stay — it guards nesting too), and check golden/LSP tests that
  may have baked in the 1-wide span.
