(* Higher-order function pipeline — matches bench/list_ops.march *)
(* range 1..1M, map x2, filter mod3=0, fold sum *)
let () =
  let xs = List.init 1_000_000 (fun i -> (i + 1) * 2) in
  let zs = List.filter (fun x -> x mod 3 = 0) xs in
  let total = List.fold_left ( + ) 0 zs in
  Printf.printf "%d\n" total
