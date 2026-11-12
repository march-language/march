`[P3]` `ConsistentHash.add` on an existing name leaves the old value on the ring (2026-11-11)

`add` replaces the name-map entry but inserts a second set of virtual nodes at the same positions; `ring_insert` puts the new entry after the old one with an equal hash, so lookups still return the OLD value for most keys. `size` and `nodes` report only the new value. The doc string describes this and says to `remove` first; replacing in place would be the least surprising behaviour.

Repro (`consistent_hash_readd.march`):

```march
mod A do
needs IO.Console
fn count(ring, i, acc_old, acc_new) do
  if i >= 200 do (acc_old, acc_new) else
    match ConsistentHash.get(ring, "k" ++ int_to_string(i)) do
      Some("old") -> count(ring, i + 1, acc_old + 1, acc_new)
      Some(_) -> count(ring, i + 1, acc_old, acc_new + 1)
      None -> count(ring, i + 1, acc_old, acc_new)
    end
  end
end
fn main(_c : Cap(IO.Console)) do
  let r1 = ConsistentHash.add(ConsistentHash.new(4), "n1", "old")
  let r2 = ConsistentHash.add(r1, "n1", "new")
  println("size=" ++ int_to_string(ConsistentHash.size(r2)) ++ " nodes=" ++ to_string(ConsistentHash.nodes(r2)))
  println("200 keys routed (old, new): " ++ to_string(count(r2, 0, 0, 0)))
  let r3 = ConsistentHash.remove(r2, "n1")
  println("after remove: size=" ++ int_to_string(ConsistentHash.size(r3)) ++ " get=" ++ to_string(ConsistentHash.get(r3, "k1")))
end
end
```

Expected: every key routes to `new`.

Actual (interpreted / compiled): `size=1 nodes=[new]`, but 180 of 200 keys route to `old` / the same.

Source: `add`, `add_replicas`, `ring_insert`, stdlib/consistent_hash.march.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
