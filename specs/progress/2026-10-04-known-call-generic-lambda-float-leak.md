`[P2]` A direct call to a let-generalized lambda leaks a Float box per call (compiled)

Found 2026-10-02 while fixing the Float-closure specialization PR (#760), whose new
`Hof_spec` pass first made this path reachable from higher-order functions and was
caught by `test/native/closure_call_arg_ownership_probe.march`'s "erased lambda" legs.
It reproduces on main without that pass (`MARCH_NO_HOF_SPEC=1`):

```march
pfn go(n : Int, acc : Float) : Float do
  if n <= 0 do acc
  else
    let keep = fn (p, x) -> p
    go(n - 1, acc +. keep(1.0, int_to_float(n)))
  end
end
```

`live_allocs()` grows by 5,001 over 5,000 calls compiled, 0 interpreted. `keep` is
let-generalized, so its parameters are still `TVar` after Mono and its Float
arguments cross erased (boxed). On the INDIRECT call path the ownership protocol
for that is in place (the caller keeps its box, the callee takes its own reference:
`march_clo_param_own` / `march_clo_float_arg`, 2026-09-30). `Known_call` turns
this call into a DIRECT `EApp(keep$apply, [clo; 1.0; x])`, and that path does not
balance the box. Fix: make the direct apply-fn call follow the same protocol, or
have `Known_call` leave calls to apply fns with `TVar` parameters indirect.
`Hof_spec` currently sidesteps it by only specializing on lambdas with a concrete
signature (`Hof_spec.concrete_apply`).

---

# DONE 2026-10-04

## Root cause

The leaked object was the RESULT, not an argument. The direct-call path in
`lib/tir/llvm_emit_call.ml` already releases a Float result that comes back
through an erased return slot (`erased_float_return`), but it decides "is this a
Float call site?" from the callee variable's type, and `Known_call` created that
variable as an untyped code address (`TPtr TUnit`). With the call-site type lost,
the result box was unboxed by the binding's coercion and never released.

## Fix

`lib/tir/known_call.ml`: when a binding's right-hand side ends, in some tail
position (through nested lets, sequences and case branches), in an indirect call
through a known closure, the converted direct call's callee is typed
`TFn ($clo :: params, <binder type>)`. The emitter's existing erased-Float-return
release then fires. Only that release reads the callee type for an apply fn
(every other use looks the callee up by name), so nothing else changes.

## Verification

- `test/native/known_call_generic_lambda_float.march`: a generic lambda that
  returns its first Float, its second Float, forwards a Float to another closure,
  returns an Int, returns a String, and a call in a nested tail position, 20,000
  calls each. With main's `known_call.ml` the four Float legs leak (`flat: false`)
  and the Int/String legs are flat; with the fix every leg is flat and every value
  matches the interpreter.
- ASAN (Linux container) over 28 closure / lambda / Float-box fixtures, including
  `closure_call_arg_ownership_probe`: 27 clean. `record_erased_field_repr` reports a
  heap-use-after-free that reproduces with main's unmodified `known_call.ml` too;
  filed as `specs/todos/2026-10-04-record-erased-field-repr-uaf.md`.

## Not done

`Hof_spec` (the higher-order-function specialization) still only specializes on
lambdas with a concrete signature. Its clones build their own direct calls with
the same untyped callee, so lifting that restriction would need the same callee
typing there too.
