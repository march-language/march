# A join-point closure dropped unused still leaks what it captured (compiled)

Found 2026-10-01 fixing `specs/progress/2026-09-28-array-built-then-dropped-leaks-trie.md`.

A match with a nested pattern and a default arm (`Cons(root, Nil) -> .. | _ ->
up(parents, ..)`) lowers the default arm to a join-point closure `$jp_clo...`,
allocated at the head of the matching arm. On a path that never falls through, the
closure is dropped with a bare `dec_rc`: shallow, so the references it captured are
not released. `Drop.dead_clo_pair` (in `specs/progress/2026-09-30-seq-constructors-leak-their-closure.md`)
removes the simplest shape, `let c = (inc_rc x;)* alloc $Clo(..) in dec_rc c; rest`,
but not these:

- the `dec_rc` is not adjacent to the allocation (it sits in one arm of a later
  `case`, the closure being called in the other);
- the closure captures another join-point closure (`$jp_clo2 = alloc $Clo(jp2,
  $jp_clo1)`), whose own captures are released by nothing.

Seen in `Array.from_list`'s `up` (every level of nodes it built leaked) and `Array.pop`'s
root collapse (the new root leaked). `stdlib/array.march` now avoids the nested
default-arm pattern in those places; any other nested pattern with a default arm
leaks the same way. Fix: sink the allocation into the arm that calls it, or give the
dead drop the deep release the allocation site's capture list allows.
Witness: `test/native/array_trie_drop_leak_probe.march`'s from_list legs with
`up` restored to `match parents do Cons(root, Nil) -> .. | _ -> .. end`.
