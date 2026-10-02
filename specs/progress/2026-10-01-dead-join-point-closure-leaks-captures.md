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

## Fixed 2026-10-02

Three parts, found in this order once single-site join points were inlined in
place (see [2026-10-01-join-point-self-tail-call-not-looped.md](2026-10-01-join-point-self-tail-call-not-looped.md)):

1. **The single-site shape no longer allocates anything** (`bind_jp`), so the
   dead closure, and its leak, do not exist.

2. **Perceus released a scrutinee before dup'ing a field the arm still reads.**
   With the fallback in place, `parents` is live in the fall-through leaf and
   dead in the matching leaf, so the arm owns it but emits no release at its
   head; the release landed as a cross-branch `dec_rc parents` at the start of
   the matching leaf, now a DEEP drop, and the leaf then did
   `let root = inc_rc $f1` on a freed field (RC underflow abort). The old
   "keep every br_var conservatively live" approximation hid this behind the
   closure that captured the scrutinee, and leaked those fields.
   `perceus_core.ml` (ECase rule): when the arm owns the scrutinee but the body
   still mentions it (`scrutinee_deferred`), every pattern field the body uses
   takes its own reference at the arm head and is owned from there on
   (released at its last use); a field the body never reads stays the
   scrutinee's. A scrutinee moved into a closure environment is covered the
   same way.

3. **A kept multi-site join point's dead release is deep.** `drop.ml` records
   every closure environment bound in the function with the heap captures its
   allocation stored (`env.clo_caps`); a later bare `dec_rc` on that binding
   becomes `let freed = march_decrc_freed(c) in case freed of True -> drop each
   capture` (`dead_clo_release`), the same discipline as the aggregate drops.
   This covers both shapes the todo lists: the release in one arm of a later
   `case`, and a join point captured by another join point (its captures are
   released by that closure's own deep drop).

Regression: `test/native/jp_dead_closure_release.march` (both shapes under
`live_allocs()`; RED as `flat: false` on both before, and with only part 1 the
first leg aborted with an RC underflow and the second SIGSEGV'd). The
`escape_analysis` "conn-like value" unit test was asserting on the dead
closure's promotion (its own `Conn(Int, Int)` is an unboxed aggregate with no
cell to promote); it now uses a boxed ctor and the driver's `Kind` table.
