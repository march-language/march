## Completed 2026-11-07

The tail checker now visits non-recursive function bodies and actor handler
bodies, using an empty enclosing recursion set. Named local functions still
receive their own recursion set. Lambda bodies and `let*` continuations are
visited with fresh empty sets, preserving their call-frame boundary.

Regressions cover rejection in ordinary functions, actors, nested named locals,
lambdas, and `let*` continuations; safe actor tail recursion, structural warnings,
callback calls to the enclosing function, and the existing opt-out remain intact.

### Stdlib sweep

Checked all 138 `stdlib/*.march` files independently with `--check`, using
the workspace stdlib, before and after the change. Exit statuses are identical:
131 pass and seven already fail on the baseline (`control`, `json`, `list`,
`msgpack`, `sorted_set`, `toml`, `yaml`). These baseline failures are not
counted as passes.

The only added diagnostics are 12 structural-recursion warnings: `Array.apply_f`,
`Dir.prepend`, `Http.go`, `HttpClient.list_concat/req_names/resp_names/err_names`,
`IOList.map_strings`, `Plot.update_at/go`, `Seq.strip_trailing_empty`, and
`Uuid.list_append`. No new errors or suppressed checks.

## Original report

`[P3]` The stack check never visits a local `fn` inside a non-recursive function

Filed 2026-10-27 by phase 0 of `specs/2026-10-26-termination-checking-design.md`
(fact F3, row t10b). This is about stack safety, not termination, so it belongs to the tail pass.

```march
fn h(i : Int) : Int do
  fn go3(i : Int) : Int do 1 + go3(i + 1) end   -- non-tail, no diagnostic at all
  go3(i)
end
```

`enforce_tail_calls_in_decls` (`lib/typecheck/typecheck_tailcall.ml`) checks a `DFn`
only when it is in a recursive SCC. It reaches a local `ELetFn` only through
`check_tail_position` of such a function. So a local recursive `fn` inside a
**non-recursive** outer function is never checked. A non-tail self-call there gets
neither the `non_tail_recursion` warning nor the error. The same local `fn` inside a
recursive outer function is checked.

`--termination-report` lists `h/go3` as a recursive unit (class C, shape `int-asc`).
The unit is visible; only the stack diagnostic is missing.

Fix: walk every top-level `DFn` body for `ELetFn`s, whether the outer function is recursive or
not, and run `check_tail_position` on each self-recursive local. Expect new
`non_tail_recursion` warnings in the stdlib: 349 stdlib units are local fns (design
§0.5), and how many of them sit in non-recursive outers is unmeasured. The PR therefore needs a
stdlib sweep.
