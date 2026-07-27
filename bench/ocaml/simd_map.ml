(* SIMD cross-language benchmark: elementwise (x * 2.0 + 1.0). Matches bench/simd_map.march *)
(* Manual for-loop into a pre-allocated array -- see bench/ocaml/simd_sum.ml
   for why (Array.map/fold_left's polymorphic closures box each float). *)
let () =
  let n = 5_000_000 in
  let arr = Array.init n (fun i -> float_of_int (i mod 100) /. 100.0) in
  let mapped = Array.make n 0.0 in
  let t0 = Unix.gettimeofday () in
  for i = 0 to n - 1 do
    mapped.(i) <- arr.(i) *. 2.0 +. 1.0
  done;
  let t1 = Unix.gettimeofday () in
  let total = ref 0.0 in
  for i = 0 to n - 1 do
    total := !total +. mapped.(i)
  done;
  Printf.printf "RESULT %f\n" !total;
  Printf.printf "TIME_MS %f\n" ((t1 -. t0) *. 1000.0)
