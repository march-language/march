# `DataFrame.col_z_score` and `col_normalize` panic on a zero-row column

Logged 2026-09-16.

`col_describe_column` was guarded against zero-row frames on 2026-09-16
(`specs/progress/2026-09-16-dataframe-col-describe-zero-rows.md`). The two
remaining unguarded `Stats.*` call sites in `stdlib/dataframe.march` have the
same shape and the same latent panic:

- `col_z_score`: `Stats.mean` / `Stats.std_dev` on the materialised column
  (both the `FloatCol` and `IntCol` arms);
- `col_normalize`: `Stats.min_val` / `Stats.max_val` (both arms).

Both return `Result(Column, String)`, so unlike `col_describe` they have a
natural way to report the empty case — `Err("...: column is empty")` — or they
could return the zero-length column unchanged, which is arguably more useful
(normalising nothing yields nothing). Decide which before implementing.

These are exactly the six `unconstrained-subject` skips that survive in
`march --check --refine-report stdlib/dataframe.march` after the `col_describe`
fix. A guard on the list actually passed to `Stats.*` should discharge them, as
it did for `col_describe_column`.

Separately: `Stats.median`, `Stats.mean` and their siblings may want declared
contracts on their own wrappers so callers inherit the obligation rather than
re-proving it at every site. Not required for the above, but it is the general
fix for this family.
