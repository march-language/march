`[P3]` `OrderedMap.filter` can return a tree that breaks the AVL balance invariant (2026-11-11)

`tree_filter` filters both subtrees and joins them with a single `balance(make_node(l2, k, v, r2))`. One
rotation step only repairs a height difference of 2, but filtering can leave the two sides arbitrarily
far apart. Lookups stay correct (key order is kept); the O(log n) depth bound is lost, and later `put`
calls do not restore it.

Repro (walks `m.tree` and reports the worst `|height(l) - height(r)|` of any node):

```march
mod A do
needs IO.Console
-- real height, and the worst |height(l) - height(r)| anywhere in the tree
@[no_warn_recursion]
fn hb(t) : (Int, Int) do
  match t do
  OrderedMap.Leaf -> (0, 0)
  OrderedMap.Node(l, _, _, r, _) -> do
    let (hl, bl) = hb(l)
    let (hr, br) = hb(r)
    let d = if hl > hr do hl - hr else hr - hl end
    let worst = if d > bl do (if d > br do d else br end) else (if bl > br do bl else br end) end
    ((if hl > hr do hl else hr end) + 1, worst)
  end
  end
end
fn build(i : Int, n : Int, acc : List((Int, Int))) : List((Int, Int)) do
  if i > n do acc else build(i + 1, n, Cons((i, i), acc)) end
end
fn report(label : String, m) do
  let (h, worst) = hb(m.tree)
  println(label ++ ": size=" ++ to_string(OrderedMap.size(m)) ++ " height=" ++ to_string(h) ++ " worst_imbalance=" ++ to_string(worst))
end
fn main(_c : Cap(IO.Console)) do
  let m = OrderedMap.from_list(build(1, 1023, Nil), fn (a, b) -> if a < b do 0 - 1 else if a > b do 1 else 0 end end)
  report("full 1..1023", m)
  let f1 = OrderedMap.filter(m, fn (k, v) -> k <= 3 || k > 512)
  report("keep k<=3 or k>512", f1)
  let f2 = OrderedMap.filter(m, fn (k, v) -> k > 1000 || k % 64 == 0)
  report("keep k>1000 or k%64==0", f2)
  let f3 = OrderedMap.filter(m, fn (k, v) -> k < 3 || k == 600)
  report("keep k<3 or k==600", f3)
  println("lookups still right: " ++ to_string(OrderedMap.get(f1, 2)) ++ " " ++ to_string(OrderedMap.get(f1, 600)) ++ " " ++ to_string(OrderedMap.get(f1, 100)))
  let f4 = OrderedMap.put(f1, 4, 4)
  report("f1 after put 4", f4)
end
end
```

Expected: every node has subtree heights within 1 of each other (514 entries fit in height 10 with imbalance at most 1).

Actual (interpreted / compiled): interpreted and compiled agree: keeping `k <= 3 || k > 512` of 1..1023 gives worst imbalance 6; keeping `k > 1000 || k % 64 == 0` gives 3; a following `put` leaves imbalance 4.

Source: `tree_filter` in `stdlib/ordered_map.march`. One fix direction: join the filtered subtrees with a height-aware join, or rebuild from the filtered sorted list.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
