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

## Fixed 2026-10-02 (runtime-guarded release)

The second option: `drop.ml` no longer refuses a field whose type mentions a
type variable. A bare `'_` child gets a bare `dec_rc` — the slot holds a uniform
value and `march_decrc` is IS_HEAP_PTR-guarded, so that is a no-op on a tagged
scalar, frees a Float box, and releases a heap child shallowly (what its own
children lose is the conservative direction, and was lost before anyway). A
type that only mentions a variable but has a layout of its own (`List('_)`,
`('_, Int)`) gets its own synthesized drop exactly like its concrete instances:
the spine is known even when the elements are not. `has_tvar` is gone.

In the todo's program the frame tuple is `(List('_), '_)`: the list's spine is
walked and freed and its Int elements are scalars, so the leak goes to zero.
Monomorphising lifted local closures at their use site would make the release
deep in every case and remains a possible later step.

Regression: `test/native/aggregate_drop_erased_fields.march` leg 3.
