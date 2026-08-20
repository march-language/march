# Fold helpers still leak a heap NON-Float accumulator (~1 object/element)

Filed 2026-08-20, split off from
`specs/progress/2026-08-20-fold-accumulator-chain-leak-fix.md` — the residual
that fix deliberately did not take.

## What still leaks

`fold_release_prev_acc` in `runtime/march_runtime.c` releases the previous
accumulator only when it carries `MARCH_FLOAT_TAG`. A **String / List / record**
accumulator threaded through any of the five fold helpers still leaks one heap
object per element, unbounded in array length.

Measured, Darwin arm64, `--compile --opt 2`, 1,000,000 elements:

```march
typed_array_fold(arr, int_to_string(10000000),
                 fn (acc, x) -> int_to_string(10000000 + x))
```

`live_allocs()` delta = **1,000,000** — exactly one leaked String per element.

## Why the Float fix does not generalise

**An apply fn does not return an owned reference.** For a `ptr` parameter
returned unchanged it emits a bare `ret ptr %x` with no `inc_rc` — read the IR
for `fn (acc, x) -> x`:

```llvm
define ptr @$lam...$apply$...(ptr %$clo.arg, ptr %acc.arg, ptr %x.arg) {
  ...
  %ld64 = load ptr, ptr %x.addr
  ret ptr %ld64            ; borrowed alias, no inc_rc
}
```

So a returned `ptr` may alias a live array element or a closure capture, and
the fold loop cannot tell that from a freshly allocated one. Releasing it is a
use-after-free — reachable today via
`typed_array_fold(arr, base, fn (acc, x) -> x)`, whose elements are owned by
the array.

Float escapes this only because the uniform-ptr ABI unboxes a Float param to a
raw `double` and re-boxes on return, making every Float-typed return provably
fresh. There is no equivalent runtime-side witness for other heap types —
`MARCH_FLOAT_TAG` is the only tag that means "certainly freshly allocated by
the callee".

## What the fix probably is

Compiler-side, not runtime-side: make apply-fn returns **uniformly owned**, so
that returning a borrowed parameter emits an `inc_rc`. Then the fold loops can
release every previous accumulator unconditionally (keeping only the
`prev != acc` guard for the caller-owned initial value) and the tag check goes
away entirely.

That is a Perceus/`Borrow.infer_module` change with a wide blast radius — every
existing call site that today relies on the borrowed-return convention would
need auditing — so it wants its own measurement + full-suite pass rather than
being bolted onto the Float fix. Compare
`specs/progress/2026-07-29-clo-drop-owned.md`-era work for the shape of that
audit; the general lesson there ("the C runtime is not one contract, it is N")
applies directly.

## Guard to add with the fix

`test/native/native_arr_fold_acc_leak_probe.march` has the apparatus. Add a
String-accumulator leg; the existing `< 1000` dune threshold catches it
immediately. The fixture header explicitly warns not to add that leg before
this item lands, because it would be permanently RED.

Also add a REJECT-side witness: `typed_array_fold(arr, base, fn (acc, x) -> x)`
followed by reading the array's elements, which must not fault.
