`[P2]` # `NativeArray.fold_float` leaks exactly 2 objects per call

Found 2026-09-16 while re-measuring the remaining RC leaks at `0a4275849`
(`specs/2026-09-16-remaining-rc-leaks-design.md` §C).

`--compile --opt 2`, Darwin arm64, 16-element `NativeFloatArr`, 2,000 calls of
`NativeArray.fold_float(a, 0.0, fn (p, x) -> p +. x)`:

| entry point | live objects per call |
|---|---|
| `fold_float` | **2.0005** |
| `fold_int` | 0.0005 |
| `sum_float` | 0.0005 |
| `map2_float` | 0.0005 |
| `map_float` | 0.0000 |

**Length-independent**: 4, 16, 64 and 256 elements all grow by the same 4,001
over 2,000 calls. So this is NOT the per-element boxing inside the loop —
`runtime/march_runtime.c:9060 native_float_arr_fold` already releases that
(`march_decrc(elem)`, and `fold_release_prev_acc` for the accumulator chain),
and both releases have their own pinning fixtures
(`native_arr_fold_leak_probe`, `native_arr_fold_acc_leak_probe`).

It is the March↔C boundary, and 2 is the count of Float boxes crossing it:

- the **initial accumulator box** the caller allocates for `0.0`.
  `fold_release_prev_acc` deliberately excludes it from release — it is the
  caller's `acc`, passed in — so the caller owes it;
- the **returned result box**, which the caller unboxes with
  `march_unbox_float` and then drops on the floor.

`fold_int` is the control that isolates the cause: `clo_call_int_int` wire-tags
its scalar instead of boxing, and it is flat.

## The fix

The same ownership question the SIMD vector box answered on 2026-09-16
(`specs/progress/2026-09-16-simd-vector-box-released.md`): a value boxed by the
CALLER to cross a `ptr` slot, for a callee that borrows it, is the caller's to
release. Release the argument box after the call and the result box after the
unbox, at the call site in `lib/tir/llvm_emit_call.ml`, gated on the builtin's
borrow classification rather than hardcoded by name.

Sweep the siblings in the same change: every `f64` entry point that takes or
returns a boxed Float across the C boundary has this shape, and only
`fold_float` happened to be exercised by this probe's argument pattern.

## Verification bar

A `live_allocs` flat probe over `fold_float` with `fold_int` as the control
leg, RED before the fix; the existing fold fixtures stay green; and the ASAN
gate — this adds a release where none ran, and an over-eager one is a
use-after-free, not a leak.
