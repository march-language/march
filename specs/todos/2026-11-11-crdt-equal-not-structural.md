`[P2]` CRDT.ORSet.equal and CRDT.PNCounter.equal compare sizes/totals, not state (2026-11-11)

The module header says `equal(a, b)` is structural equality on the internal state. `ORSet.equal` compares only the element counts, so {1} equals {2}. `PNCounter.equal` compares only the P and N sums, so two replicas that each incremented a different actor are `equal` although their merge has a different value. Code that uses `equal` to detect convergence stops syncing too early.

Repro:
```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let a = CRDT.ORSet.add(CRDT.ORSet.new(), 1, int_to_string, "t1")
  let b = CRDT.ORSet.add(CRDT.ORSet.new(), 2, int_to_string, "t2")
  println("elements a=" ++ to_string(CRDT.ORSet.elements(a)) ++ " b=" ++ to_string(CRDT.ORSet.elements(b)))
  println("equal({1},{2}) = " ++ to_string(CRDT.ORSet.equal(a, b)))
end
end
```
```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let a = CRDT.PNCounter.increment(CRDT.PNCounter.new(), "a")
  let b = CRDT.PNCounter.increment(CRDT.PNCounter.new(), "b")
  println("equal(a, b) = " ++ to_string(CRDT.PNCounter.equal(a, b)))
  println("value(merge(a, b)) = " ++ to_string(CRDT.PNCounter.value(CRDT.PNCounter.merge(a, b))) ++ " vs value(a) = " ++ to_string(CRDT.PNCounter.value(a)))
  println("equal(merge(a,b), a) = " ++ to_string(CRDT.PNCounter.equal(CRDT.PNCounter.merge(a, b), a)) ++ " (if a==b as states, merge(a,b) must equal a)")
end
end
```

Expected: `equal({1},{2}) = false`; `PNCounter.equal(a, b) = false`.

Actual (interpreted / compiled): `true` in both cases (interpreted).

Source: `ORSet.equal` and `PNCounter.equal` in `stdlib/crdt.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
