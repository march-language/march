# A niche-encoded `Option(T)` field of a dying aggregate is released shallowly (compiled)

Found 2026-10-01 fixing `specs/progress/2026-09-28-array-built-then-dropped-leaks-trie.md`.

`Drop.may_be_non_heap` sends a field of niche-encoded type (`Option` of a boxed type:
`Some(x)` is `x`, `None` is null) to a bare `dec_rc`, because the synthesized
`__drop$T` helpers gate their children on `march_decrc_freed`, which reports "freed"
for a non-heap word and would dereference a null `None`. A bare `dec_rc` is shallow, so
a tuple or record holding `Some(tree)` that is dropped frees the payload's cell and
leaks everything the payload owned. `Array.pop_leaf` returned `(Option(TrieNode(a)),
List(a))`; every pop that crossed a leaf leaked the subtree. The stdlib now returns the
`TrieEmpty` sentinel instead.

Fix: a niche-aware drop that tests the word for non-null/heap before calling the
payload's `__drop`, e.g. via `march_decrc_local_freed` (which returns 0 for a non-heap
word) or a new `is_heap` test. Witness: `let (o, n) = (Some(big_tree), 1)` dropped in a
`live_allocs()` loop; it must reach delta 0.
