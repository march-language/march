# Native regression tests for the 2026-08-20 Boxed-ADT Float / ambiguous-ctor fix

Adds `test/native/` compiled-only coverage for the two bug clusters fixed in
`5ec5b1a6` (see
`specs/progress/2026-08-20-record-put-get-float-niche-segfault.md`), which
landed without regression tests of their own. Both clusters were
compiled-only miscompiles (interpreter was always correct), found by running
the downstream package corpus against `origin/main`.

## Boxed-ADT Float field boxing

- `test/native/record_float_niche_typed.march` — `record_put`/`record_get`
  round-trip through a statically **typed** `Option(Float)` annotation
  (`record_get`'s call-site `expected_kind` threads 'f' through
  `lib/tir/llvm_emit.ml`, giving `runtime/march_extras.c`'s
  `rec_box_some_float` a concrete boxed shape to produce). SIGSEGVs pre-fix
  (verified against the parent commit) at both `--opt 0` and the default
  `--opt 2`.
- `test/native/record_float_niche_eq.march` — same shape via `==`
  (`Some(0.0) == record_get(...)`); returns `false` pre-fix instead of
  crashing (the `--opt` level didn't matter for this shape).
- `test/native/boxed_adt_float_field.march` — depot's `SqlValue.PFloat`
  shape: a multi-ctor ADT's Float field survives `derive Eq` equality and
  match-extract + `float_to_string`. Note: this fixture does NOT distinguish
  pre/post-fix in isolation — pre-fix, ctor construction
  (`lib/tir/llvm_emit.ml`), extraction (`lib/tir/llvm_case.ml`), and the
  derived-Eq comparator (`lib/tir/llvm_eq.ml`) all agreed on the *old*
  "raw double" convention, so a fully self-contained compile never exercised
  the inter-module inconsistency depot hit. Kept anyway as a convention
  guard: a future edit that re-diverges any one of those three sites from
  the other two will break this test immediately (verified by temporarily
  aliasing `ctor_field_llty` to `Llvm_eq.field_load_llty`, which is *also*
  exactly the over-broad draft the negative control below guards against).
- `test/native/boxed_adt_atom_field_not_boxed.march` — negative control.
  An earlier draft of the fix reused `Llvm_eq.field_load_llty`'s `_ -> ptr`
  catch-all at ctor-construction sites, which also remapped `Atom` fields
  and broke `List.any(allowed, fn a -> a == m)` over `List(Atom)` (bastion's
  `Middleware.allow_methods`). Verified this fixture actually catches that
  regression: temporarily made `ctor_field_llty` alias
  `Llvm_eq.field_load_llty` and confirmed the fixture's first line flips to
  `false`.

## Ambiguous-ctor construction vs. pattern key mismatch

- `test/native/qctor_collision/` (multi-file, `MARCH_LIB_PATH`) — a public,
  impl-bearing (`derive Eq`) `SortDir` type whose short name and `Asc`/`Desc`
  ctors collide with stdlib `DataFrame.SortDir`. One module constructs
  `QcTypes.Asc` with a written module qualifier from outside the declaring
  module; another matches `QcTypes.Asc`/`QcTypes.Desc`; the entry module
  references `DataFrame.from_columns` purely to pull DataFrame's `SortDir`
  into the whole-program build (DataFrame is otherwise lazily loaded and
  never reaches `Lower_state.compute_shared_ctor_collisions`). Verified
  against the parent commit's `lib/tir/lower.ml`: pre-fix, both `Asc` and
  `Desc` matches fall through to `matched-other` (the "non-exhaustive
  pattern match" symptom's non-panicking cousin, since this fixture has a
  wildcard default arm) instead of `matched-asc`/`matched-desc`.

## Verification

All five fixtures compile and run correctly at both `--opt 0` and the
default `--opt 2`; `scripts/run-tests.sh` is green; TIR snapshots unchanged
(no lowering/Perceus shape was touched — test-only change).

Two dune rule pairs per fixture (default opt level + explicit `--opt 0`),
following `test/native/xmod_ctor_collision`'s two-rule
(compile-and-run / diff) pattern and `test/native/lazy_niche`'s
`(source_tree ../stdlib)` dependency for lazily-loaded stdlib modules.
