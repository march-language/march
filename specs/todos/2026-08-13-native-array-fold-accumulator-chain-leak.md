# NativeArray float folds leak the accumulator box chain (~32 B/element)

Filed 2026-08-13, discovered during the final review of the SIMD follow-ups
branch (`feat/simd-followups`). This is the **second** leak in the compiled
`NativeArray.fold_*` helpers. The first — the per-**element** box — was found
and fixed mid-branch (`march_decrc(elem)` in `native_float_arr_fold` and
`native_f32_arr_fold`) and is now pinned by
`test/native/native_arr_fold_leak_probe.march`. This one is still open.

## What leaks

`native_float_arr_fold` / `native_f32_arr_fold` in `runtime/march_runtime.c`
carry the accumulator through the loop in the erased/boxed representation:

```c
void *result = acc;
for (int64_t i = 0; i < len; i++) {
    ...
    result = call_closure_2(f, result, elem);   /* <-- old result never released */
}
```

When the accumulator is itself a `Float`, the closure returns a **fresh**
`march_alloc_float` box each iteration. That box becomes the next iteration's
`result`, and the previous one is never released — the callee treats its
arguments as borrowed (that is precisely the convention the element-box
`march_decrc` relies on), so nobody drops it. One 32-byte cell leaks per
element, unbounded in array length.

## Measurement

Darwin arm64, `--compile --opt 2`, 5,000,000 elements, `peak_rss_bytes()`:

| program | accumulator | peak RSS |
|---|---|---|
| `NativeArray.fold_float(arr, 0.0, fn (acc, x) -> acc + x)` | Float | 202,964,992 B (193.6 MB) |
| `NativeArray.fold_int(arr, 0, fn (acc, x) -> acc + x)` (control) | Int | 42,319,872 B (40.4 MB) |

Both arrays are 40 MB of payload (5,000,000 x 8 B), so the array itself is not
the difference. Delta = 160,645,120 B / 5,000,000 = **32.13 B per element**,
i.e. exactly one leaked box per iteration.

The `fold_int` control grew by **zero** over the array's own size, which is the
load-bearing half of the measurement: it rules out the already-fixed element
box (int elements are wire-tagged, never allocated) and rules out the array
itself, leaving only the accumulator chain.

## Scope

- **Affected:** `fold_float` and `fold_f32` **when the accumulator is a Float**
  (the common case — summing, averaging, dot products). Also any fold whose
  accumulator is a heap value the closure rebuilds each step (a list, a record),
  for the same reason.
- **Unaffected:** `fold_int`, `fold_i32`, `fold_u8` with an Int accumulator —
  a wire-tagged Int is never heap-allocated, so there is nothing to release.
  Confirmed by the control row above.
- **Not a correctness bug.** The fold returns the right answer; this is purely
  a memory-residency problem. It is unbounded in array length, though: a
  50,000,000-element `NativeFloatArr` folded with a Float accumulator costs
  ~1.6 GB of otherwise-unexplained RSS.

## Where the fix likely belongs

**Shared with `march_typed_array_fold`.** The `(acc, arr, f)` helpers copied
their RC discipline verbatim from `march_typed_array_fold` (same file), which
has the identical `result = call_closure_2(f, result, ...)` chain and the
identical omission. So the accumulator leak is not new to this branch — the
new helpers inherited it — and a fix that only touches the two native-array
folds would leave the older typed-array fold still leaking. Fix
`march_typed_array_fold` and apply the same shape to all the `native_*_arr_fold`
helpers in one pass.

The obvious fix — `if (result != acc) march_decrc(prev)` around each call — is
NOT safe as written, because it needs to distinguish "the closure returned a
fresh box" from "the closure returned its own accumulator argument
unchanged" (e.g. `fn (acc, x) -> acc`), and from a wire-tagged non-pointer
accumulator (an `IS_HEAP_PTR` guard is required — a wire-tagged Int must never
be handed to `march_decrc`). Whatever lands must be tested against all three
shapes.

## Guard to add with the fix

`test/native/native_arr_fold_leak_probe.march` already has the apparatus: give
it a third leg with a **Float** accumulator and extend the dune threshold rule.
Note that the probe's signal is now `live_allocs()` (net live March objects),
not peak RSS — the RSS band above was macOS-calibrated and reported a false
leak on CI's Linux leg, whose process baseline alone is ~122 MB. The new leg
should assert on the live-object delta too: expect it to add one leaked object
per element, the same shape as the element box, so the existing `< 1000`
threshold already catches it once the leg is added.
Today that leg is deliberately absent, and the two existing legs deliberately
use an **Int** accumulator, so the existing guard isolates the element box and
does not fire for this still-open leak. The fixture's header comment says so
explicitly; update it when this is fixed.

## Disclosure

Recorded for users in `docs/simd-vectorization.md` ("Known limitations") and in
the `CHANGELOG.md` entry for the compiled-fold work, so nobody hits the RSS
spike without a pointer to this file.
