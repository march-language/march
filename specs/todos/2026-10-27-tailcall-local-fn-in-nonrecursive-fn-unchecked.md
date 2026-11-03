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
