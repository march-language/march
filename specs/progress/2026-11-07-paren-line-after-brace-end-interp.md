# A `(` line after `}`, `end` or an interpolated string is a new statement (2026-11-07)

GitHub #1179. Follow-up to #129 (`8efcc991a`) and #132 (`3ff8c48e2`).

## The bug

Inside a block the token filter swallows newlines, so a `(` that opens a line
reaches menhir right after the previous line's last token. #129 made the filter
retag such a `(` as `LPAREN_STMT` (accepted only by the group/tuple/unit and
parenthesised-pattern rules, never by the call rule `expr_field LPAREN … RPAREN`)
when the previous significant token was an identifier, `)` or `]`; #132 added the
literals via a wider `ends_expression` predicate. The call rule takes any
`expr_field`, and three more `expr_atom` forms end in tokens neither predicate
listed:

| previous line ends in | `expr_atom` | token |
|---|---|---|
| `{ x: 1 }`, `{ r with x: 2 }` | record literal / update | `RBRACE` |
| `do ... end` | block expression | `END` |
| `"n=${n}"` | interpolated string | `INTERP_END` |

So `let r = { x: 1 }`⏎`(r.x + 1)` parsed as `let r = { x: 1 }(r.x + 1)`
(`not_a_function`, `unbound_variable` for `r`, and on a `needs ()`-bounded fn a
spurious `cap_bound`), and `let g = do fn s -> … end`⏎`("discarded")` silently
called `g`, interpreted and compiled.

## The fix

`lib/parser/token_filter.ml`: `ends_expression` now also returns true for
`RBRACE`, `END` and `INTERP_END _`. `is_value_ending` is unchanged (it also
decides whether a paren is a call for the curried-call guard, and a same-line
`{…}(`/`end(` keeps its old classification). `parser.mly` is untouched; menhir's
conflict count is unchanged.

`END` and `RBRACE` close many other constructs (`if`/`match`/local `fn`/`mod`,
record types and patterns). After those a `(` already had to start a new
statement or arm, and `LPAREN_STMT` is accepted at every such position, so the
retag is a no-op there. Verified rather than argued: a throwaway parse-level
differ parsed each of the 2200 `.march` files under `stdlib/ test/ examples/
bench/ specs/ forge/ lsp/ tree-sitter-march/` twice, once with the new filter and
once with a wrapper that turned exactly the new retags back into `LPAREN`, and
compared the ASTs (spans included): 51 retag sites (match arms opening with a
tuple pattern after a `{ … }` body, tuple tails after an `if … end`, …), 0
differing parses. The differ reported a difference on all three issue repros,
so the green is not vacuous.

Tree-sitter needed nothing: its external scanner (`tree-sitter-march/src/scanner.c`)
already emits `_stmt_lparen` for any line-initial `(` where the grammar can start
a statement or arm, whatever the previous token.

## Tests

- `test/test_compiler.ml`, group `module`: record literal, record update,
  interpolated string and do-block cases (RED before the fix: one block
  expression instead of two); controls for `if … end`/local `fn … end` followed by
  a `(` line, a same-line `do … end("x")` call, and tuple-pattern arms after
  `}`/`end`/interpolated-string arm bodies.
- `specs/lang/grammar/parse/p46_paren_stmt_after_brace_end_interp.march`: prints
  `ok` (the pre-fix compiler rejects it with 12 diagnostics).

## Docs

`specs/lang/surface-syntax.md` "Newline-glom" no longer says a `(` line is a call
on the previous expression (its examples were stale since #129), and
`specs/lang/grammar.md` §3.3 documents `LPAREN_STMT` and the token set.
