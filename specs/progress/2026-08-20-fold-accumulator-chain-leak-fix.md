# Fold helpers: the accumulator chain is released (Float accumulators)

Fixes `specs/todos/2026-08-13-native-array-fold-accumulator-chain-leak.md`
(this file is that item, moved). Filed 2026-08-13, fixed 2026-08-20.

## What leaked

Every fold helper in `runtime/march_runtime.c` carried the accumulator through
the loop in the erased/boxed representation and never released the previous
one:

```c
result = call_closure_2(f, result, elem);   /* old result dropped on the floor */
```

Affected: `march_typed_array_fold` (the shared root the others copied their RC
discipline from), `native_int_arr_fold`, `native_float_arr_fold`,
`native_f32_arr_fold`, and the macro-generated `PREFIX##_fold` (i32/u8) — five
bodies. ~32 B per element, unbounded in array length.

## Measurement

`test/native/native_arr_fold_acc_leak_probe.march`, Darwin arm64,
`--compile --opt 2`, two 2,000,000-element legs (f64 + f32 accumulator):

| build | `live_allocs()` delta |
|---|---|
| before | **4,000,007** |
| after | **9** |

4,000,000 = exactly one leaked box per element across the two legs. The healthy
figure is a genuine constant, not a smaller slope: measured at **9 for 500,000,
2,000,000 and 8,000,000** elements per leg — a 16x range.

The earlier RSS-based figure in the original report (193.6 MB vs a 40.4 MB
control over 5M elements) is consistent with this but is not the signal used;
see the fixture header for why `live_allocs()` replaced RSS.

## The fix, and why it is tag-guarded

`fold_release_prev_acc(prev, result, acc)`, called after each
`call_closure_2`. It releases `prev` only when all of:

* `prev != result` — the closure did not thread its accumulator through
  unchanged;
* `prev != acc` — this is not the fold's INITIAL accumulator, which belongs to
  the caller;
* `IS_HEAP_PTR(prev)` — a wire-tagged Int accumulator is an immediate;
* **`((march_hdr *)prev)->tag == MARCH_FLOAT_TAG`**.

The tag check is the safety argument, not an optimization. **An apply fn does
not return an owned reference in general.** For a `ptr` parameter returned
unchanged it emits a bare `ret ptr %x` with no `inc_rc` — verified by reading
the emitted IR for `fn (acc, x) -> x` — so it hands back a *borrowed* alias of
something still owned elsewhere (a live array element, a closure capture).
Releasing that is a use-after-free, and for `march_typed_array_fold` it is a
reachable one: its elements are arbitrary heap pointers owned by the array.

A Float is provably different. The uniform-ptr ABI unboxes a Float parameter to
a raw `double` in the apply fn's entry prologue (`Llvm_toplevel.emit_fn`) and
re-boxes on return via `march_alloc_float` (`Llvm_ctx.coerce`); Float closure
captures are stored as raw doubles too. So *every* Float-typed value coming out
of an apply fn is a fresh box the loop solely owns. Confirmed in IR: even
`fn (acc, x) -> x` compiles to `march_unbox_float` on both params followed by a
fresh `march_alloc_float` on the way out.

This is exactly the three-shape discrimination the original item demanded
("fresh box" vs "returned its own accumulator argument" vs "wire-tagged
non-pointer"), and all three are pinned by tests.

## Guards added

* `test/native/native_arr_fold_acc_leak_probe.march` (+ `.expected`, + four
  dune rules in `test/dune`) — leak direction, threshold `< 1000`.
* The same fixture's **identity leg** — double-free direction: the closure
  returns its accumulator argument unchanged AND the caller keeps using the
  initial accumulator after the fold returns, so an over-eager release shows up
  as an RC-underflow abort or a garbage length rather than as a leak.
* The pre-existing `test/native/native_arr_fold_leak_probe.march` (per-ELEMENT
  box) re-verified unchanged at delta 3 — the two releases do not interact.
* `specs/lang/golden/sanitize.sh` corpus gate: clean.

## Residual — still open

A heap **non-Float** accumulator (String, List, record) still leaks one object
per element, for the borrowed-return reason above. Measured with a String
accumulator at 1,000,000 elements: `live_allocs` delta = 1,000,000. Fixing it
needs the compiler to guarantee owned returns, not a runtime-side guess.
Tracked in
`specs/todos/2026-08-20-fold-heap-accumulator-borrowed-return-leak.md`.

`march_typed_array_fold` gets the identical fix but **could not be pinned by a
leak leg**: its compiled path is independently broken for exactly the scalar
accumulator types that would show the leak (Int accumulator returns 15 instead
of 35; Float accumulator SIGSEGVs). Tracked in
`specs/todos/2026-08-20-typed-array-fold-compiled-scalar-accumulator-broken.md`.
