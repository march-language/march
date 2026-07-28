(** Optimization coordinator.
    Runs passes in a fixed-point loop, up to 5 iterations.
    Terminates when no pass makes a change.

    Pass order matters:
    - Join_points first: hoists common leading lets above ECase, exposing
      shared structure to all downstream passes in the same iteration
    - Known_call second: converts ECallPtr → EApp for statically-known closures,
      enabling Inline to see and inline the lifted apply functions
    - Inline third: exposes literal arguments at inlined call sites
    - Single_use_inline fourth: inlines functions with one remaining call site
    - CProp fifth: propagates those literals through let chains
    - Fold sixth: evaluates now-literal arithmetic
    - Simplify seventh: identity laws / strength reduction on folded results
    - Fusion.run_struct eighth: collapses chains of record-update operations
    - DCE last: removes let bindings made dead by folding/simplification

    The optional [~snap] callback is invoked after each individual pass with
    a label of the form ["tir-opt-{iter}-{pass}"] and the post-pass module.
    When [~snap] is omitted (or is a no-op) behaviour is identical to before. *)

let named_passes = [
  "join-points", Join_points.run;
  "known-call",  Known_call.run;
  "inline",      Inline.run;
  "single-use-inline", Single_use_inline.run;
  "cprop",       Cprop.run;
  "fold",        Fold.run;
  "simplify",    (fun ~changed m -> Simplify.run ~changed m);
  "fusion",      Fusion.run_struct;
  "dce",         Dce.run;
]

let run ?(snap = fun _label _m -> ()) ?(hot_reload = None)
    (m : Tir.tir_module) : Tir.tir_module =
  (* Hot Code Reload: keep boundary functions out of the inliner for this run
     so their call sites survive to codegen as dispatch-table edges.
     Fun.protect ensures the global is reset even if a pass raises. *)
  Inline.boundary_config := hot_reload;
  Fun.protect ~finally:(fun () -> Inline.boundary_config := None) (fun () ->
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
    loop m 5)
