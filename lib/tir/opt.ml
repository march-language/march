(** Optimization coordinator.
    Runs passes in a fixed-point loop, up to 5 iterations.
    Terminates when no pass makes a change.

    Pass order matters:
    - Known_call first: converts ECallPtr → EApp for statically-known closures,
      enabling Inline to see and inline the lifted apply functions
    - Inline second: exposes literal arguments at inlined call sites
    - CProp third: propagates those literals through let chains
    - Fold fourth: evaluates now-literal arithmetic
    - Simplify fifth: identity laws / strength reduction on folded results
    - Fusion.run_struct sixth: collapses chains of record-update operations
    - DCE last: removes let bindings made dead by folding/simplification *)

let run (m : Tir.tir_module) : Tir.tir_module =
  let passes = [Known_call.run; Inline.run; Cprop.run; Fold.run; Simplify.run;
                Fusion.run_struct; Dce.run] in
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
