# `[P3]` `forge refine --infer`'s per-file fallback prints every proposal once per file

Filed 2026-10-29 from the second inference evaluation
(`specs/progress/2026-10-29-refine-infer-evaluation-2.md`).

When the project does not check as one unit, `Cmd_refine.run_infer` runs each project file
as its own entry. But forge puts the whole project on `MARCH_LIB_PATH`, and the compiler
loads every module found there. So each per-file run infers over the WHOLE project, and the
same results are printed once per file.

## Repro

On a copy of `~/code/depot` (v0.3.3, 31 files under `lib/`, one of which,
`lib/forge/cmd_depot.march`, fails `cap_ceiling`, so the unit check fails):

```
forge refine --infer --diff
```

The output has 3585 lines. The 3 metric proposals (`Sqlite.collect_col_names`,
`Sqlite.collect_row_cells`, `Pool.warm_up`) and their `--diff` hunks appear 30 times each.
The output also has 30 copies of the `inferred metrics: 3 proposed, 56 not inferred` block,
with 1686 "no metric inferred" lines and 966 `scc-unsupported` notes. The 966 notes are the
count the 2026-10-21 noise todo quoted, and they are 30 copies of about 32.

Expected: each proposal printed (and, under `--apply`, written) once. Options: run the
fallback on the files that check, as one generated entry; or deduplicate results by
(site, annotation) across the per-file runs.
