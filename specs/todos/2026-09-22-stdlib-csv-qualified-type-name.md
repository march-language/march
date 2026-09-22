# `[P2]` csv.march: qualified `Csv.CsvRow` does not unify with the bare `CsvRow` its patterns produce

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
