# Native regression tests for the 2026-08-20 ambiguous-ctor fix (+ a since-reverted Float attempt)

Adds `test/native/` compiled-only coverage for the ambiguous module-qualified
ctor construction/pattern key mismatch fixed on `claude/sleepy-benz-9aaadf`
(originally landed as part of `5ec5b1a6` alongside a Boxed-ADT Float field
attempt that was **reverted mid-review** — see below), which landed without
regression tests of their own.

## Ambiguous-ctor construction vs. pattern key mismatch (still fixed, tested)

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

## Boxed-ADT Float field boxing — attempt reverted, NOT what shipped

The original `5ec5b1a6` also shipped a fix for `record_put`/`record_get`
SIGSEGVing on a Float field (see
`specs/todos/2026-08-20-record-put-get-float-niche-segfault.md`), by boxing
every `TFloat` ctor field behind a `march_alloc_float` box+`ptr` slot. That
approach was **reverted** on `claude/sleepy-benz-9aaadf` (commit
`b37e9301`/`e5a5e125`) after it regressed 6 pre-existing native goldens
(`float_generic_field_abi`, `record_pattern`, `native_arr_map2_inline`,
`native_arr_map_inline_capture`, `native_arr_map_inline_float_box_reuse`,
`native_arr_map_inline_unboxed`) — boxing is only correct for a *generic*
(`TVar`) field; a *concrete monomorphic* `TFloat` field is meant to stay an
inline `double`, and forcing `ptr` everywhere corrupted every inline path.
The `record_put`/`record_get` Float SIGSEGV itself is **still open**
(re-filed back to `specs/todos/`) — a different, narrower fix is needed.

While independently chasing the same regression (before discovering the
other branch had already reverted it), this PR's author found and verified
one more site the reverted attempt had missed: `lib/tir/llvm_emit.ml`'s
closure free-variable (`$fvN`) load path used a direct native-typed load
(`llvm_ty v.Tir.v_ty`) that assumed unboxed storage, while closure structs
are materialized through the same `ctor_field_llty`-boxed construction path
as any other ctor — so a closure capturing a concrete `Float` free variable
read back a heap pointer's bit pattern as a double. That finding is now moot
(the whole boxing approach was reverted rather than patched site-by-site),
but is recorded here in case a future fix attempt reintroduces the same
`TVar`-vs-concrete distinction bug: **the missing site was the closure
`$fvN` peephole load in `emit_expr`'s `ELet` case, not covered by the fix's
original three sites** (`runtime/march_extras.c` `rec_box_some_float`,
`lib/tir/llvm_eq.ml` `field_load_llty`, `lib/tir/llvm_case.ml` branch
extraction).

Two fixtures from the original plan survive and stay in this PR because
they never actually depended on which convention (boxed vs. inline) is in
effect — construction, extraction, and the derived-Eq comparator for a
multi-ctor ADT's `Float` field agree with each other under EITHER
convention, so they're kept as a plain consistency guard:

- `test/native/boxed_adt_float_field.march` — depot's `SqlValue.PFloat`
  shape: a multi-ctor ADT's Float field survives `derive Eq` equality and
  match-extract + `float_to_string`.
- `test/native/boxed_adt_atom_field_not_boxed.march` — negative control for
  the *specific* over-broad-fix hazard the original attempt's own commit
  message called out (reusing `Llvm_eq.field_load_llty`'s `_ -> ptr`
  catch-all at ctor-construction sites, which also remaps `Atom` fields and
  would break `List.any(allowed, fn a -> a == m)` over `List(Atom)` —
  bastion's `Middleware.allow_methods`). Verified this fixture catches that
  regression by temporarily reintroducing it.

The two fixtures that DID depend on the (reverted) boxed convention —
`record_float_niche_typed.march` (typed `Option(Float)` round-trip through
`record_put`/`record_get`) and `record_float_niche_eq.march` (same, via
`==`) — were removed from this PR: they fail against the current branch tip
because the bug they exercised is genuinely still open, not fixed. Re-add
them once `specs/todos/2026-08-20-record-put-get-float-niche-segfault.md`
lands a real fix.

## Verification

All 3 surviving fixtures compile and run correctly at both `--opt 0` and the
default `--opt 2`. Full `dune runtest` (which — unlike `scripts/run-tests.sh`
— actually exercises the `test/native/` dune-rule goldens; see the todo file
above for why that distinction mattered here) and `scripts/run-tests.sh` are
both green against the merged branch tip. TIR snapshots unchanged (no
lowering/Perceus shape was touched — test-only change).

Two dune rule pairs per fixture (default opt level + explicit `--opt 0`),
following `test/native/xmod_ctor_collision`'s two-rule
(compile-and-run / diff) pattern and `test/native/lazy_niche`'s
`(source_tree ../stdlib)` dependency for lazily-loaded stdlib modules.
