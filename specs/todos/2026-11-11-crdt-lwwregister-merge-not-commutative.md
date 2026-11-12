`[P2]` CRDT.LWWRegister.merge is not commutative for concurrent writes (2026-11-11)

For concurrent or equal vector clocks `merge` keeps the left argument, with no deterministic tiebreak. Two replicas that merge each other's state end with different values and never converge. The module header promises a commutative join.

Repro:
```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let r0 = CRDT.LWWRegister.new("v0", VectorClock.new())
  let a = CRDT.LWWRegister.set(r0, "from-n1", "n1")
  let b = CRDT.LWWRegister.set(r0, "from-n2", "n2")
  println("merge(a, b) = " ++ CRDT.LWWRegister.get(CRDT.LWWRegister.merge(a, b)))
  println("merge(b, a) = " ++ CRDT.LWWRegister.get(CRDT.LWWRegister.merge(b, a)))
end
end
```

Expected: `merge(a, b)` and `merge(b, a)` return the same value.

Actual (interpreted / compiled): `from-n1` and `from-n2` (interpreted and compiled).

Source: `LWWRegister.merge` in `stdlib/crdt.march`. A deterministic tiebreak (for example on the clock entries or a node id) would fix it.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
