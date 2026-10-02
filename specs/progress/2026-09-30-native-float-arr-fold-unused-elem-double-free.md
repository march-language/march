# A generic lambda that ignores a Float argument no longer double-frees it

**Landed 2026-09-30.** Filed the same day (as
`specs/todos/2026-09-30-native-float-arr-fold-unused-elem-double-free.md`, in the
NativeArray fold inline-loop work) while adding runtime-path legs to
`test/native/native_arr_fold_boundary_box_probe.march`.

## The defect

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

macOS: `RC underflow ... aborting` (exit 134), or SIGTRAP inside a longer
program. Linux glibc: `malloc(): unaligned fastbin chunk detected`. ASAN:
heap-use-after-free in `march_decrc` from `native_float_arr_fold`, first freed
by `march_decrc_local` in the lambda's apply fn.

The todo blamed the fold loop. The fold loop was right; the bug was wider. It
is the case the 2026-09-14 closure-ownership change listed as "not observed"
(`specs/progress/2026-09-14-closure-calls-consume-their-arguments.md`, "Not
closed here"):

- `keep` is let-generalized, so its apply fn's parameters are still `TVar`
  after mono (`fn $lam$apply($clo, p : 'a, x : 'b)`, body `dec_rc x; p`).
- The convention (`lib/tir/clo_flags.ml`) is that a closure call consumes every
  heap argument **except a boxed Float**, which stays the caller's. A
  `Float`-typed apply-fn param honours that by unboxing in its prologue.
- An erased param cannot: `Borrow.infer_module` pins it owned, so RC insertion
  releases it at its last use, or at entry when unused
  (`Perceus.insert_dead_apply_param_drops`). Handed a Float box, it released a
  reference it never got.

So it was not specific to the fold helpers. Every caller that keeps its Float
box crashed the same way: `native_f32_arr_fold`, `march_typed_array_fold` on a
`TypedArray(Float)`, and plain compiled code calling the lambda through a
`Float -> Float -> Float` parameter (`f(1.0, 2.0)` with `keep` or
`fn (p, x) -> x`: SIGABRT and SIGBUS respectively). The inline-literal case
worked because a lambda written at the call site is typed `Float`, not `TVar`.

## What landed

The callee now adapts, and the call sites that relied on the old behaviour
(each was balanced only because the callee consumed the box) were updated.

1. **Callee prologue** (`Llvm_toplevel.emit_fn`): for each user parameter of an
   apply fn whose type is `TVar`, `call void @march_clo_param_own(ptr %x.arg)`,
   which `march_incrc`s a Float box and does nothing to any other value. The
   body then owns what it releases, stores or returns. Runtime function in
   `runtime/march_runtime.c` (no-op stub in `march_runtime_wasm.c`), declared in
   `Llvm_builtins.core_items`.
2. **`$clo_wrap` trampolines** (`Llvm_calls.clo_wrap_define`) do the same for
   each `ptr` param they forward (`~own_float`), since their target may consume
   it or the trampoline may release it as borrowed. Off for actor dispatch and
   `on_stop` trampolines, whose runtime caller hands over no references.
3. **Fold helpers** (`fold_release_prev_acc`): the `prev == result` guard is
   gone. With (1) an identity callback returns its own reference, so a Float
   accumulator is always released after the call. Keeping the guard leaked one
   box per element.
4. **Indirect calls** (`Llvm_emit_call`, `ECallPtr`): a Float argument box the
   call site created is released unconditionally; the pointer-equality alias
   guard (skip the release when the result is the same box) leaked one box per
   call for the same reason as (3).
5. **Erased arguments** (both the `ECallPtr` path and the direct apply-fn
   path): a `TVar` variable passed to a closure may be a Float box that Perceus
   handed over and the callee will not spend. `march_clo_float_arg` reads its
   tag before the call (a non-Float argument may be freed during the call) and
   the call site releases the box afterwards. Without it, a lambda that passes
   its erased argument on (`fn (f, x) -> f(x)`) leaked one box per call.
6. **Direct apply-fn calls** (Boundary B): a Float box created for an erased
   param is now released too (it used to be left for the callee to consume),
   and a `TVar` result at a `Float` call site is unboxed and released when the
   callee var's type says Float.

## Not closed here

- A direct call to an erased lambda whose result type is known only from the
  enclosing `let` (`let k = fn (p, x) -> x` then `k(1.0, 2.0)` in the same
  function) still leaks the returned box, one per call. Same count as before
  this change; the callee var's type is `TVar` there, so (6) cannot see it.
- A generic named function passed as a `Float` closure returns the wrong
  value; its trampoline is built from the use-site type.
  `specs/todos/2026-09-30-generic-named-fn-as-float-closure-wrong-value.md`.

## Verification

- `test/native/native_arr_fold_boundary_box_probe.march`: identity `_rt` leg
  re-added (the todo's request), plus an f32 identity leg and an
  element-returning leg, all with the callback passed as a parameter.
- `test/native/closure_call_arg_ownership_probe.march`: three legs for an
  erased lambda handed Float arguments (ignores one, returns one, forwards one
  to another closure).
- RED controls: without (1), both fixtures abort (`RC underflow`, exit 134);
  without (5), the forwarding leg reads `flat: false`.
- **ASAN** (linux/arm64 `march-amdr-repro` container, `MARCH_SANITIZE=1
  MARCH_DEBUG_RUNTIME=1`, `detect_leaks=0`): the todo's repro, both updated
  fixtures, `native_arr_fold_leak_probe`, `native_arr_fold_acc_leak_probe`,
  `native_float_box_abi_leak_probe`, `closure_capture_release_probe` and the
  scratch probe below, 3 runs each, all clean. Control: the same sources at
  HEAD rebuilt in the same container report heap-use-after-free in
  `march_decrc` on the repro, both fixtures and the scratch probe.
  `specs/lang/golden/sanitize.sh`: golden 47/47 and native 32/32 clean,
  two-node 54 clean; its 9 `cert_*` failures are setup only ("forge not
  built" in the container), and 4 scenarios skip (need root).
- `scripts/run-tests.sh` (full) green once the preamble golden in
  `test/test_codegen.ml` lists the two new declares; `dune build --root .
  @test/runtest` green.
- Benchmarks: `bench/list_ops`, `tree_transform` and `binary_trees` emit no
  `march_clo_param_own` or `march_clo_float_arg` call at all (`--emit-llvm
  --opt 2`), so they are unaffected by construction; outputs byte-identical
  against HEAD. Timings were taken at load average ~50 and are not meaningful.
- A scratch probe over 5,000 calls each: indirect, `fold_float`, `fold_f32` and
  `typed_array_fold` with `keep` and `fn (p, x) -> x`, and a forwarding lambda
  with an erased and a typed inner closure, all grow by 2 objects in total.
