`[P3]` A reflected call in a return refinement is not unfolded when the body does not call it.

Found 2026-11-06 while pinning the closed pre-pass resolution gap
(`specs/progress/2026-11-06-predicate-names.md`). With everything at top level:

```march
mod Gap do
  fn dbl(x : Int) : Int do x + x end
  fn twice(n : Int) : {Int | _ == dbl(n)} do n + n end

  fn use_it(n : Int) : {Int | _ == n + n} do twice(n) end

  fn main() : Unit do
    let _ = use_it(3)
    ()
  end
end
```

`march --check --refine-report-sites=all` files `twice`'s postcondition `skip
unreflectable-predicate`, while the same program with the body written `dbl(n)` proves it. Stage 2
(`Refine_reflect.unfold`) seems to unfold only the reflected calls the body's own terms mention, so a
call that appears only on the predicate side never gets its definition equation.

Done when `twice` above is proved (`uses: dbl`), a `{Int | _ == dbl(n) + 1}` body `n + n` is a
violation, and both are pinned in the reflection unfold tests.
