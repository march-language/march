`[P2]` `Hamt` loses a key, then loops forever, when two hashes agree on the low 35 bits (2026-11-11)

The trie consumes 7 levels of 5 bits. Two keys whose hashes agree on the low 35 bits but differ above
them are put by `make_branch` into one `HCollision` tagged with the first hash. `get` and `remove` compare
the bucket tag with the full hash of the key, so the second key is never found or removed. Inserting the
second key again never terminates: `hamt_insert` on a collision with a different hash rebuilds the bucket
by re-inserting, which builds the same shape again. The module header documents the lookup miss and asks
callers to keep hashes below 2^35; `Map` (30-bit mask) and `DataFrame` (31-bit mask) do, so only direct
`Hamt` users with an unmasked hash are affected. The builtin `hash` returns 62 bits: `hash(38155)` and
`hash(279193)` are such a pair.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let eq = fn (a, b) -> a == b
  let id = fn k -> k
  let k2 = 1 + 34359738368
  let h = Hamt.insert(Hamt.insert(Hamt.empty(), 1, "a", id, eq), k2, "b", id, eq)
  println(to_string(Hamt.get(h, k2, id, eq)))
  println(to_string(Hamt.size(Hamt.remove(h, k2, id, eq))))
  println(to_string(Hamt.size(Hamt.insert(h, k2, "c", id, eq))))
end
end
```

Expected: `Some(b)`, `1`, `2`.

Actual (interpreted / compiled): interpreted prints `None`, `2`, then hangs in the last insert (killed after 60 s); compiled prints `None`, `2`, then dies with `fatal SIGBUS ... fault in its stack guard page (overflow)`.

Source: `make_branch`, `hamt_get`, `hamt_insert` (the `HCollision` arm with `ch != h`) and `hamt_remove` in `stdlib/hamt.march`. One fix direction: mask the hash to 35 bits once in the public `get` / `insert` / `remove`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

## Fixed (2026-11-25)

`Hamt.get`, `Hamt.insert` and `Hamt.remove` keep only the low 35 bits of what `hash_fn`
returns (`path_hash`, one `int_and`), so every hash inside the trie and every collision
bucket's tag is below 2^35. Two keys that agree on those bits now have equal hashes and
share a bucket as ordinary collisions. A negative hash works too. The module header no
longer asks callers to mask.

Tests: `test/stdlib/test_hamt.march`, group "hashes that agree on the low 35 bits" (five
cases: both keys found, the second removed, the second re-inserted, a third key, negative
hashes). On main the file never finished interpreted (killed after 60 s); it passes
interpreted and compiled (`--compile --test`: 49 tests).

Cost: `bench/hash_map_bench.march` at `--opt 2`, six runs each against main's stdlib:
9.92 to 9.97 billion instructions before and 9.92 to 9.98 after, the same within the run
to run spread.

Not done: the plan also asks for a law in the stdlib laws pass. `Hamt` is untyped and
takes its hash and equality as closures, which that pass (refinement contracts) cannot
state; no law was added.
