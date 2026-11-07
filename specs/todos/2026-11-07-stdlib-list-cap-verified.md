`[P3]` `List` cannot declare `cap verified` yet: checked as its own entry, two things fail.

Found 2026-11-07 in the `cap verified` pass over List, Option, Result and Math
(`specs/progress/2026-11-07-stdlib-cap-verified-pass.md`). Option, Result and Math now
declare it. In an ordinary program List is already clean: its obligations are 37 proved,
28 trusted (the manifest-admitted lemmas), 0 skipped, 0 violated (`--refine-report-sites=all`
rows in `stdlib/list.march`). But a stdlib module's `cap verified` is enforced by checking the
module as its own entry (`march --check --stdlib-source stdlib/list.march`, the CI
conformance job and the `reflect-stdlib-sweep` "checks clean" case), and there List fails:

1. **`reverse` is ambiguous.** As the entry, `List`'s declarations sit at the top level beside
   `Prelude.reverse` (`stdlib/prelude.march:196`), and the termination graph refuses to choose
   ("a name more than one declaration could denote"). In the stdlib proper `List` is a nested
   module and its own `reverse` wins. Consequences: four lemmas are `invalid_lemma` (L3:
   `reverse_append`, `reverse_reverse`, `take_onto_drop`, `take_onto_append`), six are
   `lemma_unproved` (`len_reverse`, `len_take_onto`, `len_take`, `take_drop`, `take_append`,
   `sum_int_reverse`, `product_int_reverse` and others that reach them), and nine sites are
   `unreflectable-predicate` (the CI conformance skip ceiling counts them). Cause, exactly:
   `Refine_term`'s `own_file_decl` prefers the walked file's own declaration of a shared key
   only when that file is NOT a stdlib file ("Stdlib code still sees both"), and
   `--stdlib-source` registers the entry as a stdlib file (`Typecheck_builtins.stdlib_source_files`,
   which every stdlib loader also fills, so it cannot tell the entry apart). Fix: hand the graph
   builder the entry file (the driver knows it) and apply the own-file rule to it as to a user
   file; the typechecker already resolves the entry's own `reverse`.
2. **A capability error under `cap verified`:** `List.par_map`'s `task_spawn` asks for
   `needs IO.Spawn` (`stdlib/list.march:461`), which `List` does not declare. Decide whether
   `par_map` belongs in `List` (it is the module's only effect) or `List` declares the need.

Done when `stdlib/list.march` declares `cap verified`, checks clean as its own entry, the
`reflect-stdlib-sweep` list of expected verified modules includes it, and the CI conformance
skip ceiling drops by the nine sites.
