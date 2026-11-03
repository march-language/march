# Element slot naming a parameter: false violation (`x = -1`)

Filed 2026-10-18 by phase 0 of `specs/2026-10-18-abstract-refinements-multi-arg-design.md`
(row r7, §8). Reproduced on the phase-0 compiler.

```march
mod Q do
  type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))
  fn need_big(_a : Assoc(Int, {Int | _ > 1000})) : Int do 0 end
  fn capt(x : {Int | _ > 1000}, a : Assoc(Int, {y : Int | y > x})) : Int do need_big(a) end
end
```

`march --check --refine-report` reports `0 proved, 1 violated`:
"an element of the container passed as `a` does not satisfy the expected element
refinement `_ > 1000` (e.g. x = -1, (elem) = 0)". This is a false violation. Every element
of `a` is `> x`, and `x > 1000`, so every element is `> 1000`. The subtyping query
(`check_elements`' subtyping arm, `lib/refinecheck/refine_check.ml`) puts the have slot's
predicate on a fresh `$elem`. The predicate names the parameter `x`, but `x`'s own
refinement never reaches that query's scope, so z3 is free to choose `x = -1`. The fix is
to scope a slot predicate's free names against the function's parameter facts (or to
decline with a recorded skip when it cannot). A false refutation must not stay a violation.
This may be the same defect as the concurrent "relational element slot `_ < n` read in
the wrong scope" fix. Check that fix against this repro before working on it.
