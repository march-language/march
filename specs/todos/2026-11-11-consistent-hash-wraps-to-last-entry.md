`[P2]` `ConsistentHash.get` wraps a key past the end of the ring to the LAST entry, not the first (2026-11-11)

`successor` recurses to the end of the list and, on finding no position >= the key, each frame returns its own node only if the recursive call returned `None`. The innermost frame (the last ring entry) answers first, so the wrap-around lands on the last virtual node instead of the first. Keys in the arc above the highest position go to the wrong owner, and the node holding the highest position gets both its own arc and the wrap arc, which skews the distribution.

Repro (`consistent_hash_wrap.march`):

```march
mod A do
needs IO.Console
fn find_key(i, maxh) do
  let k = "key" ++ int_to_string(i)
  if Crypto.sha256(k) > maxh do k else find_key(i + 1, maxh) end
end
fn main(_c : Cap(IO.Console)) do
  -- one virtual node per physical node, so the ring positions are just these three hashes
  let ha = Crypto.sha256("a#0")
  let hb = Crypto.sha256("b#0")
  let hc = Crypto.sha256("c#0")
  let ring = ConsistentHash.add(ConsistentHash.add(ConsistentHash.add(ConsistentHash.new(1), "a", "a"), "b", "b"), "c", "c")
  let lo = if ha < hb && ha < hc do "a" else if hb < hc do "b" else "c" end end
  let hi = if ha > hb && ha > hc do "a" else if hb > hc do "b" else "c" end end
  let maxh = if hi == "a" do ha else if hi == "b" do hb else hc end end
  let k = find_key(0, maxh)
  println("first ring entry (lowest position): " ++ lo ++ "; last (highest): " ++ hi)
  println("key past the last position: " ++ k)
  println("get -> " ++ to_string(ConsistentHash.get(ring, k)) ++ " (wrap-around should give " ++ lo ++ ")")
end
end
```

Expected: `Some(b)` (the lowest position).

Actual (interpreted / compiled): `Some(a)` (the highest position) / the same.

Source: `successor`, stdlib/consistent_hash.march. The fix is to remember the head of the ring and return it when the walk falls off the end.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
