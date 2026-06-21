(* Top-level discharge: cache lookup -> shared solver -> cache store, mapping the
   raw solver verdict to a caller-facing outcome.  The solver is created lazily
   and shared across the run; if z3 is unavailable the result is Unverified and
   is NOT cached (z3 may be installed before the next build). *)

type outcome =
  | Verified                          (* goal proved (unsat of its negation) *)
  | Refuted of (string * string) list (* goal can fail; counterexample model *)
  | Unverified                        (* unknown, or z3 unavailable *)

(* None  = not yet attempted; Some None = attempted, z3 absent; Some (Some s) = live. *)
let shared_solver : Solver.t option option ref = ref None

let get_solver () : Solver.t option =
  match !shared_solver with
  | Some s -> s
  | None ->
      let s = Solver.create () in
      shared_solver := Some s;
      s

let discharge ~root ?(preamble = "") (vc : Smt.vc) : outcome =
  let key = Vc_cache.key_of_vc ~preamble vc in
  let result =
    match Vc_cache.lookup ~root key with
    | Some r -> r
    | None -> (
        match get_solver () with
        | None -> Solver.Unknown (* z3 unavailable; do not cache *)
        | Some s ->
            let r = Solver.check ~preamble s vc in
            Vc_cache.store ~root key r;
            r)
  in
  match result with
  | Solver.Unsat -> Verified
  | Solver.Sat model -> Refuted model
  | Solver.Unknown -> Unverified
