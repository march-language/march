# Laws across files: interface laws and LSP rewrites (2026-11-03)

The rest of ideas 5 and 6 in `specs/todos/2026-11-02-lemma-uses-beyond-refinement.md`.

## Interface laws

- **Impls in other files.** Each file is desugared alone, so an impl never saw an
  interface declared elsewhere. `Interface_laws.expand_program` runs where a driver joins
  the program: `bin/main.ml`'s two `extra_decls @ mod_decls` sites and its multi-file
  `all_decls`, plus the LSP analysis (`~context:extra_decls`). It skips an impl the
  per-file step already expanded (its first law's lemma is a sibling).
- **Default methods.** A method the impl takes from the interface's default (an impl in
  another file never had `inject_defaults` add it) gets its copy from the default's lambda.
- **`Unit` arguments.** A method whose signature takes `Unit` (`fn unit : Unit -> a`) gets a
  copy without that parameter, and every call of the copy drops the matching argument
  (`drop_unit_args`), so `combine(unit(()), x) == x` proves: the logic has no `Unit`.
- `rename` is now `map_expr` (bottom-up) with a variable case.

Tests (`reflect-lemma`): `iface_law_cross_file`, `iface_law_default_unit` (same file and
another file).

## LSP rewrites (`lsp/lib/lemma_rewrite.ml`)

- Rules come from the open file, the project files it imports (`depot_source_decls`
  outside the file), and the stdlib (`Stdlib_cache.load`).
- Status: the first two through `Refine_diag.lemma_admitted`, the stdlib's through
  `stdlib/lemmas.verified` (reflection phase 3's manifest): a listed `Mod.name` is
  admitted.
- A rule keeps its file's text (`l_src`) for matching and for the replacement. A rule from
  another module has that module's functions qualified in its right side, so
  `Lst.rev(Lst.cat(a, b))` becomes `Lst.cat(Lst.rev(b), Lst.rev(a))`.

Tests (`lsp/test/test_lsp_refine.ml`): `lsp_lemma_rewrite_imported` (a forge project's
`lib/`), `lsp_lemma_rewrite_stdlib` (a listed lemma is a rule; an unlisted one is not).

## Found on the way

A default method of a cross-file impl unbound at run time, and `use M.*` read as unused
when only an interface of `M` is used: both fixed in
`specs/progress/2026-11-03-lemma-tooling-bugfixes.md`.
