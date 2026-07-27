(* SIMD cross-language benchmark: elementwise (a.(i) +. b.(i)). Matches bench/simd_map2.march *)
(* Manual for-loop -- see bench/ocaml/simd_sum.ml for why. *)
let () =
  let n = 5_000_000 in
  let a = Array.init n (fun i -> float_of_int (i mod 100) /. 100.0) in
  let b = Array.init n (fun i -> float_of_int (i mod 100) /. 100.0 +. 1.0) in
  let combined = Array.make n 0.0 in
  let t0 = Unix.gettimeofday () in
  for i = 0 to n - 1 do
    combined.(i) <- a.(i) +. b.(i)
  done;
  let t1 = Unix.gettimeofday () in
  let total = ref 0.0 in
  for i = 0 to n - 1 do
    total := !total +. combined.(i)
  done;
  Printf.printf "RESULT %f\n" !total;
  Printf.printf "TIME_MS %f\n" ((t1 -. t0) *. 1000.0)
