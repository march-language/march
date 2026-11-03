`[P3]` A lemma whose theorem is an `Int`-valued recursive function over a user datatype does
not prove, even with the obvious induction:

```march
type Tree = Leaf | Node(Tree, Int, Tree)
fn tsize(t : Tree) : Int do
  match t do
    Leaf -> 0
    Node(l, _, r) -> tsize(l) + 1 + tsize(r)
  end
end
@[lemma]
fn size_nonneg(t : Tree) : {Unit | tsize(t) >= 0} do
  match t do
    Leaf -> ()
    Node(l, _, r) ->
      size_nonneg(l)
      size_nonneg(r)
  end
end
```

`tsize` is reflected (`--reflect-report`: `reflected unfold`), yet the lemma is
`lemma_unproved`, and the walk also warns "`tsize` is not a measure or known predicate".
The same shape over `List` (`cat`, `rev`) proves. Found while testing interface laws
(`specs/progress/2026-11-03-interface-laws.md`). Find where the theorem's call stops being
the reflected symbol, and add a `reflect-lemma` case.
