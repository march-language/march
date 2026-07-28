(* SIMD cross-language benchmark: sum a Float array. Matches bench/simd_sum.march *)
(* OCaml's `float array` is unboxed/flat, the fair native-array comparison.
   A manual for-loop, not Array.fold_left, since fold_left's polymorphic
   accumulator boxes every float (~5x slower) -- not what a performance-
   conscious OCaml numeric loop looks like.
   Data generation is NOT timed -- see bench/simd_sum.march for why. *)
let () =
  let n = 5_000_000 in
  let arr = Array.init n (fun i -> float_of_int (i mod 100) /. 100.0) in
  let t0 = Unix.gettimeofday () in
  let total = ref 0.0 in
  for i = 0 to n - 1 do
    total := !total +. arr.(i)
  done;
  let t1 = Unix.gettimeofday () in
  Printf.printf "RESULT %f\n" !total;
  Printf.printf "TIME_MS %f\n" ((t1 -. t0) *. 1000.0)
