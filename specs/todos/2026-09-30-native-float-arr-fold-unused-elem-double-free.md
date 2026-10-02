`[P1]` `fold_float` with a callback that ignores its element: use-after-free

A lambda that returns its accumulator without using the element, passed to
`NativeArray.fold_float` through a **parameter**, double-frees each element box.
Found 2026-09-30 while adding runtime-path legs to
`test/native/native_arr_fold_boundary_box_probe.march`. Reproduces on the branch
point (5f4aa31dc) as well, so it predates the fold inline loop, which does not
take this path (the callback is not a lambda literal at the call site).

```march
mod Main do
  needs IO.Console
  pfn idfold_rt(a : NativeFloatArr, k : Int, acc : Float, f : Float -> Float -> Float) : Float do
    if k <= 0 do acc else idfold_rt(a, k - 1, acc +. NativeArray.fold_float(a, 1.0, f), f) end
  end
  fn main(_c : Cap(IO.Console)) do
    let fa = NativeArray.make_float(4, 1.5)
    let keep = fn (p, x) -> p
    println(float_to_string(idfold_rt(fa, 3, 0.0, keep)))
  end
end
```

- macOS: `march: RC underflow ... aborting` (exit 134); inside a longer program,
  SIGTRAP (133).
- Linux glibc: `malloc(): unaligned fastbin chunk detected`.
- ASAN (`MARCH_SANITIZE=1`, Linux container): heap-use-after-free in
  `march_decrc` called from `native_float_arr_fold`; the first free was
  `march_decrc_local` inside the lambda's apply fn.

Likely cause: the runtime loop (`runtime/march_runtime.c`, `native_float_arr_fold`)
boxes each element, calls the closure, then `march_decrc(elem)`, assuming the
callee only borrows the element. An apply fn that does not use a parameter drops
it, so the element box is released twice. The same lambda written inline at a
`fold_float` call site worked before 2026-09-30, so the callee's parameter
convention evidently differs between a closure the compiler can see at the call
site and one that arrives as a value; check `Clo_flags.borrowed_params` and the
"C runtime is a third owner of closures" rule. `native_f32_arr_fold` and
`march_typed_array_fold` share the pattern and need the same check.

Add the identity leg back to the boundary-box probe's `_rt` legs when fixed.
