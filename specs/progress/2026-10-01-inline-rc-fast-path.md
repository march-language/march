# DONE Inline refcount fast path

Filed 2026-09-30 (`specs/todos/2026-09-30-inline-rc-fast-path.md`), done
2026-10-01. Spec: `specs/plans/2026-09-30-inline-rc-fast-path.md` (its "As
built" section records where the implementation differs from the design).

## The problem

Every refcount operation in compiled code was an out-of-line call into the
precompiled runtime, which LLVM cannot inline or elide. Compiled `main` runs on a
scheduler worker, so the `_local` entry points always took their atomic branch
after a thread-local check: a call, a TLS load, a heap-pointer test and an atomic
per operation.

## The change

- `lib/tir/llvm_rc_inline.ml`: rewrites a finished LLVM module so each call to
  `march_incrc`, `march_incrc_local`, `march_decrc`, `march_decrc_local`,
  `march_decrc_freed` or `march_decrc_local_freed` goes to an `internal
  alwaysinline` twin in the same module. Each twin does the heap-pointer test and
  the atomic inline, skips immortal objects on decrement as the originals do,
  calls the original whenever GC tracing is on or unresolved, and on the last
  reference calls a runtime tail helper.
- `runtime/march_runtime.c`: `march_gc_trace_state` exported and resolved in
  `spawn_main_impl`; `march_rc_last_atomic` and `march_rc_last_local` run the
  originals' free and underflow tails without decrementing again.
- The same rewrite hoists each function's fixed-size scalar and pointer stack
  slots to its entry block, so LLVM can promote them, but only in functions where
  every slot is one (see the spec: a mixed function, `simd_mutual_tco`'s
  dispatcher, crashed when hoisted). Without hoisting the twins grew frames enough
  to overflow `test/native/array_sort_by.march`'s deep recursion.
- `bin/main.ml`: `maybe_inline_rc` applies the rewrite at both `emit_module` call
  sites, except for wasm, sanitizer builds and `MARCH_NO_INLINE_RC=1` (a CAS-key
  tag).

## Verification

- `test/native/rc_inline_fast_path.march`: shared lists, string literals
  (immortal), capturing closures, Float boxes in a list, destructuring matches;
  output matches the interpreter and the fast-path-off build, and a
  `live_allocs()` check stays flat. A second rule pins the IR: twins defined, no
  refcount call bypassing them.
- Perturbation: making the decrement twin free one reference early aborted with
  an RC underflow; restoring it turned the fixture green.
- `MARCH_TRACE_GC` on `bench/list_ops.march`: 5,000,014 events with the fast
  path on and off, identical per kind.
- wasm32-wasi and `MARCH_SANITIZE=1` builds contain no twins.
- Benchmarks (same compiler on and off, median of 9 interleaved rounds, M3 Max):
  `list_ops` 1.25×, `tree_transform` 1.06×, `binary_trees` 1.12×.
- Stack depth: the full suite's first run caught `array_sort_by` overflowing its
  green-thread stack. Its `ordered_and_stable` recurses through a join-point
  closure, so it is not a loop; per level it took 208 bytes before, 256 with the
  twins, and 160 with the twins plus hoisting. The largest list it survives went
  from about 5,000 (before) and 4,000 (twins alone) to 6,000.

## Found along the way

- A match on a nested pattern (`Cons(a, Cons(b, rest))`) whose arm makes a
  self tail call is lowered through a join-point closure, so the call is a
  mutual call between the function and the closure. It is not turned into a loop,
  and the function recurses once per element: `array_sort_by`'s
  `ordered_and_stable` overflows at about 8,000 elements. Filed as
  `specs/todos/2026-10-01-join-point-self-tail-call-not-looped.md`.

A `List(Float)` cons cell leaks its boxed Float when dropped, compiled, with or
without this change; added to
`specs/todos/2026-10-01-aggregate-drop-skips-boxed-float-field.md`.

## Not done

- Why hoisting scalar slots in a function that also has dynamic `<4 x float>`
  slots crashes `simd_mutual_tco`. Hoisting is skipped for such functions.

- No x86 Linux timing yet. The spec asked for one before merge, because an atomic
  RMW costs more on x86 than on arm64.
- ASAN cannot check the fast path itself, because sanitizer builds turn it off on
  purpose. The suite's golden outputs and leak probes are the check instead.
