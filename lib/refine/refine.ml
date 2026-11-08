(* Top-level discharge: cache lookup -> shared solver -> cache store, mapping the
   raw solver verdict to a caller-facing outcome.  The solver is created lazily
   and shared across the run; if z3 is unavailable the result is Unverified and
   is NOT cached (z3 may be installed before the next build); neither is a
   query z3 rejected, or one whose solver hung or died. *)

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
(* Set when z3 died or stopped answering during this run; the run report
   turns it into the solver_unavailable warning. *)
let solver_failure : string option ref = ref None

(* Whether this run asked z3 anything (a VC-cache miss reached the solver);
   the z3 warning is only for runs whose verdicts depended on z3. *)
let queried = ref false

(* Queries that reached the solver this run, and those that got no answer
   (z3 missing, or it died or hung on them). *)
let queries_asked = ref 0

let queries_unanswered = ref 0

(** The z3 report for this run: [None] when no query reached the solver;
    otherwise its health, where a z3 that died or hung mid-run is [Broken]
    with that reason. *)
let run_report () : Solver.health option =
  if not !queried then None
  else
    match (Solver.health (), !solver_failure) with
    | ((Solver.Missing _ | Solver.Broken _) as h), _ -> Some h
    | (Solver.Healthy { path; _ } | Solver.Mismatch { path; _ }), Some reason ->
        Some (Solver.Broken { path; reason })
    | h, None -> Some h

(** Whether z3 could not be used at all this run (missing, or broken from
    the start), as opposed to failing partway: only then is every undecided
    obligation the solver's absence. *)
let solver_unusable () : bool =
  !queried && (match Solver.health () with Solver.Missing _ | Solver.Broken _ -> true | _ -> false)

(* Hangs since the last answer.  One hung query costs only itself (a starved
   query on a loaded machine), but a z3 that hangs on every query would cost a
   backstop per query for the whole run, so after [max_hangs] in a row with no
   answer between them z3 is given up on for the run. *)
let consecutive_hangs = ref 0

let max_hangs = 3

let try_check ?(assume = []) ~preamble (s : Solver.t) (vc : Smt.vc)
    : (Solver.result, [ `Hung | `Died ]) result =
  let fail reason why =
    solver_failure := Some reason;
    shared_solver := None;
    Solver.close s;
    Error why
  in
  match Solver.check ~preamble ~assume s vc with
  | r -> consecutive_hangs := 0; Ok r
  | exception Solver.Hung ->
      incr consecutive_hangs;
      let e = fail "stopped responding" `Hung in
      if !consecutive_hangs >= max_hangs then shared_solver := Some None;
      e
  | exception (End_of_file | Sys_error _ | Failure _ | Unix.Unix_error (_, _, _)) -> fail "exited mid-run" `Died

(* ── Ground fast path ──────────────────────────────────────────────────────
   A call with literal arguments reaches the solver as a CLOSED goal — no
   symbols, e.g. `(>= 8 0)` for `Crypto.random_hex(8)`.  Asking z3 is wasted
   work (a process round trip and a reset per query).

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

(* ── Reflection stage 2 (specs/2026-10-29-refinement-reflection-design.md §4.4)
   A stage-2 query carries one Bool ASSUMPTION LITERAL per unfolding (a
   declared constant named [stage2_literal_prefix]...), each unfolding
   asserted as `lit => equation`.  It is checked with `check-sat-assuming`
   over those literals, under its own (smaller) rlimit, and a proof's unsat
   core (the literals it used) is left in [last_core] and cached beside the
   verdict, so a warm proof reports the same `uses:` as a cold one.  An
   `unknown` is also remembered in process ([stage2_unknown]), keyed by the
   VC text, z3's version and the rlimit, so a re-check in the same process
   does not pay for the same query twice. *)
let stage2_literal_prefix = "|$ru_"

(* The per-query limits live in [Solver]; these are the same refs. *)
let default_rlimit = Solver.default_rlimit

let stage2_rlimit = Solver.stage2_rlimit

(** The literals of the last stage-2 proof ([[]] after any other discharge). *)
let last_core : string list ref = ref []

(** Every unfolding literal the last discharged query assumed (its own
    frontier), proved or not; [[]] after a stage-1 query.  A proof whose core
    names none of them ([last_core] empty, congruence alone) used none of their
    definitions, and its `uses:` falls back to this query's frontier rather than
    every unfolding the whole stage-2 run made. *)
let last_assumed : string list ref = ref []

let stage2_queries = ref 0

let stage2_unknown_hits = ref 0

let stage2_unknown : (string, unit) Hashtbl.t = Hashtbl.create 16

let stage2_literals (vc : Smt.vc) : string list =
  List.filter_map
    (fun (n, s) -> if s = Smt.SBool && String.starts_with ~prefix:stage2_literal_prefix n then Some n else None)
    vc.Smt.decls

(* A query the caller knows z3 would reject (a reflected logic symbol that
   reached a discharge path which never declares it): refused as [Unverified]
   instead of being sent, so one such query never shows up as a malformed VC.
   Set by [March_refinecheck.Refine_reflect]; the default admits everything. *)
let well_formed : (string -> Smt.vc -> bool) ref = ref (fun _ _ -> true)

(* A verdict is stored only from a z3 with an identity (a version that
   probed): one whose `--version` fails would store under the "noz3" key, to
   be served to a later run that has no z3 at all. *)
let storable () = Solver.identity () <> None

let discharge ~root ?(preamble = "") (vc : Smt.vc) : outcome =
  last_core := [];
  last_assumed := [];
  if ground_verified vc then Verified else
  if not (!well_formed preamble vc) then Unverified else
  let assume = stage2_literals vc in
  last_assumed := assume;
  let key = Vc_cache.key_of_vc ~preamble vc in
  let neg_key =
    if assume = [] then ""
    else key (* already carries the z3 version and the limits *)
  in
  if assume <> [] && Hashtbl.mem stage2_unknown neg_key
     && Sys.getenv_opt "MARCH_REFLECT_PERTURB" <> Some "no-negcache" then begin
    incr stage2_unknown_hits;
    Unverified
  end else
  let result =
    match Vc_cache.lookup ~root key with
    | Some r ->
        (if assume <> [] && r = Solver.Unsat then
           match Vc_cache.lookup_core ~root key with Some c -> last_core := c | None -> ());
        r
    | None -> (
        if assume <> [] then incr stage2_queries;
        queried := true;
        incr queries_asked;
        let checked =
          match get_solver () with
          | None -> None (* z3 unavailable; do not cache *)
          | Some s -> (
              match try_check ~assume ~preamble s vc with
              | Ok r -> Some r
              | Error `Hung ->
                  (* The query outlived the backstop.  Retrying it would only
                     hang again, so it costs itself alone: unanswered and not
                     cached, and the next query gets a fresh z3. *)
                  None
              | Error `Died -> (
                  (* Solver died mid-run: restart once.  If the replacement
                     also fails, mark z3 unavailable for the rest of the run
                     rather than respawning per VC. *)
                  match get_solver () with
                  | None -> None
                  | Some s2 -> (
                      match try_check ~assume ~preamble s2 vc with
                      | Ok r -> Some r
                      | Error `Hung -> None
                      | Error `Died ->
                          shared_solver := Some None;
                          None)))
        in
        if checked = None then incr queries_unanswered;
        match checked with
        | Some Solver.Rejected ->
            (* z3 rejected the query: a compiler bug's encoding, not an
               answer.  Never cached, so the fix to the encoding is not masked
               by a warm cache. *)
            Solver.Rejected
        | Some Solver.Unknown ->
            (* An `unknown` under the rlimit is an answer about fixed text, a
               fixed z3 and a fixed limit (all in the key), so it is cached
               like any other verdict. *)
            if storable () then Vc_cache.store ~root key Solver.Unknown;
            if assume <> [] then Hashtbl.replace stage2_unknown neg_key ();
            Solver.Unknown
        | Some r ->
            if storable () then Vc_cache.store ~root key r;
            if assume <> [] && r = Solver.Unsat then begin
              last_core := !Solver.last_core;
              if storable () then Vc_cache.store_core ~root key !last_core
            end;
            r
        | None -> Solver.Rejected)
  in
  match result with
  | Solver.Unsat -> Verified
  | Solver.Sat model -> Refuted model
  | Solver.Unknown | Solver.Rejected -> Unverified
