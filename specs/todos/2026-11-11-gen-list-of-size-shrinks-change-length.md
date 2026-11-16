`[P2]` Gen.list_of_size(n, g) shrinks to lists whose length is not n (2026-11-11)

`list_fixed_tree` keeps the length for the first level of shrink candidates, but builds each candidate with `list_tree_from_elems`, the tree of the variable-length `list` generator. From the second level on, candidates include shorter lists down to `[]`. A property that relies on the fixed length can be reported with a shrunk counterexample the generator could never have produced.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let rng = { s0: 1, s1: 2, s2: 3, s3: 4 }
  let (t, _) = Gen.run(Gen.list_of_size(3, Gen.int(0, 100)), rng, 10)
  println("root:    " ++ to_string(Gen.tree_root(t)))
  let kids = Gen.tree_children(t)
  println("level 1: " ++ to_string(List.map(kids, fn k -> List.length(Gen.tree_root(k)))))
  let grand = List.flat_map(kids, fn k -> Gen.tree_children(k))
  let lens = List.map(grand, fn k -> List.length(Gen.tree_root(k)))
  println("level 2: " ++ to_string(List.length(lens)) ++ " candidates, of which length != 3: " ++ to_string(List.length(List.filter(lens, fn n -> n != 3))))
  println("level 2 first five: " ++ to_string(List.map(List.take(grand, 5), fn k -> Gen.tree_root(k))))
end
end
```

Expected: every shrink candidate at every depth has length 3

Actual (interpreted / compiled): `level 2: 372 candidates, of which length != 3: 38`, first five `[[], [38, 76], [0, 0, 76], [0, 19, 76], [0, 28, 76]]` / same

Source: `list_fixed_tree` in stdlib/gen.march.
