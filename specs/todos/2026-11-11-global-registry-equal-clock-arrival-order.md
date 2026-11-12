`[P2]` `GlobalRegistry.merge` resolves two bindings with Equal clocks by arrival order (2026-11-11)

`wins` returns `true` for `Equal`, so the incoming binding replaces the stored one. Two different bindings for one name with Equal vector clocks therefore merge to different winners on different replicas, and their Merkle roots differ, so anti-entropy never settles. The module header claims `merge` is commutative. Equal clocks with different payloads arise when one node registers twice from the same base clock, for example after a restart that lost its registry (`next_clock` gives `{n1: 1}` again with a new pid). `Equal` should fall to the same deterministic `tiebreak` that `Concurrent` uses.

Repro (`global_registry_equal_clock.march`):

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let clk = VectorClock.increment(VectorClock.new(), "n1")
  let a = GlobalRegistry.register(GlobalRegistry.empty(), "db", "n1", 41, clk)
  let b = GlobalRegistry.register(GlobalRegistry.empty(), "db", "n1", 42, clk)
  println("merge(a,b): " ++ to_string(GlobalRegistry.lookup(GlobalRegistry.merge(a, b), "db")))
  println("merge(b,a): " ++ to_string(GlobalRegistry.lookup(GlobalRegistry.merge(b, a), "db")))
  println("roots equal: " ++ to_string(GlobalRegistry.root_hash(GlobalRegistry.merge(a, b)) == GlobalRegistry.root_hash(GlobalRegistry.merge(b, a))))
end
end
```

Expected: both orders give the same binding and equal root hashes.

Actual (interpreted / compiled): `(n1, 42)` one way, `(n1, 41)` the other, `roots equal: false` / the same.

Source: `wins`, `observe`, stdlib/global_registry.march.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
