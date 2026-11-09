# Formatter: no placeholder text, and a round-trip check before writing (2026-11-07)

GitHub issue #1174. The companion paren fix (#1175) is
`specs/progress/2026-11-07-formatter-keeps-needed-parens.md`; both landed in one commit.

## The bug

`march fmt` / `forge format` wrote `...`, `match ...` or `match do ... end` over valid code.
`expr_inline` (lib/format/format.ml), the single-line renderer, returned those strings for a
multi-statement block, a `match` and a subject-less `match do`. It was reached whenever a
container did not know its content needed several lines: `is_multiline` had no `ECond` case and
looked only through a call's trailing lambda, never into list or tuple elements, record fields,
non-last call arguments, operands, `if` branches or interpolations. `emit_stmt` had no `ECond`
case at all. The old regression helper only searched for `-> ...`.

## What changed

- **One renderer, no placeholders.** `render ind lvl e` prints every construct in full. A
  construct that needs several lines (`match`, `match do`, a statement or a block of them) is
  emitted by the existing block emitters into a scratch buffer at the current indentation
  (`sub_block`), and the text, with absolute indentation on its continuation lines, goes into
  the enclosing line. A statement form in an expression position is printed as `do ... end`.
  `expr_inline` (still used by `lib/refinecheck/infer_lemma.ml`) is `render 0 lv_expr`.
- **`needs_break`** is the structural "must be multi-line" test, and it looks inside every child
  (`children`), so all containers agree with the renderer. `is_multiline` is `needs_break` plus
  the old sigil and trailing-lambda shapes, which keeps existing layouts unchanged.
- **`emit_cond`** prints `match do cond -> body ... end`, and `emit_stmt` has an `ECond` case.
- **Lambda bodies.** A multi-statement body uses `fn x -> do ... end` except as a call's trailing
  lambda (the existing hanging form). A statement-level `fn x ->` continuing on the next lines is
  kept only when the body is `let`s and a final expression (`lets_only_body`). Outside a call
  argument, `lambda_body` accepts only that, so a bare statement there used to end the lambda
  and change the program.
- **A nested block keeps its scope.** `emit_stmt (EBlock ...)` prints `do ... end` and no longer
  splices the statements into the enclosing block. A `let x =` whose right-hand side is a block
  is printed `let x = do ... end`. It used to come out as `let x =` followed by the statements,
  which binds only the first one.
- **`plain_call`** separates a real call from an operator application or a list literal. The
  trailing-lambda layout walked into `a + f(fn ...)` and printed `+(a, f(fn ...`.

## The safety net

`Format.equal_modulo_spans` compares two parsed values and ignores spans. It walks the
representation and treats any 5-field block with a string and four ints as a span.
`Format.verify_format ~filename ~src formatted` re-parses the output and compares it with the
input. `format_source_checked` is the two steps together.

- `march fmt` (`fmt_file` / `run_fmt` in `bin/main.ml`): a file that fails the check is left
  unchanged. The command prints `not formatted: <why>. This is a formatter bug`, goes on to the
  other files, and exits 1. `--check` reports it the same way. `--fmt` before a compile exits 1.
  `--stdin` echoes the input and exits 1.
- `forge format` runs `march fmt` for files. `forge format --stdin` echoes the input and returns
  an error.
- The language server's `textDocument/formatting` and `march query format` return no edit, or
  the input, when the check fails. Format-on-save is the path most likely to destroy code without
  anyone noticing.

The check found more bugs in the stdlib sweep, all fixed here:

- strings: `String.escaped` wrote UTF-8 bytes as `\226`, which the lexer rejects, and left `${`
  alone, which re-lexed as an interpolation. `escape_string` follows the lexer's escapes.
  Triple-quoted output escapes `${` and is not used for content with `"""`, `\$`, a trailing
  quote or `\r` (the lexer reads `\r\n` as one newline);
- `resource Name` was printed `type Name = `;
- `opaque type` / `always_linear opaque type` were printed without `opaque`, which made the
  constructors public;
- `blocking` / `raises` extern functions lost the modifier;
- `linear let x` was printed `let linear x`;
- `p as a as b` needs `(p as a) as b`;
- an interface's superclasses are written after `requires`, not `when`;
- float literals: `string_of_float` keeps 12 significant digits. Now the shortest `%g` that
  reads back as the same float;
- default arguments were printed `\\ _`;
- `use A` (`UseSingle`, the module name only) was printed `import A` (`UseAll`);
- a multi-line sigil's content was re-indented (common indentation stripped, the first newline
  and the trailing blanks dropped), which changed the string the sigil receives. It is now
  printed exactly as written.

Still refused, not fixed: `actor` declarations, whose `supervise`, `mailbox`, `@compat`,
`@invariant` and `@[remote]` parts the formatter does not print
(`specs/todos/2026-11-07-formatter-actor-decl-round-trip.md`). Before the check they were
deleted silently.

## Evidence

- `test/test_fmt.ml`: the groups "issue 1174 shapes" (17 cases) and "round-trip safety". Each
  case checks that the output parses, has no `...`, parses to the same AST as the input, and is
  idempotent (`check_roundtrip`). `check_no_ellipsis_placeholder` now searches for any `...`.
  Before the fix, 39 of the 42 new cases failed. The three that passed were shapes the old
  code already got right: `x |> h(1, (y |> g))`, `a == (b == c)` and `a - (b - c)`.
- "round-trip sweep shapes" (10 cases) pins the string and declaration fixes.
- Sweep over copies of the stdlib: the formatter at bf7307f23, measured with the new check,
  broke 47 of 137 files (43 outputs did not parse, 4 parsed to a different program). With
  this change all 137 format, pass the check, and are idempotent.
- The same sweep over copies of `test/**/*.march` (1316 files): 1233 format cleanly, 33 are
  deliberately unparseable inputs (the `test/errors` syntax cases and two fragments), and 50
  are refused, every one of them because of an `actor` declaration (the todo above).
