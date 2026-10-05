# Parse errors: keep the grammar's position, and one parse entry point (D0)

**Date:** 2026-10-05
**Plan:** `specs/plans/diagnostics-and-triage-plan.md` §4 (D0).

## 1. The chosen position was discarded

`lib/parser/parser.mly`'s `error`-token productions raise
`Errors.ParseError (msg, hint, pos)` with a deliberately chosen `pos`
(`$startpos($N)`: the `then`, the token where `end` was expected, ...). The CLI
and the REPL caught it as `ParseError (msg, hint, _)` and rendered through
`Errors.parse_error_diagnostic ... lexbuf`, whose span is
`Lexing.lexeme_start_p lexbuf`: menhir's lookahead token, the token AFTER the
one the message is about. `march fmt` and the REPL's desugar-error path were
worse: they rendered against a *fresh* lexbuf, so the caret sat at line 1,
column 0. The LSP kept the position and was already right.

Fix: `Errors.parse_error_diagnostic_at` / `render_parse_error_at` take the
exception's `Lexing.position` (and `?src`, used by `token_len_at` to size the
caret to the identifier/keyword at that position; located by line/column, not
`pos_cnum`, since desugar- and supervise-built positions carry no absolute
offset). Every `ParseError` catch site uses it; the lexbuf form remains only
for `Parser.Error`, which carries no position.

Before / after, `specs/lang/grammar/reject/r01_then_keyword_rejected.march`:

```
6 |     else                    4 |     if true then
        ^^^^                                    ^^^^
```

Also moved: `let? x : Int = ...` / `let* x : Int = ...` (caret now on the `:`
the message rejects, not on the following line).

Guard: `test/test_compiler.ml` "parse caret: ..." pins line, column and end
column, plus the rendered caret line, for the `then`, `else if`-missing-`end`
and `mod`-missing-`do` productions. Before this only message substrings were
asserted, which is why the bug survived.
