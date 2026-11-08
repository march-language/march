`[P2]` Induction fails when an Int guard comes before the `match` on the list

Found 2026-11-08 while proving HAMT measures (`specs/progress/2026-11-08-nested-set-measures.md`).

This is solver-undecided:

```march
pfn lins(lst : List(a), idx : Int, e : a) : {List(a) | lelts(_) == union(lelts(lst), singleton(e))} do
  if idx <= 0 do Cons(e, lst)
  else match lst do
    Nil -> Cons(e, Nil)
    Cons(h, t) -> Cons(h, lins(t, idx - 1, e))
    end end
end
```

The same function with the `match` outermost and the `if` inside the `Cons` arm proves (group
`nested-measure`'s `ins_at`). Every base step proves on its own. So the gap is in how the
recursive call's hypothesis, or the `Cons` arm's facts about `lst`, are carried when the `match`
sits under an `if`. The stdlib's HAMT insertion helpers are written in the failing shape. Either
fix this, or stage B of `2026-11-06-prove-map-set-contracts.md` rewrites them match-first.

Done when the program above proves, and a REJECT variant (drop `singleton(e)`) does not.
