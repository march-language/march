`[P1]` A generic named function passed as a `Float` closure returns the wrong value (compiled)

```march
mod Main do
  needs IO.Console
  pfn ksnd(p, x) do x end
  pfn call2(f : Float -> Float -> Float, n : Int, acc : Float) : Float do
    if n <= 0 do acc else call2(f, n - 1, acc +. f(1.0, int_to_float(n))) end
  end
  fn main(_c : Cap(IO.Console)) do
    println(float_to_string(call2(ksnd, 3, 0.0)))
  end
end
```

Interpreted: `6.`. Compiled (`--compile`): `3.`. Reproduces with a compiler
built on 2026-09-04 (bfb16dac8) as well as on 2026-09-30, so it is old. Found
while fixing
specs/progress/2026-09-30-native-float-arr-fold-unused-elem-double-free.md.

Cause, from `--emit-llvm`: `ksnd` stays generic (`define ptr @ksnd(ptr, ptr)`),
but its `$clo_wrap` trampoline is built from the USE-SITE type
(`Float -> Float -> Float`), so it unboxes both arguments and calls
`@ksnd(double, double)`. The callee reads its pointer registers, which hold
whatever the caller left there. `kfst` (`fn (p, x) -> p`) happens to print the
right number.

The trampoline is emitted in three places in `lib/tir/llvm_emit.ml` (search
`clo_wrap_define`); each takes `param_tys` from `v.Tir.v_ty`, the call-site
type. They should use the target definition's parameter types
(`ctx.top_fn_param_tys`), or mono should specialize the function at the use.

## Fixed 2026-10-02

The three `$clo_wrap` sites in `lib/tir/llvm_emit.ml` now take the parameter and
return types from the target's DEFINITION (`ctx.top_fn_param_tys` /
`ctx.top_fn_ret_ty`) whenever it is registered, not only when the arity differs
from the use site. The wrapper is keyed by the target (one per function), so
only the definition's types can be right for every use site: an erased `ptr`
parameter forwards the caller's boxed Float / tagged Int unchanged and the
caller coerces the erased `ptr` result itself. The REPL site already did this.

Regression: `test/native/generic_fn_float_closure.march` (`ksnd`, `kfst` and a
concrete `fadd` through the same `Float -> Float -> Float` parameter; the
.expected is the interpreter's output, RED as `3.` on the first line before).
