`[P1]` `else not p(n) end` parses as two block statements, `not` and `p(n)`, and returns `p(n)`.

Found while pinning probe r1 of `specs/2026-10-29-refinement-reflection-design.md` (§0.12;
`test/refine/reflect/r1_dom1.march`, and `--reflect-report` reports `p` as
`no R7:names not as a value`).

- `fn p(n : {Int | _ >= 0}) : Bool do if n >= 0 do true else not p(n) end end`: the `--emit-core-ast`
  of the else branch is `EBlock [EVar not; EApp (p, [n])]`. The branch's value is `p(n)`, not
  `not p(n)`, and the program typechecks with no diagnostic (the bare `not` is a discarded value).
- In expression position `not (n > 0)` is the `EApp (EVar not, [...])` of `parser.mly`'s `not`
  production, so the split happens only where a block body starts (after `else`, a match arm, `do`).
- The probe's measured certificate (`cert=metric`) is still right for the program as parsed; only its
  meaning differs from what was written. Writing `not(p(n))` gives the intended program.
- Fix in the parser / token filter (and `tree-sitter-march/grammar.js`), or at least warn on a bare
  function name as a non-final block statement.

## 2026-11-09: fixed in the token filter

It was wider than a block start: `let b = not p(n)` also split, binding the function `not`
(caught only because the types then disagreed). `not` is an ordinary name, and two adjacent
expressions on one line are two block statements.

`Token_filter.make` now promotes `not` to `BANG` when the next token can start an operand but
can never follow a name in an expression (a name, a literal or `!`; the `elif` test,
`starts_condition`), so `not p(n)`, `not x`, `not true` and `not not x` are the prefix `!`.
`not(x)`, `fn not(…)`, `not` before `,` or `)` and `not` at a line end keep the name, so a
user-defined `not` still shadows the builtin (`test/native/shadowed_negate_not`). `BANG` builds
the same `EApp (EVar "not", …)` as a call. Precedence is `!`'s: `not a == b` is `(!a) == b`.

No `parser.mly` / `lexer.mll` change, so the tree-sitter grammar is not touched: tree-sitter reads
`not p(n)` as two expressions, which is no ERROR node, only a different tree.

Pinned by `specs/lang/grammar/parse/p47_not_prefix_operand.march` (rejected by `--check` under the
old reading) and the codegen parity test "`not p(n)` at a block start is `!p(n)`".
