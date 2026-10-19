`[P3]` Refinement: a relational scalar demand on a bare-variable call is not traced

Filed 2026-10-18 with phase 1 of `specs/2026-10-18-fold-accumulator-invariants-design.md`,
whose target f5 it blocks:

```march
fn h(ys : List(Int), lo : Int) : {Int | _ >= lo} do
  List.fold_left(ys, lo, fn (a, x) -> if x > a do x else a end)   -- unreflectable-subject skip
end
```

The scalar demand entry point (`Refine_check.scalar_demand`, element-flow phase 2) answers
`` `Na `` unless the demand is closed (`classify_pred b [] p = Closed`), at a call
(`List.nth(xs, Option.unwrap_or(o, 0))` against `_ < len(xs)`) and at a return tail
(`: {Int | _ >= lo}`) alike, so the fold rule never sees f5 and it keeps the old skip
(pinned in `test/test_refinecheck.ml` group `fold-invariants-1`, "f5"). The closed twin
(`: {Int | _ >= 0}`, f4) proves. Needs: the demand put in the caller's namespace (phase 0's
`instantiate_entry` substitution at the call's actuals; at a return tail the parameters are
already the caller's names), the z5 capture guard, and, for the fold, the accumulator
hypothesis's shadowing guard, which then becomes reachable through a scalar demand (f10: a
lambda parameter `lo` shadowing the demand's `lo` must decline; today f10 is still reported
violated by the witness path, and that must survive). Also listed in
`specs/progress/2026-10-18-element-flow-phase2-scalar-demands.md` "Left open".
