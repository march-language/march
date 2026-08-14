# Compiled NativeArray.fold for all five element widths

**Filed and closed:** 2026-08-13 (Task 2 of the SIMD follow-ups plan,
`.superpowers/sdd/2026-08-13-simd-followups/`).

## Problem

`NativeArray.fold_int`/`fold_float` typechecked and evaluated interpreted,
but had no C runtime symbol — a compiled program calling either failed to
link. `fold_f32`/`fold_i32`/`fold_u8` didn't exist at all.

## Fix

Five C functions in `runtime/march_runtime.c` (`native_int_arr_fold`,
`native_float_arr_fold`, `native_f32_arr_fold`, and `native_i32_arr_fold`/
`native_u8_arr_fold` sharing one body via the pre-existing
`DEF_NARROW_INT_ARR` macro), all `(acc, arr, f)` — the March builtin's
argument order, deliberately the OPPOSITE of the reference
`march_typed_array_fold`'s `(arr, acc, f)` — modelled on that reference's
`call_closure_2`-based RC discipline (`incrc(f)` per element, one `decrc(f)`
after the loop). Element materialisation is the only per-width difference:
i64/i32/u8 wire-tag `(x<<1)|1`; f64/f32 box via `march_alloc_float`.
Registered end-to-end: three new `poly1` typecheck sigs, three new eval
impls, three new `defun.ml` names, five `llvm_builtins.ml` rows
(`ret_ty = Some (Tir.TVar "a")`) + five `PDeclare` + golden-preamble mirror
in `test_codegen.ml`, three new stdlib wrappers in `stdlib/native_array.march`
(mirrored to `share/march/native_array.march`), retiring the "will fail to
link" caveat there and in `docs/simd-vectorization.md`.

New compiled/interpreted parity fixture `test/native/native_arr_fold.march`
uses a non-commutative fold (`fn (acc, x) -> acc * 2 + x`) across all five
widths specifically so a swapped argument order can't hide behind a
commutative operator, plus odd initial accumulators and a negative-element
i32 case (see "Two bugs found during development" below for why those two
details are load-bearing, not just belt-and-suspenders).

## Two bugs found during development, both caught before merge

1. **SIGSEGV on a literal accumulator for the float-family folds.** The
   compiled call-site marshaling that boxes/tags a scalar argument for a
   generic `TVar "a"` parameter is opt-in per `(builtin, param_index)` via
   `Llvm_builtins.builtin_boxed_generic_params_tbl` — previously only
   `ring_buf_push -> [1]`. Without an entry for the new folds' `acc`
   parameter (index 0), a literal accumulator (e.g. `fold_float(arr, 0.0,
   ...)`) reached the runtime as raw double bits instead of a
   `march_alloc_float` box, and `march_unbox_float` dereferenced garbage —
   immediate SIGSEGV. `fold_int` appeared to work by coincidence: `coerce
   ("ptr","i64")` is a *conditional* untag that only shifts odd values, and
   the fixture's original `0` accumulator is even. Fixed by registering all
   five new builtins' `acc` param in that table. The fixture now uses `3`
   (fold_int) and `1` (fold_i32) as odd initial accumulators specifically so
   deleting a table entry produces a wrong number (verified: `fold_int`
   silently returns `19` instead of `35` with the entry removed) instead of
   hiding behind an even-value coincidence.

2. **Per-element memory leak in the float-family folds.** `native_float_arr_fold`
   and `native_f32_arr_fold` allocate a fresh `march_alloc_float` box per
   element and never released it — `~32B/element`, unbounded in loop length
   (measured: isolated element-box leak alone, 6M elements, 243 MB peak RSS;
   50 MB after the fix — see task-2-report.md for the full before/after and
   the store-safety verification). Fixed with `march_decrc(elem)` after
   `call_closure_2` in both functions. Verified safe against a
   use-after-free by inspecting the compiled closure's `-emit-llvm` output:
   even a closure that stores the element (`fn (acc, x) -> List.append([x],
   acc)`) always allocates a FRESH box from the unboxed double value for
   storage rather than aliasing the box passed in, so the original `elem`
   box has no surviving alias once the call returns and dropping it is
   always safe. Now **pinned** by `test/native/native_arr_fold_leak_probe.march`
   plus three `test/dune` rules (run / stdout diff / RSS threshold), added at
   final review: an output diff cannot see a leak, so before that guard
   existed deleting either `march_decrc(elem)` left every gate green.
   Falsifiability established by sabotage in both directions and both lines —
   48.1 MB healthy, 170.6 MB with either decrc removed, threshold 96 MB.

   The accumulator has the identical borrowed-argument shape and is *also*
   never freed by the callee, but that half of the leak is inherited from the
   reference `march_typed_array_fold` and was deliberately left out of scope
   for this task. It is now measured, disclosed to users
   (`docs/simd-vectorization.md`, `CHANGELOG.md`) and tracked as an open item
   in `specs/todos/2026-08-13-native-array-fold-accumulator-chain-leak.md` —
   5M elements with a `Float` accumulator cost 193.6 MB peak RSS against
   40.4 MB for the `fold_int` control, i.e. 32.1 B/element, with int-width
   folds unaffected.

## Verification

`scripts/run-tests.sh` and `dune build --root . @test/runtest` both exit 0
against the full tree, including the new `native_arr_fold` compile-run-diff
rule in `test/dune` and the golden-preamble byte-diff test
(`test_preamble_byte_identical_native`) picking up the five new declares.
See `.superpowers/sdd/2026-08-13-simd-followups/task-2-report.md` for the
full file-by-file change list, per-width table, argument-order proof, and
the leak fix's before/after RSS numbers and store-safety verification.
