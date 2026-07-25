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

(* Kill + reap the shared z3 child and forget it; a later discharge lazily
   respawns.  Call at the end of a solving scope (the compiler calls it after
   its refinement passes); also registered as an at_exit on first spawn so
   every exit path — including `exit 1` on type errors — reaps the child. *)
let shutdown () : unit =
  match !shared_solver with
  | Some (Some s) ->
      shared_solver := None;
      Solver.close s
  | _ -> ()

let at_exit_registered = ref false

let get_solver () : Solver.t option =
  match !shared_solver with
  | Some s -> s
  | None ->
      let s = Solver.create () in
      shared_solver := Some s;
      (match s with
       | Some _ when not !at_exit_registered ->
           at_exit_registered := true;
           at_exit shutdown
       | _ -> ());
      s

(* One check against a live solver.  A broken pipe / EOF / garbage verdict all
   mean the z3 child is dead or wedged: reap it and clear the slot so the
   caller can respawn (supervised restart). *)
let try_check ~preamble (s : Solver.t) (vc : Smt.vc) : Solver.result option =
  try Some (Solver.check ~preamble s vc)
  with End_of_file | Sys_error _ | Failure _ | Unix.Unix_error (_, _, _) ->
    shared_solver := None;
    Solver.close s;
    None

let discharge ~root ?(preamble = "") (vc : Smt.vc) : outcome =
  let key = Vc_cache.key_of_vc ~preamble vc in
  let result =
    match Vc_cache.lookup ~root key with
    | Some r -> r
    | None -> (
        let checked =
          match get_solver () with
          | None -> None (* z3 unavailable; do not cache *)
          | Some s -> (
              match try_check ~preamble s vc with
              | Some r -> Some r
              | None -> (
                  (* Solver died mid-run: restart once.  If the replacement
                     also fails, mark z3 unavailable for the rest of the run
                     rather than respawning per VC. *)
                  match get_solver () with
                  | None -> None
                  | Some s2 -> (
                      match try_check ~preamble s2 vc with
                      | Some r -> Some r
                      | None ->
                          shared_solver := Some None;
                          None)))
        in
        match checked with
        | Some Solver.Unknown ->
            (* Do NOT cache `unknown`.  It is the absence of an answer rather
               than an answer about fixed SMT text, and persisting it is
               actively harmful in two ways:

               - It is nondeterministic.  The solver runs under a wall-clock
                 timeout (Solver.create sets :timeout), so a loaded machine can
                 turn a decidable VC into `unknown` — and caching freezes that
                 accident into the project's cache for every later build.
               - Since the resync fix, a MALFORMED VC also yields `unknown`.
                 Caching that makes a compiler bug's "silently unchecked"
                 verdict outlive the fix to the compiler bug — which is exactly
                 how a warm cache masked two refinement regression tests.

               Not caching costs only re-asking the VCs nobody could decide,
               which are precisely the ones where re-asking might now succeed:
               a quieter machine, a newer z3, or a fixed encoding.  Genuine
               verdicts (unsat / sat-with-model) are facts about fixed text and
               are still cached, so the hot path is unaffected. *)
            Solver.Unknown
        | Some r ->
            Vc_cache.store ~root key r;
            r
        | None -> Solver.Unknown)
  in
  match result with
  | Solver.Unsat -> Verified
  | Solver.Sat model -> Refuted model
  | Solver.Unknown -> Unverified
