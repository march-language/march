`[P2]` `Sort.sort` / `Enum.sort_by` / `Sort.timsort_by` are not stable under any comparator (2026-11-11)

No comparator convention makes the default sort stable. The small-size networks (n <= 8) reorder ties
under both `<` and `<=`; insertion sort (16 <= n < 64) is stable only with `<`; the merge steps of timsort
(n >= 64) only with `<=`, while its run extension uses insertion sort, so `timsort_by` reorders ties under
both. Only `Sort.mergesort_by` / `List.sort_by` with `<=` and `Sort.insertion_sort_by` with `<` are stable.
The module header and doc strings now say stability is not guaranteed, so this is an API gap, not a
contract violation, but a sort-by-key on records is commonly expected to be stable.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let xs = [(1, "a"), (0, "b"), (1, "c"), (0, "d"), (1, "e")]
  println(to_string(Enum.sort_by(xs, fn a -> fn b -> Tuple.first(a) <= Tuple.first(b))))
  println(to_string(List.sort_by(xs, fn (a, b) -> Tuple.first(a) <= Tuple.first(b))))
end
end
```

Expected: both lines `[(0, b), (0, d), (1, a), (1, c), (1, e)]`.

Actual (interpreted / compiled): `Enum.sort_by` returns ties out of input order (see `sort_stability.march` in the triage scratch dir: with `<=`, 72 of 100 random 5-element inputs, 100 of 100 at n = 20, all at n = 100 and 1000; with `<`, 31 of 100 at n = 2 and all at n >= 100). `List.sort_by` is stable. The stdlib is shared, so both backends agree.

Source: `sort`, `sort_small_by` (`cmp_swap` networks), `insert_sorted`, `merge_sorted`, `extend_run` in `stdlib/sort.march`. One fix direction: make every step take the left element on a tie under one documented comparator convention.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
