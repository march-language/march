# Formatter keeps the parentheses the grammar needs (2026-11-07)

GitHub issue #1175. Landed with #1174
(`specs/progress/2026-11-07-formatter-no-placeholder-text.md`), which also adds the round-trip
check that would have refused every output below.

## The bug

The parser drops parentheses (`LPAREN e RPAREN` yields `e`), so the formatter must work out
where they go. It only did so between binary infix operators (`expr_infix_prec`, which returns
`None` for anything else). The `negate` / `not` cases and the call case had the same gap. The
left-operand test `pa < p` also treated comparisons as left-associative, though they are
non-associative.

| Input | Old output |
| --- | --- |
| `1 + (if x > 0 do 1 else 0 end)` | `1 + if ...`: does not parse |
| `1 + (3 \|> double)` | `1 + 3 \|> double`: a different program (7 became 8) |
| `(if c do f else g end)(5)` | `if ... end(5)`: a different program |
| `(fn y -> y)(1)`, `-(if ...)`, `!(if ...)` | parens dropped |
| `(a == b) == c` | `a == b == c`: does not parse |
| `(mk(x)).y`, `(make(1))(2)` | `mk(x).y`: does not parse |
| `-(-x)` | `--x`: lexes as a comment |

## What changed

Binding levels follow the grammar's layering in `lib/parser/parser.mly`. `lv_expr` (`if`,
`match`, `match do`, `fn`, `assert`) < `lv_pipe` < `||` < `&&` < comparison < additive <
multiplicative < `lv_unary` < `lv_app` (a call or constructor application) < `lv_atom` (what a
callee or a field base must be). `level_of e` is the level `e` prints at. `render ind lvl e`
wraps `e` in parentheses when `level_of e < lvl`. The positions:

- a binary operator: the left operand needs at least the operator's level and the right operand
  more than it. Both operands of a comparison need more than the comparison level, since a
  comparison is non-associative;
- `|>`: the head needs `lv_pipe` and the stage `lv_or`, the same in the multi-line pipe chain;
- `-e` / `!e`: the operand needs `lv_unary`. An operand whose text starts with `-` is wrapped,
  so `-(-x)` is never printed as `--x`;
- a callee or field base needs `lv_atom`, so a call or constructor application there is
  wrapped. A bare constructor callee is wrapped too, or `(Foo)(x)` would come back as
  `Foo(x)`;
- `if` condition, `match` subject, guards, cond-arm conditions and the `with` base of a record
  update need `lv_pipe`. The parens are not required there, but they are always safe;
- call arguments, list, tuple and record elements, `let` right-hand sides, lambda bodies and
  interpolations take any `expr`.

## Evidence

`test/test_fmt.ml` group "issue 1175 shapes" (21 cases, each run through `check_roundtrip`, which
requires the same AST after a re-parse) and `test_semantic_parens_kept`, which pins
`1 + (3 |> double)` and `(if x > 0 do add1 else add1 end)(5)` as text. Before the fix, 18 of
the 21 cases failed.
