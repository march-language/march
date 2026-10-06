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

## Fixed 2026-10-06

The leaked object was not an argument box but the RESULT box. Both erased
halves were already handled on the direct path: the argument boxes are
released after the call (`apply_float_param_idxs` counts a `TVar` param), and
an erased Float result is unboxed and released by `erased_float_return` in
`Llvm_emit_call.emit_generic_app`. But that result release reads the
call-site result type from the callee var's own `v_ty`, and `Known_call`
stamped every rewritten callee `TPtr TUnit`. The call fell through to the
generic `ptr`→`double` coerce at the `let` binder, which unboxes without
releasing.

Leaving the call indirect (the todo's second option) was worse, not better:
the closure var of a let-generalized lambda is itself typed
`('a, 'b) -> 'a`, so the `ECallPtr` path had no Float return type either and
leaked two objects per call.

Fix (`lib/tir/known_call.ml`): the traversal now carries the type of the
expression it is in (a `let` RHS gets the binder's type, a tail position the
function's return type). For an apply fn whose signature is not concrete
(`concrete_apply_sig`, moved here from `Hof_spec`, which now calls it), the
direct callee var is typed `TFn ($clo :: arg types, ret)`, so
`erased_float_return` fires. Apply fns with a concrete signature keep
`TPtr TUnit`, so their emitted code is unchanged.

Regression: three new legs in `test/native/closure_call_arg_ownership_probe.march`
(direct call ignoring / returning a Float, and a direct call in tail
position). All three print `flat: false` with the old `known_call.ml` and
`flat: true` with the fix. `Hof_spec` still specializes only on concrete
lambdas: its own `EApp` carries no call-site type.
