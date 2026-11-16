`[P2]` CRDT.ORSet.remove keeps no tombstone, so a merge resurrects removed elements (2026-11-11)

`ORSet.remove` deletes the map entry and records nothing about the tags it observed. Merging with any replica that still holds the element brings it back, even when the remove happened after observing that exact add. This is not an observed-remove set, and the module header promises a proper CRDT join. The function doc now states the behaviour, but the type is unusable for replicated removal.

Repro:
```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  -- replica a adds 1 (tag t1); b is a copy of a; a removes 1 after observing t1.
  let a0 = CRDT.ORSet.add(CRDT.ORSet.new(), 1, int_to_string, "t1")
  let b = a0
  let a1 = CRDT.ORSet.remove(a0, 1, int_to_string)
  println("after remove on a: contains=" ++ to_string(CRDT.ORSet.contains(a1, 1, int_to_string)))
  let m = CRDT.ORSet.merge(a1, b)
  println("after merge(a, stale b): contains=" ++ to_string(CRDT.ORSet.contains(m, 1, int_to_string)) ++ " (OR-Set law: false, the remove observed t1)")
end
end
```

Expected: second line prints `contains=false`.

Actual (interpreted / compiled): second line prints `contains=true` (interpreted and compiled).

Source: `ORSet.remove` and `ORSet.merge` in `stdlib/crdt.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
