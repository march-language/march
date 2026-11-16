`[P2]` A length hypothesis on a list parameter does not meet the length fact of a `match` arm.

Found while writing the refinement-alias worked example (2026-11-08).

```march
fn need(m : Int, xs : {List(Int) | len(_) == m}) : Int do 0 end
fn tl(n : Int, xs : {List(Int) | len(_) == n}) : Int do
  match xs do
  Nil -> 0
  Cons(_, xt) -> need(n - 1, xt)          -- solver-undecided
  end
end
```

Inside `Cons(_, xt) ->` the checker has `len(xs) == len(xt) + 1` (list-length narrowing,
`refine_check.ml`) and the parameter's `len(xs) == n`; `len(xt) == n - 1` follows linearly, yet the
precondition is `solver-undecided`. The same blocks every recursive length-carrying function
(`fn zip_vec(n, xs : Vec(Int, n), ys : Vec(Int, n)) : Vec((Int, Int), n)`, `tail_len`), while a
non-recursive `Vec(Int, n + 1)` result proves. Find which fact is missing from the query
(`--refine-report-sites=all`, `MARCH_REFINE_DUMP`), fix, and add the two functions above as tests.

Related, once this works: `List.map` (`len(_) == len(xs)`) and `List.zip` / `List.zip_with`
(`len(_) == min(len(xs), len(ys))`, or `len(xs)` under `len(xs) == len(ys)`) have no length
contracts, so a `zip`-built list cannot carry `Vec(_, n)` from the stdlib.
