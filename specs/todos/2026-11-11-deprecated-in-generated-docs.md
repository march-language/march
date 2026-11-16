`[P2]` Show a function's `@[deprecated("...")]` message in the generated API reference.

Package B1 (`specs/progress/2026-11-11-deprecated-attribute.md`) asked for the stdlib docs and
`forge doc` to show the message on the item. That is not a change in this repository: the
generator is the `march_doc` package, which `forge doc` and `scripts/gen-stdlib-docs.sh` fetch
and run (`forge/lib/cmd_doc.ml`), and it builds each item from the function's `doc` string.

What it needs:

- `march_doc` reads the attribute. The message is in the AST as
  `fn_attr_args = ["deprecated", [ELit (LitString msg)]]` (`Ast.deprecation_of_fn`), and
  `--dump-ast`/`lib/dump/ast_json.ml` is the likely source for a generator written in March;
  check that the dump carries `fn_attr_args` and add it if not.
- The page shows "Deprecated: <message>" on the item and marks it in the module's index.
- Check D of `scripts/check-docs.sh` (every public symbol anchored) keeps passing.
- LSP hover (`lsp/lib/analysis.ml`, `doc_map`) could show the same line; completion items
  could set `deprecated`/`CompletionItemTag.Deprecated`.

Related, also not built: `forge fix` rewriting a deprecated call to its replacement. The
message is free text, so that needs a structured form first (for example
`@[deprecated("...", replace: new_name)]`).
