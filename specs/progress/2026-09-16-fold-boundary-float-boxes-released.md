`[P2]` # `fold_float` leaked two Float boxes per call; both released

Closes `specs/todos/2026-09-16-native-float-arr-fold-leaks-two-boxes-per-call.md`,
which is §C of `specs/2026-09-16-remaining-rc-leaks-design.md`.

## The leak

`NativeArray.fold_float(arr, 0.0, f)` grew `live_allocs` by exactly **2 per
call**, and — the tell — **independent of length**: 4, 16, 64 and 256 elements
all grew by the same 4,001 over 2,000 calls. So it was not the per-element
boxing inside the fold loop, which has been released since 2026-08-20 and is
pinned by `native_arr_fold_leak_probe` and `native_arr_fold_acc_leak_probe`.
It was the March/C boundary, and 2 is the number of Float boxes that cross it.

Read straight off `--emit-llvm` for a single call:

```llvm
%cv5 = call ptr @march_alloc_float(double 0.0)          ; never released
%cr6 = call ptr @native_float_arr_fold(ptr %cv5, ...)
%cv7 = call double @march_unbox_float(ptr %cr6)         ; %cr6 never released
```

`fold_int` was the control that isolated the cause: `clo_call_int_int`
wire-tags its scalar instead of boxing, and it was always flat. So were
`sum_float` (no closure) and `map2_float` / `map_float` (different return
path).

## Two halves, two owners

**The initial accumulator box.** `runtime/march_runtime.c`'s
`fold_release_prev_acc` skipped the release when `prev == acc`, on the
intuition that a fold's initial accumulator belongs to the caller. It does not:
every one of these helpers is in `Borrow.extern_owned_builtins`, so the caller
TRANSFERS its reference — and the call site's boxed-generic-param coercion
(`Llvm_builtins.builtin_boxed_generic_params_tbl`, which exists so a literal
`0.0` does not reach the C runtime as raw double bits) makes that box FRESH at
every call, owned by nobody else. Dropping the exclusion makes the helper
honour the convention it is declared under. The `prev == result` guard stays
and is what covers a closure that hands its accumulator straight back; a
zero-length fold never enters the loop, so `acc` is returned as `result` and
the caller releases it once.

**The returned box.** The helper declares a generic `ptr` return; at a Float
call site the caller unboxes it and dropped it. Released at the call site now,
by the same arm that already did this for a Float-returning apply fn
(`lib/tir/llvm_emit_call.ml`, the `native_float_box_abi_leak_probe` release) —
one representation removed.

Two details that cost a build each and are worth writing down:

- `ret_tir` for a builtin is its **declared** return type, which for these is
  the generic `'a` the table exists to describe — never `"double"`. The
  concrete type for a given call is the call-site `TFn` annotation, so the
  Float-ness has to be read from there. Gating on `ret_tir` compiled fine and
  emitted nothing.
- The release is gated on an **allowlist**
  (`Llvm_builtins.builtin_owned_boxed_return`), not on the shape. "Returns
  `ptr` where March says `Float`" is not sufficient: `typed_array_get` hands
  back an element the ARRAY still owns, and releasing that at the call site
  would be a use-after-free rather than a leak fixed.

## Measured

20,000 calls over a 4-element array, `live_allocs` growth per call:

| entry point | before | after |
|---|---|---|
| `fold_float` | 2.0005 | 0.0005 |
| `fold_f32` | 2.0005 | 0.0005 |
| `fold_int` (control) | 0.0005 | 0.0005 |

## Verification

- `test/native/native_arr_fold_boundary_box_probe.march`, five legs, RED
  against the parent commit: `fold_float`, `fold_f32`, the identity-closure leg
  and the zero-length leg all flip from `flat: false` to `flat: true`, the
  `fold_int` control stays true, and every printed VALUE is byte-identical
  across the flip — the fix changes allocation, not results.
- The last three legs are the double-free direction, which is what an
  over-eager release of either box looks like: an identity closure returning
  the accumulator it was handed, and a zero-length fold whose result IS the
  caller's initial accumulator.
- `native_arr_fold_leak_probe` and `native_arr_fold_acc_leak_probe`, the
  per-element and accumulator-chain pins, both still match.
- `scripts/run-tests.sh`, `dune build --root . @test/runtest`.
- The ASAN gate, with the new probe added to the curated native corpus.

## Apparatus note

Editing `runtime/*.c` and building `@install` does **not** restage
`_build/default/runtime`, which is the runtime the compiler actually compiles.
The first measurement after the runtime half of this fix read unchanged at
2.0 per call because of it. Build a target with a `runtime` dep to restage, and
check `grep` on `_build/default/runtime/march_runtime.c` before believing a
null result.
