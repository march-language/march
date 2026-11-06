`[P2]` Diagnostics: show `cap_grant` beside other errors (one-turn metric follow-up)

Filed and done 2026-11-05, from the one-turn re-measurement in
`specs/progress/2026-11-02-diag-one-turn-metric.md`.

`Errors.suppress_cascades` (`lib/errors/errors.ml`) dropped `cap_grant` and `cap_root_broad`
whenever any non-capability error existed (§X3: "the grant is computed from a program that does
not typecheck yet"). In practice the computed grant was right, and hiding it cost a second turn on
every program that also forgot the grant: 27 of the metric's 105 failures, and every
`missing_impl` case. Now only `cap_root_broad` (advice) is dropped. `cap_grant` is kept, and
`Errors.sorted` puts it after every other error, so the reader meets the real mistake first.

The corpus's fix check (`test/run_errors.ml`, `check_fix_fixes`) required every case's fixes to
reach exit 0, which a program with a fix-less error beside `cap_grant` cannot. It now also passes
when the errors left after applying the fixes are all ones that offered no fix
(`fixes_did_their_part`): each fix cleared what it was about and broke nothing. `missing_impl_2`
and `_3` lost their `EXPECT-FIX-PARTIAL` markers, since their fixes now compile.

Corpus: 67 `.expected` files gain the `cap_grant` error and fix (four reorder an existing one).
One-turn metric on those 67: 4/67 → 64/67 fixed; overall 286/391 → 346/391.
