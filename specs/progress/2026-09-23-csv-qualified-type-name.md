# `[P2]` DONE csv.march: qualified `Csv.CsvRow` does not unify with the bare `CsvRow` its patterns produce

Filed 2026-09-22 from the stdlib internal-error sweep
(`2026-09-22-stdlib-internal-type-errors.md`). 12 errors in `stdlib/csv.march`
(:33-:35, :65-:67, :89-:91, :108-:109, :113), all of the shape
"expected `Csv.CsvRow` but got `CsvRow`" and its mirror image.

`stdlib/csv.march:29` declares `ptype CsvRow = CsvEof | Row(List(String))`, and
the `csv_next_row` builtin is typed with the QUALIFIED name, so matching its
result against the bare constructors fails in both directions. March
canonicalizes qualified type names to bare ones in `surface_ty`'s `canon_name`,
so the interesting question is which route skips that — the builtin signature
table, most likely. Fix the canonicalization rather than the spelling if the
builtin table is the odd one out; a spelling fix here would leave the same trap
for the next builtin typed with a qualified name.

## Resolution (2026-09-23)

Root cause as suspected: `surface_ty` canonicalizes `Mod.T` to the bare `T`
when `T` is a same-arity type in scope, but builtin signatures are hand-built
`ty` values bound in `base_env` (before `Csv.CsvRow` exists), so they never went
through it.

- `Typecheck_env.canon_type_name` is now the single qualified->bare rule;
  `surface_ty` calls it, and `canon_qualified_tcons` applies it over a whole
  type.
- `Typecheck_builtins.qualified_type_builtins` is COMPUTED from
  `builtin_bindings` (every builtin whose signature mentions a dotted `TCon`),
  so a future builtin typed with a qualified name is covered with no list to
  maintain. Today it holds only `csv_next_row`; a grep of the table found no
  other qualified type name.
- `infer_expr`'s `EVar` arm canonicalizes the instantiated type of such a
  builtin (physical-equality check against the table's scheme, so a user
  binding that shadows the builtin is untouched).

The TIR half. The qualified spelling was put in the table on purpose
(b413fe7a4): the TIR registers stdlib types qualified, and `csv_next_row`'s C
implementation returns a NICHE-encoded value (raw NULL for `CsvEof`), so the
compiled match must see `Csv.CsvRow` to find the niche-shaped typedef. That
only ever worked because the type error was filtered and the call kept its
qualified type in the type_map. With the typechecker now bare, a first cut
SIGSEGVed `test/native/csv_niche_row.march`. `Lower_state.ty_of_expr` now gives
a call to a `qualified_type_builtins` builtin the table's qualified return type
when the type_map agrees up to qualification, so the TIR is byte-identical to
before (checked with `--dump-tir` on the csv_niche_row program).

Regression test: `test_qualified_builtin_type_unifies_bare` in
test/test_compiler.ml (fails on the pre-fix compiler). The ratchet's csv row is
gone.
