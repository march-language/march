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
