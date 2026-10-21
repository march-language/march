# `[P3]` A relational element return built by `List.filter` with a captured bound is not proved

Filed 2026-10-21 from the inference-lite design (`specs/2026-10-20-refinement-suggest-lite-design.md` §0, row R2).

```march
fn small(xs : List(Int), n : Int) : List({Int | _ < n}) do List.filter(xs, fn y -> y < n) end
fn go(ys : List(Int)) : Int do sum_lt(small(ys, 10), 0) end
```

Hand-annotated, this gives 2 skips: `abstract-refinement-uninstantiated` at the return (the lambda
captures `n`, so `q` is not closed) and `unreflectable-subject` at the call. The closed variant
(`fn y -> y < 10`, `List({Int | _ < 10})`) proves 2/2. Until this proves, `--refine-infer` rejects
the candidate as `not-true` (it never proposes a contract the checker will not verify).
