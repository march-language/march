(** Optimization coordinator.
    Runs Inline -> CProp -> Fold -> Simplify -> DCE in a fixed-point loop.
    Terminates when no pass makes a change, or after 5 iterations.

    Pass order matters:
    - Inline first: exposes literal arguments at inlined call sites
    - CProp second: propagates those literals through let chains
    - Fold third: evaluates now-literal arithmetic
    - Simplify fourth: identity laws / strength reduction on folded results
    - DCE last: removes let bindings made dead by folding/simplification *)

let run (m : Tir.tir_module) : Tir.tir_module =
  let passes = [Inline.run; Cprop.run; Fold.run; Simplify.run; Dce.run] in
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
