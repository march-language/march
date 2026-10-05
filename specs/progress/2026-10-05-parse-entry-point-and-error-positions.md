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

## 2. One parse entry point: `March_parser.Parse`

`Token_filter.make Lexer.token` was instantiated inline at about 120 sites
(about 45 outside `test/`), with about a dozen hand-written
`Parser.Error`/`ParseError`/`Lexer_error` handlers that disagreed on the
"stuck" message, on whether a lexer error was caught at all, and (above) on
where the caret went.

`lib/parser/parse.ml` (+ `.mli`) is now the only place the filter is built and
the only place those exceptions become diagnostics:

- `Parse.module_ / repl_input / repl_sequence / expr : ?filename -> ?stuck ->
  string -> (_, Errors.diagnostic list) result`. One diagnostic per failure,
  coded `parse_error` (a grammar `error` production, span from the exception's
  position, hint as a note), `syntax_error` (menhir's `Parser.Error`, span at
  the lookahead, message `?stuck`, default "I got stuck here:") or `lex_error`
  (`Lexer_error`, one caret where the lexer stopped). D3 of the plan refines
  the codes.
- `Parse.*_of_lexbuf`: the same pipeline over a caller-owned lexbuf, raising.
  For callers that treat every failure alike (`with _ -> None`,
  `Printexc.to_string exn`) and for tests that assert on the raw exception;
  using them kept those ~100 sites a one-line, behaviour-identical change.
- `Parse.tokens ()`: the filtered token stream, for the token-filter tests.

Sites that *report* a syntax error use the result forms: `bin/main.ml`
(compile, multi-file compile, `march test`, doctests, `march fmt` via the new
`Format.format_source_result`), `bin/toolchain.ml` (stdlib loader),
`lib/repl/repl.ml` (`parse_repl_input`), `lsp/lib/analysis.ml`,
`lib/lint/lint.ml`, `lib/resolver/resolver.ml`, `js/march_browser*.ml`.
Message text is unchanged everywhere (each site passes its old "stuck" wording
as `?stuck`); `scripts/types-oracle.sh` against a commit-1 baseline shows
Tier 2 (rendered text) identical.

**Build layout.** `march_lexer` depends on `march_parser` (the lexer needs the
token type), so `Parse` could not call `March_lexer.Lexer`. The lexer is now
compiled *inside* `march_parser` from the unchanged source
`lib/lexer/lexer.mll` (a `sed` in `lib/parser/dune` rewrites its one
`open March_parser.Parser` to `open Parser`), and `lib/lexer/lexer.ml` is
`include March_parser.Lexer`, so `March_lexer.Lexer.token` and
`March_lexer.Lexer.Lexer_error` are the same values as before for every
existing caller.

**`Parse_errors` deleted.** `error_raise` collected *and* raised, so a parse
that returned an AST always had an empty buffer; the "declaration-level parse
errors collected during recovery" loops in `bin/main.ml` never ran on their
own file. (They could run on the *wrong* one: a discovered library file that
failed to parse, and was skipped, left its error in the global buffer for the
next `take_parse_errors`.) `parser.mly`'s prologue lost the two lines that
called it; no production changed.

**Behaviour that did change, all of it previously a crash:**
- A lexer error (`@`, an unterminated string) on the command line was
  `Fatal error: exception Lexer_error(...)` with an OCaml backtrace, exit 2.
  It is now a rendered diagnostic, exit 1. Same for `march test`, `march fmt`
  and the browser playground.
- A lexer error in a file discovered on `MARCH_LIB_PATH` aborted the compile
  with that exception; it is now reported like any other unparsable
  discovered file (`[lib] file:line: parse error: ...`, or the strict
  `--test` error).
- `march fmt`'s "Parse error (cannot format)" caret sat at line 1, column 0
  (it rendered against a fresh lexbuf); it now sits at the offending token.
- The REPL keeps its `lexer error: <msg>` line (its read loop resets the
  input buffer in that handler), so `parse_repl_input` re-raises for
  `lex_error`.

`--emit-core-ast`'s parse-failure document now carries
`"code":"parse_error"` (was `null`); the `t70_letq_type_annotation` golden is
regenerated (in commit 1 for the span, here for the code).

## 3. Parse errors reach `--check-json`; labels and notes in the NDJSON

`march --check-json` printed nothing for a file that did not parse: the parse
path wrote text to stderr and exited before the NDJSON branch. It now also
writes the parse diagnostics to stdout as NDJSON (stderr text and exit 1
unchanged).

`Errors.render_diagnostic_json` gains `"labels":[{file, start_line,
start_col, end_line, end_col, message}]` and `"notes":[...]` after `fix`.
`--emit-core-ast` passes `~related:false` and is byte-identical: that document
is versioned (`format_version`) and read by the external Lean re-checker, so
extending it is a separate decision. `forge fix`
(`forge/lib/cmd_fix.ml:parse_fix_line`) reads fields by name through Yojson
and skips any line whose `fix` is null, so the extra fields and the new
parse-error lines are both ignored by it.
