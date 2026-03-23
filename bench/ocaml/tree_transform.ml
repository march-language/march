(* Tree transform benchmark — matches bench/tree_transform.march (depth=20, 100 passes) *)
(* inc_leaves traverses the tree building a fresh copy each pass (no FBIP). *)
type tree = Leaf of int | Node of tree * tree

let rec make d = if d = 0 then Leaf 0 else Node (make (d - 1), make (d - 1))
let rec inc_leaves = function
  | Leaf n      -> Leaf (n + 1)
  | Node (l, r) -> Node (inc_leaves l, inc_leaves r)
let rec sum_leaves = function Leaf n -> n | Node (l, r) -> sum_leaves l + sum_leaves r

let () =
  let t = ref (make 20) in
  for _ = 1 to 100 do t := inc_leaves !t done;
  Printf.printf "%d\n" (sum_leaves !t)
