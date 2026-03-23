(* Binary Trees benchmark — matches bench/binary_trees.march (depth=15) *)
type tree = Leaf | Node of tree * tree

let rec make d = if d = 0 then Leaf else Node (make (d - 1), make (d - 1))
let rec check = function Leaf -> 1 | Node (l, r) -> check l + check r + 1

let () =
  let n = 15 and min_depth = 4 in
  let max_depth = max n (min_depth + 2) in
  let stretch = max_depth + 1 in
  Printf.printf "stretch tree of depth %d check: %d\n" stretch (check (make stretch));
  let long_lived = make max_depth in
  let d = ref min_depth in
  while !d <= max_depth do
    let iters = 1 lsl (max_depth - !d + min_depth) in
    let sum = ref 0 in
    for _ = 1 to iters do sum := !sum + check (make !d) done;
    Printf.printf "%d trees of depth %d check: %d\n" iters !d !sum;
    d := !d + 2
  done;
  Printf.printf "long lived tree of depth %d check: %d\n" max_depth (check long_lived)
