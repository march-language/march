(** Optimization coordinator.
    Runs Inline -> Fold -> Simplify -> DCE in a fixed-point loop.
    Terminates when no pass makes a change, or after 5 iterations. *)

let run (m : Tir.tir_module) : Tir.tir_module =
  let passes = [Inline.run; Fold.run; Simplify.run; Dce.run] in
  let changed = ref false in
  let apply p =
    changed := false;
    List.fold_left (fun acc pass -> pass ~changed acc) p passes
  in
  let rec loop p n =
    if n = 0 then p
    else
      let p' = apply p in
      if not !changed then p'
      else loop p' (n - 1)
  in
  loop m 5
