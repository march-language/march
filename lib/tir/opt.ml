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
    - DCE last: removes let bindings made dead by folding/simplification

    The optional [~snap] callback is invoked after each individual pass with
    a label of the form ["tir-opt-{iter}-{pass}"] and the post-pass module.
    When [~snap] is omitted (or is a no-op) behaviour is identical to before. *)

let named_passes = [
  "known-call",  Known_call.run;
  "inline",      Inline.run;
  "cprop",       Cprop.run;
  "fold",        Fold.run;
  "simplify",    Simplify.run;
  "fusion",      Fusion.run_struct;
  "dce",         Dce.run;
]

let run ?(snap = fun _label _m -> ()) (m : Tir.tir_module) : Tir.tir_module =
  let changed = ref false in
  let apply iter p =
    changed := false;
    List.fold_left (fun acc (label, pass) ->
      let acc' = pass ~changed acc in
      snap (Printf.sprintf "tir-opt-%d-%s" iter label) acc';
      acc'
    ) p named_passes
  in
  let rec loop p n =
    if n = 0 then p
    else
      let iter = 6 - n in
      let p' = apply iter p in
      if not !changed then p'
      else loop p' (n - 1)
  in
  loop m 5
