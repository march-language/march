# A tuple destructured inside a polymorphic local `fn` is only shallowly released (compiled)

Found 2026-10-01 fixing `specs/progress/2026-09-28-array-built-then-dropped-leaks-trie.md`.

```march
pfn outer(n : Int) : List(Int) do
  fn ascend(nd, stk) do
    match stk do
    Nil -> nd
    Cons(frame, rest) -> do
      let (c, s) = frame
      ascend(Cons(s, c), rest)
    end
    end
  end
  fn descend(k, path) do
    if k == 0 do ascend(Nil, path)
    else descend(k - 1, Cons(([k, k], k), path)) end
  end
  descend(n, Nil)
end
```

leaks 4 objects per frame (compiled `--opt 2`, `live_allocs()`); with `ascend` as a
top-level `pfn` it leaks nothing. A local `fn` is lifted to a closure apply function
that stays polymorphic (`stk : List((List('_), '_))`), so `Drop.drop_fn_for` finds a
type variable in the tuple's field types (`has_tvar`) and emits a bare shallow
`dec_rc frame`: the cell is freed, the references it held are not. In
`stdlib/array.march` that was the whole old subtree of a trie on every deep push.

The stdlib no longer has any such closure (`trie_update_*`, `insert_*`, `pop_*` are
top-level). Open: either monomorphise lifted local closures at their use site, or
give an aggregate with a type-variable field a runtime-guarded generic release.
Witness: the program above in a `live_allocs()` loop; it must reach delta 0.
