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

(* ── Ground fast path ──────────────────────────────────────────────────────
   A call with literal arguments reaches the solver as a CLOSED goal — no
   symbols, e.g. `(>= 8 0)` for `Crypto.random_hex(8)`.  Asking z3 is not just
   wasted work: the query runs under the per-query wall-clock timeout, so on a
   loaded machine even `8 >= 0` can come back `unknown`, which surfaces as a
   spurious "precondition … was NOT verified (solver-undecided)" hint on a
   literal argument.

   [ground_eval] evaluates the Int/Bool fragment exactly as SMT-LIB defines
   it, returning [None] for anything else (a symbol, a function application,
   division — whose Euclidean semantics differ from OCaml's — floats, sets,
   datatypes) and on any OCaml integer overflow, since SMT integers are
   unbounded.  [None] means "ask the solver as before". *)
type ground = GInt of int | GBool of bool

let rec ground_eval (t : Smt.term) : ground option =
  let int t = match ground_eval t with Some (GInt n) -> Some n | _ -> None in
  let bool t = match ground_eval t with Some (GBool b) -> Some b | _ -> None in
  let arith f a b = match int a, int b with Some x, Some y -> f x y | _ -> None in
  let cmp f a b =
    match int a, int b with Some x, Some y -> Some (GBool (f x y)) | _ -> None
  in
  let add x y =
    let s = x + y in
    (* Overflow iff both operands share a sign the sum does not. *)
    if (x >= 0) = (y >= 0) && (s >= 0) <> (x >= 0) then None else Some (GInt s)
  in
  let mul x y =
    if x = 0 || y = 0 then Some (GInt 0)
    else
      let p = x * y in
      if p / y <> x || (x = -1 && y = min_int) || (y = -1 && x = min_int) then None
      else Some (GInt p)
  in
  let neg x = if x = min_int then None else Some (GInt (- x)) in
  match t with
  | Smt.IntLit n -> Some (GInt n)
  | Smt.BoolLit b -> Some (GBool b)
  | Smt.Add (a, b) -> arith add a b
  | Smt.Sub (a, b) -> arith (fun x y -> if y = min_int then None else add x (- y)) a b
  | Smt.MulLit (k, a) -> (match int a with Some x -> mul k x | None -> None)
  | Smt.Mul (a, b) -> arith mul a b
  | Smt.Neg a -> (match int a with Some x -> neg x | None -> None)
  | Smt.Not a -> Option.map (fun b -> GBool (not b)) (bool a)
  | Smt.And (a, b) -> (match bool a, bool b with Some x, Some y -> Some (GBool (x && y)) | _ -> None)
  | Smt.Or (a, b) -> (match bool a, bool b with Some x, Some y -> Some (GBool (x || y)) | _ -> None)
  | Smt.Implies (a, b) ->
    (match bool a, bool b with Some x, Some y -> Some (GBool ((not x) || y)) | _ -> None)
  | Smt.Eq (a, b) | Smt.Ne (a, b) ->
    let same =
      match ground_eval a, ground_eval b with
      | Some (GInt x), Some (GInt y) -> Some (x = y)
      | Some (GBool x), Some (GBool y) -> Some (x = y)
      | _ -> None
    in
    (match t, same with
     | Smt.Eq _, Some s -> Some (GBool s)
     | Smt.Ne _, Some s -> Some (GBool (not s))
     | _ -> None)
  | Smt.Lt (a, b) -> cmp ( < ) a b
  | Smt.Le (a, b) -> cmp ( <= ) a b
  | Smt.Gt (a, b) -> cmp ( > ) a b
  | Smt.Ge (a, b) -> cmp ( >= ) a b
  | _ -> None

(* A closed goal that evaluates to true is valid, so it is [Verified] under ANY
   assumption set — exactly z3's answer (unsat of assumptions ∧ ¬goal), minus
   the timeout.  A closed goal that evaluates to FALSE is deliberately left to
   the solver: it is still [Verified] when the assumptions are contradictory
   (an unreachable call site), and only z3 can tell.  This also covers the
   violation direction: for `random_hex(-1)` the caller's `¬G` discharge is the
   closed, true `(not (>= (- 1) 0))`. *)
let ground_verified (vc : Smt.vc) : bool =
  ground_eval vc.Smt.goal = Some (GBool true)

let discharge ~root ?(preamble = "") (vc : Smt.vc) : outcome =
  if ground_verified vc then Verified else
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
