# `[P2]` Parser: string-literal spans now cover the literal's full extent

**Status:** Done (2026-08-11).

- [x] **Fix string-literal spans.** A string literal's `ELit(LitString _, span)`
  collapsed to a **single column — the closing quote**. Measured before the
  fix: `"hello"` at column 0 recorded span `6–7`. Integer and other literal
  spans were always correct; this was specific to strings.

  (An earlier note recorded this as covering the *opening* quote, from a
  `"localhost"`-at-col-24 → `24–25` observation. Direct measurement says
  closing, which is also what the mechanism below predicts — the older
  description was imprecise.)

## Mechanism

`lib/lexer/lexer.mll`'s main `token` rule matches only `'"'` and hands off to
a separate `read_string` sub-rule, which recurses once per character or escape.
**Every re-entry into an ocamllex rule resets `lex_start_p` to the current
lexeme**, so by the time the closing quote matched and `STRING` was returned,
`lex_start_p` pointed at that closing quote. Menhir built the literal's span
from it.

## Fix

Record the opening delimiter's position into `string_start_p` on handoff, and
restore `lexbuf.lex_start_p` in the actions that actually produce a token —
`STRING` **and** `INTERP_START`, in **both** `read_string` and
`read_triple_string`. `Token_filter` reads `lex_start_p` immediately after each
lexer call, so patching it in the action is sufficient for the corrected
position to reach the parser.

## Tests

`test/test_compiler.ml`, `ast` group — written test-first, each watched failing
before the fix:

- base case: `"hello"` spans columns 0–7
- escapes: `"a\nb"` spans 6 source columns for a 3-character value
- non-zero start column: the literal in `f("hi")` spans 2–6
- multi-line triple-quoted: start/end line and column across a newline

Full suite green afterwards.

## Notes for future work

- The three consumers that worked around this can be revisited, though
  `forge refactor bundle`'s `split_top_commas` should stay — it guards nesting,
  not just string spans.
- This unblocks the in-sample diagnostic squiggle in the inline parser-probe
  design (`specs/plans/2026-08-09-parsing-and-string-search.md` §8.2), which
  needs to offset a parse-error byte position into a sample literal's extent.
- **Apparatus note found while verifying:** a fresh worktree's
  `_build/default/bin/main.exe` can be served from the shared dune cache at a
  much older revision than HEAD, and `scripts/run-tests.sh` does not refresh
  it. This surfaced as a `cap_ceiling` failure reading
  `unknown option '--no-cap-strict'` for a flag that exists in `bin/main.ml`.
  `dune build --root . bin/main.exe` fixed it with no source change.
