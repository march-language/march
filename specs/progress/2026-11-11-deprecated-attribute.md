`@[deprecated("use X instead")]` on functions — DONE (2026-11-11).

Package B1 of `specs/plans/2026-11-11-pre-1.0-execution-plan.md`. `specs/lang/compatibility.md`
promised the attribute and said it was planned.

## What it does

```march
mod Temperature do
  @[deprecated("use `Temperature.to_fahrenheit` instead")]
  fn c_to_f(c : Int) : Int do to_fahrenheit(c) end
  fn to_fahrenheit(c : Int) : Int do c * 9 / 5 + 32 end
end
```

Every reference to `Temperature.c_to_f` from outside `Temperature` gets
``warning: `Temperature.c_to_f` is deprecated: use `Temperature.to_fahrenheit` instead. [deprecated]``
(the message, closed with a full stop if the author left it open).
The exit status does not change. A reference inside the declaring module, or a module nested
in it, does not warn.

## How

- **Parser** (`lib/parser/parser.mly`, `fn_attr`). No new production: `@[name(expr, ...)]`
  already parsed, and its action rejected every payload but `decreases`'s. `deprecated` now
  keeps its payload when it is exactly one string literal, so the message rides in
  `fn_attr_args` like a `decreases` metric (`Ast.deprecation_of_fn` reads it), and the
  formatter prints it back with no change. A bare `@[deprecated]` or a non-string payload is a
  parse error that shows the form. The grammar's conflict count is unchanged (7 before and
  after).
- **On a type or a module** the attribute is rejected with a message that says it marks
  functions only (four keyword-only `decl` rules, like the `doc`-on-a-type rules). Before,
  any attribute above a `type` or `mod` produced "This `mod` has no matching `end`" pointing
  at line 1. Supporting them is `specs/todos/2026-11-11-deprecated-attribute-on-types-and-modules.md`.
- **Parse-error position** (`lib/parser/parse.ml`). A production that rejects something it
  has already parsed raises with that construct's position, which is on a line above the
  lookahead. The block-balance refinement is evidence about the lookahead, and it was applied
  anyway: with a declaration keyword next, the caret moved to the enclosing `mod` and the
  note said "I only noticed at `fn`". It is now skipped when the error's line is above the
  lookahead's. The errors corpus did not move.
- **Typechecker** (`lib/typecheck/typecheck.ml`). The `DMod` export step records each
  deprecated function as (exported scheme, module span, message) in `env.deprecated_fns`.
  `EVar` resolution calls `warn_if_deprecated`: it warns when the resolved scheme is
  physically one of those and the reference's span is outside the module's. Matching the
  scheme, not the spelled name, is what makes a `use`d or aliased name warn and keeps a
  user's own function of the same name quiet. It is the mechanism `@[stdlib_internal]`
  already uses. One warning per span, since an expression can be inferred twice.
- **Codes.** `deprecated` in `lib/errors/code.ml` (category PROGRAM); `"deprecated"` added to
  the known function attributes in `lib/refinecheck/refine_check.ml`, or every use would also
  draw `unknown_attribute`.
- **LSP** (`lsp/lib/analysis.ml`). The diagnostic carries `DiagnosticTag.Deprecated`, so an
  editor strikes the name through.
- **Tree-sitter.** `attribute` already took an expression list, so `grammar.js` needed no
  rule change; a corpus case in `tree-sitter-march/test/corpus/grammar_sync.txt` pins it.

## Tests

- `test/test_deprecated.ml` (suite `compiler`, group `deprecated`): the payload in the AST,
  after a `doc` and beside another attribute; the two parse errors; another attribute still
  refusing a string; the formatter round trip; one warning with the message at a qualified
  call; none inside the declaring module or a module nested in it; one per use; a value
  reference; a pipe; an imported name (warned at the call, not the import); an alias and a wildcard import; a user
  function of the same name.
- `test/errors/deprecated_1.march` (from `specs/lang/errors/deprecated.md`) and
  `deprecated_2.march`: rendered text, exit 0, and the code in `--check-json`;
  `parse_error_19`/`parse_error_20`: the bare attribute and the attribute on a type.
- `lsp/test/test_lsp_analysis.ml`: the tag, on that diagnostic only.

## Not done

- Types and modules: `specs/todos/2026-11-11-deprecated-attribute-on-types-and-modules.md`.
- The message in the generated API reference, and `forge fix` applying the replacement:
  `specs/todos/2026-11-11-deprecated-in-generated-docs.md`.
- A deprecated function declared at a file's top level outside any `mod` is not recorded;
  it has no other module to be used from.
