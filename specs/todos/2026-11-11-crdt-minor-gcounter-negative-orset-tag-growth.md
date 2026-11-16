`[P3]` CRDT: GCounter.add accepts negative n; ORSet.merge appends duplicate tags (2026-11-11)

`GCounter.add` does not reject a negative `n`, so a grow-only counter can decrease, and the per-actor max in `merge` then silently undoes the decrease. `ORSet.merge` appends the two tag lists without deduplication, so `merge(a, a)` doubles every tag list and repeated gossip grows state without bound (merge is not idempotent on the internal state; membership is unaffected).

Repro:
```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let a = CRDT.GCounter.add(CRDT.GCounter.new(), "a", 5)
  let a2 = CRDT.GCounter.add(a, "a", -3)
  println("value after add(5) then add(-3) = " ++ to_string(CRDT.GCounter.value(a2)) ++ " (grow-only: must not decrease)")
  println("value(merge(a2, a)) = " ++ to_string(CRDT.GCounter.value(CRDT.GCounter.merge(a2, a))) ++ " (the decrease is discarded by merge)")
  let n = CRDT.GCounter.add(CRDT.GCounter.new(), "a", -4)
  println("value of add(new, -4) = " ++ to_string(CRDT.GCounter.value(n)))
end
end
```
```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let a = CRDT.ORSet.add(CRDT.ORSet.new(), 1, int_to_string, "t1")
  let m1 = CRDT.ORSet.merge(a, a)
  let m2 = CRDT.ORSet.merge(m1, m1)
  println(to_string(a))
  println(to_string(m1))
  println(to_string(m2))
end
end
```

Expected: `add` with negative `n` is rejected or clamped; `merge(a, a)` has the same tags as `a`.

Actual (interpreted / compiled): value goes 5 to 2 and back to 5 after merge (interpreted and compiled); tags `[t1]` become `[t1, t1]` then four copies (interpreted).

Source: `GCounter.add` and `ORSet.union_tags` in `stdlib/crdt.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
