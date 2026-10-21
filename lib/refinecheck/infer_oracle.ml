(* The acceptance oracle for inference-lite
   (specs/2026-10-20-refinement-suggest-lite-design.md §2).

   One probe installs one candidate at one slot on a pruned tree (the target
   plus every caller in the unit), re-walks it with the REAL checker, and diffs
   the ledger site by site against the unhypothesised walk.  Admissibility per
   kind:
     - a precondition (K1/K5 on a parameter) closes a site in the body, opens
       none, creates no violation; a new violation at a CALLER refuses it
       (D2); it must leave the parameters satisfiable;
     - a return (K2/K5 on the return) must be TRUE (the checker's own
       postcondition oracle) and USEFUL (closes a caller site, opens none).
   "Not refuted" is never TRUE: a skipped postcondition rejects. *)

module A = March_ast.Ast
module PI = Precond_infer
module PO = Postcond_infer
module IS = Infer_slot
module IV = Infer_vocab
module LD = Ledger_diff
module RC = Refine_check

type verdict =
  | Accept of { closes : LD.key list; new_skipped : LD.key list }
  | Reject of string * string   (* reason (closed set, design §4.2), detail *)
  | Refuse of PI.refusal

(* Everything a slot's probes share: computed once per slot. *)
type ctx = {
  qualified : string;
  fd0 : A.fn_def;
  rebuild : A.fn_def -> A.decl list;
  defs : (string, RC.fn_sig option) Hashtbl.t;
  base : LD.snapshot;
  in_body : A.span -> bool;
}

let split_qualified (q : string) : string list * string =
  match List.rev (String.split_on_char '.' q) with
  | name :: rpath -> (List.rev rpath, name)
  | [] -> ([], q)

let prepare ~(root : string) ~(decls : A.decl list) (s : IS.slot) : ctx option =
  let path, name = split_qualified s.IS.fn in
  match PI.prune_with_callers path name decls with
  | None -> None
  | Some (fd0, rebuild) ->
    let defs = RC.collect_all_defs decls in
    let base = PI.walk_ledger ~root ~defs (rebuild fd0) in
    let in_body (sp : A.span) =
      List.exists (fun (c : A.fn_clause) -> IV.within c.A.fc_span sp) fd0.A.fn_clauses
    in
    Some { qualified = s.IS.fn; fd0; rebuild; defs; base; in_body }

let defs_with (cx : ctx) (hyp : A.fn_def) =
  let d = Hashtbl.copy cx.defs in
  Hashtbl.replace d cx.qualified (RC.entry_of_sig (RC.sig_of_fn hyp));
  d

let precondition ?(allow_caller_violations = false) ~(root : string) (cx : ctx) (hyp : A.fn_def) : verdict =
  let after = PI.walk_ledger ~root ~defs:(defs_with cx hyp) (cx.rebuild hyp) in
  let delta = LD.diff ~before:cx.base ~after in
  let caller_viol =
    List.filter (fun (k : LD.key) -> not (cx.in_body k.LD.span)) (LD.new_violated delta)
  in
  let without_callers =
    List.filter
      (fun ((k : LD.key), c) -> not (c = LD.New_violated && not (cx.in_body k.LD.span)))
      delta
  in
  if caller_viol <> [] then
    if not (PI.admissible without_callers) then Reject ("not-useful", "creates violations and closes nothing in the body")
    else if not (PI.satisfiable ~root hyp) then Reject ("unsatisfiable", "the parameters admit no value")
    else if allow_caller_violations then
      (* D2's override: admissible but for the callers it breaks. *)
      Accept { closes = LD.closed without_callers; new_skipped = LD.new_skipped without_callers }
    else
      Refuse
        { PI.rf_reason = "caller-violation";
          rf_sites = List.sort_uniq compare (List.map (fun (k : LD.key) -> k.LD.span) caller_viol) }
  else if LD.opened delta <> [] then Reject ("opens-site", "a previously proved obligation is no longer proved")
  else if not (PI.admissible delta) then Reject ("not-useful", "closes no site")
  else if not (PI.satisfiable ~root hyp) then Reject ("unsatisfiable", "the parameters admit no value")
  else Accept { closes = LD.closed delta; new_skipped = LD.new_skipped delta }

let return_ ~(root : string) (cx : ctx) (hyp : A.fn_def) : verdict =
  if not (PO.post_holds ~root hyp) then Reject ("not-true", "the checker does not prove this return")
  else
    let after = PI.walk_ledger ~root ~defs:(PO.defs_with_post cx.defs ~qualified:cx.qualified hyp) (cx.rebuild hyp) in
    let delta = LD.diff ~before:cx.base ~after in
    if LD.opened delta <> [] then Reject ("opens-site", "a previously proved obligation is no longer proved")
    else if not (PI.admissible delta) then Reject ("not-useful", "closes no caller site")
    else Accept { closes = LD.closed delta; new_skipped = LD.new_skipped delta }

(* An element return (K4) is TRUE when the checker's own element-return gate
   admits it: one gate round over the hypothesis tree, read back from
   [Refine_param.elem_ret_proved].  The table is global and the gate writes it,
   so it is restored around the probe; while the probe's caller walk runs the
   entry is present, which is what lets the callers USE the proved return. *)
let with_elem_table (f : unit -> 'a) : 'a =
  let saved = Hashtbl.copy Refine_param.elem_ret_proved in
  Fun.protect
    ~finally:(fun () ->
      Hashtbl.reset Refine_param.elem_ret_proved;
      Hashtbl.iter (fun k v -> Hashtbl.replace Refine_param.elem_ret_proved k v) saved)
    f

let elem_ret_holds ~(root : string) ~defs (decls : A.decl list) ~(fn : string) : bool =
  Hashtbl.remove Refine_param.elem_ret_proved fn;
  (try RC.gate_elem_returns ~root defs decls with _ -> ());
  Hashtbl.mem Refine_param.elem_ret_proved fn

let elem_return ~(root : string) (cx : ctx) (hyp : A.fn_def) : verdict =
  with_elem_table @@ fun () ->
  let defs = defs_with cx hyp in
  let tree = cx.rebuild hyp in
  if not (elem_ret_holds ~root ~defs tree ~fn:cx.qualified) then
    Reject ("not-true", "the checker does not prove this element return")
  else
    let after = PI.walk_ledger ~root ~defs tree in
    let delta = LD.diff ~before:cx.base ~after in
    if LD.opened delta <> [] then Reject ("opens-site", "a previously proved obligation is no longer proved")
    else if not (PI.admissible delta) then Reject ("not-useful", "closes no caller site")
    else Accept { closes = LD.closed delta; new_skipped = LD.new_skipped delta }

(* K7: an annotated accumulator.  TRUE: the annotation's own obligation (base
   and step) is proved — an `accumulator-base-unproved` /
   `accumulator-step-unproved` skip rejects.  USEFUL: a site in the step or on
   the fold result closes; nothing opens; no violation. *)
let accumulator ~(root : string) (cx : ctx) (hyp : A.fn_def) : verdict =
  let after = PI.walk_ledger ~root ~defs:(defs_with cx hyp) (cx.rebuild hyp) in
  let acc_skip =
    List.exists
      (fun (_, v) ->
        match v with
        | Obligation.Skipped r ->
          let n = Obligation.reason_name r in
          n = "accumulator-base-unproved" || n = "accumulator-step-unproved"
        | _ -> false)
      after
  in
  let delta = LD.diff ~before:cx.base ~after in
  if acc_skip then Reject ("not-true", "the accumulator invariant's base or step is not proved")
  else if LD.new_violated delta <> [] then Reject ("not-true", "creates a violation")
  else if LD.opened delta <> [] then Reject ("opens-site", "a previously proved obligation is no longer proved")
  else if not (PI.admissible delta) then Reject ("not-useful", "closes no site")
  else Accept { closes = LD.closed delta; new_skipped = LD.new_skipped delta }

(* The checker reads a callee's DEFINITION (not only its signature) from
   [Refine_param.fn_defs_tbl], registered once by [check_module] from the
   unhypothesised function — that is where a caller finds a proved element
   return ([Refine_check.declared_elem_return]).  A probe puts the hypothesis
   there for its duration. *)
let with_hyp_def (cx : ctx) (hyp : A.fn_def) (f : unit -> 'a) : 'a =
  let key = cx.qualified in
  let saved = Hashtbl.find_opt Refine_param.fn_defs_tbl key in
  let saved_abs = Hashtbl.find_opt RC.abstracts_tbl key in
  (match saved with
   | Some (prefix, _) -> Hashtbl.replace Refine_param.fn_defs_tbl key (prefix, hyp)
   | None -> ());
  (* [callee_abstracts] memoises a function's abstract names from the
     definition table: withdraw the memo so the hypothesis is read. *)
  Hashtbl.remove RC.abstracts_tbl key;
  Fun.protect
    ~finally:(fun () ->
      (match saved with
       | Some v -> Hashtbl.replace Refine_param.fn_defs_tbl key v
       | None -> ());
      match saved_abs with
      | Some v -> Hashtbl.replace RC.abstracts_tbl key v
      | None -> Hashtbl.remove RC.abstracts_tbl key)
    f

(* A probe that raises costs that candidate, never the command. *)
let probe ?allow_caller_violations ~(root : string) (cx : ctx) (s : IS.slot) (c : IV.cand) : verdict =
  try
    let s = { s with IS.fd = cx.fd0 } in
    let hyp = IS.install s ~mk:c.IV.c.PI.c_pred in
    with_hyp_def cx hyp @@ fun () ->
    match s.IS.path with
    | IS.Return -> return_ ~root cx hyp
    | IS.Param _ -> precondition ?allow_caller_violations ~root cx hyp
    | IS.Lambda_param _ -> accumulator ~root cx hyp
    | p -> (
      match IS.root p with
      | IS.Param _ -> precondition ?allow_caller_violations ~root cx hyp
      | IS.Return -> elem_return ~root cx hyp
      | _ -> Reject ("not-useful", "kind not implemented"))
  with e -> Reject ("not-true", "probe raised: " ^ Printexc.to_string e)

let scope_types (s : IS.slot) : (string * A.ty) list =
  match s.IS.fd.A.fn_clauses with
  | c :: _ ->
    let ps = PI.named_params c in
    List.filter_map (fun n -> Option.map (fun t -> (n, t)) (List.assoc_opt n ps)) (IV.scope_names s)
  | [] -> []

let ordered_candidates ~(root : string) ~(ledger : Obligation.t list) ~(unit_decls : A.decl list)
    (s : IS.slot) : IV.cand list =
  IV.order ~root ~scope:(scope_types s) ~base:s.IS.base (IV.mine s ~ledger ~unit_decls)

let is_return (s : IS.slot) = match IS.root s.IS.path with IS.Return -> true | _ -> false

(* The proposal for one slot, and every verdict on the way.  Candidates arrive
   weakest first; among admissible ones a precondition takes the best net gain
   (closes − new skips), a return the most closed caller sites — ties to the
   earlier (weaker, higher-rank) candidate (design §1.4).  An exhausted budget
   is recorded as [Reject ("budget", _)], never folded into "no candidate". *)
let best_for_slot ?allow_caller_violations ~(root : string) ~(decls : A.decl list) (s : IS.slot) (cands : IV.cand list)
    ~(budget : int ref) : (IV.cand * verdict) option * verdict list =
  Obligation.with_scratch @@ fun () ->
  match prepare ~root ~decls s with
  | None -> (None, [ Reject ("not-useful", "function not found") ])
  | Some cx ->
    let score = function
      | Accept { closes; new_skipped } ->
        if is_return s then List.length closes else List.length closes - List.length new_skipped
      | _ -> min_int
    in
    let rec go best verdicts = function
      | [] -> (best, List.rev verdicts)
      | _ :: _ when !budget <= 0 -> (best, List.rev (Reject ("budget", "probe budget exhausted") :: verdicts))
      | c :: tl ->
        decr budget;
        let v = probe ?allow_caller_violations ~root cx s c in
        let best =
          match v, best with
          | Accept _, None -> Some (c, v)
          | Accept _, Some (_, bv) when score v > score bv -> Some (c, v)
          | _ -> best
        in
        go best (v :: verdicts) tl
    in
    go None [] cands

(* ── K6: joint abstract-refinement candidates (design §1.2, §2) ──────────── *)

(* TRUE: the checker's element-return gate proves the grafted signature on
   the definition side ([p] uninterpreted; a recursive call must pass its own
   callback unchanged — the checker's own-predicate rule).  USEFUL: some
   caller site closes with [p] instantiated.  Passing a callable for a definer
   owes nothing at the caller, so K6 adds no caller burden. *)
let k6_verdict ~(root : string) (cx : ctx) (hyp : A.fn_def) : verdict =
  with_hyp_def cx hyp @@ fun () -> elem_return ~root cx hyp

let best_k6 ~(root : string) ~(decls : A.decl list) (s : IS.slot) ~(budget : int ref)
    : (IS.k6_shape * verdict) option * verdict list =
  Obligation.with_scratch @@ fun () ->
  match prepare ~root ~decls s with
  | None -> (None, [ Reject ("not-useful", "function not found") ])
  | Some cx ->
    let s = { s with IS.fd = cx.fd0 } in
    let closes = function Accept { closes; _ } -> List.length closes | _ -> min_int in
    let rec go best verdicts = function
      | [] -> (best, List.rev verdicts)
      | _ :: _ when !budget <= 0 -> (best, List.rev (Reject ("budget", "probe budget exhausted") :: verdicts))
      | shape :: tl ->
        decr budget;
        let v =
          match IS.graft s shape with
          | None -> Reject ("unannotated-signature", "the signature cannot be re-spelled")
          | Some hyp -> ( try k6_verdict ~root cx hyp with e -> Reject ("not-true", "probe raised: " ^ Printexc.to_string e))
        in
        let best =
          match v, best with
          | Accept _, None -> Some (shape, v)
          | Accept _, Some (_, bv) when closes v > closes bv -> Some (shape, v)
          | _ -> best
        in
        go best (v :: verdicts) tl
    in
    go None [] (IS.k6_shapes s)

(* TRUE only (no USEFUL): does the checker prove [c] at return slot [s]?  The
   demand-chain step of the fixpoint (design §3.3) asks this of a callee link
   before installing it tentatively. *)
let holds ~(root : string) ~(decls : A.decl list) (s : IS.slot) (c : IV.cand) : bool =
  Obligation.with_scratch @@ fun () ->
  match prepare ~root ~decls s with
  | None -> false
  | Some cx -> (
    let s = { s with IS.fd = cx.fd0 } in
    let hyp = IS.install s ~mk:c.IV.c.PI.c_pred in
    try
      with_hyp_def cx hyp @@ fun () ->
      match s.IS.path with
      | IS.Return -> PO.post_holds ~root hyp
      | p when IS.root p = IS.Return ->
        with_elem_table (fun () -> elem_ret_holds ~root ~defs:(defs_with cx hyp) (cx.rebuild hyp) ~fn:cx.qualified)
      | _ -> false
    with _ -> false)
