# `[P1]` The stdlib-only gate never looks inside `impl`, interface default methods, or test blocks

Filed 2026-09-24 by the distributed-deploys review (step 2, PR #594). Plan: II.1.

## Defect

The gate's declaration walker (`lib/typecheck/typecheck_caps.ml:249-270`)
visits `DFn`, `DLet` and `DActor` only, and ends in `| _ -> ()`. It skips
`DImpl` method bodies, `DInterface` default methods, `DTest`, `DDescribe`,
`DSetup` and `DSetupAll`. Any of them can call `pid_of_int`,
`actor_whereis` or `actor_registered` from ordinary user code.

## Confirmed

A user module with only `Cap(IO.Console)` forges a pid inside an impl method
and messages a live actor with it:

```march
impl Forger(Int) do
  fn forge(n) do
    let p = pid_of_int(n)
    let _ = send(p, Bump())
    let _ = send(p, Bump())
    if is_alive(p) do 1 else 0 end
  end
end
```

`--check` exits 0. Interpreted and compiled, it prints `forged alive=1
hits=2`. The same holds for a default method (`forged via default method`),
and `test`/`setup`/`setup_all`/`describe` bodies pass `--check`.

## Fix I would make

Check at name resolution, not by walking declaration kinds. In
`infer_expr`, flag an `EVar` that resolves to a gated builtin binding when the
current declaration's span is not a stdlib file. That covers every
declaration kind and the `let` shadow in
`2026-09-24-dd-review-stdlib-only-gate-let-shadow.md`. As a stopgap, add the
missing declaration kinds to the walker. Add each shape as a reject test.
