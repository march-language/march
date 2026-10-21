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

let precondition ~(root : string) (cx : ctx) (hyp : A.fn_def) : verdict =
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
    if PI.admissible without_callers then
      Refuse
        { PI.rf_reason = "caller-violation";
          rf_sites = List.sort_uniq compare (List.map (fun (k : LD.key) -> k.LD.span) caller_viol) }
    else Reject ("not-useful", "creates violations and closes nothing in the body")
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

(* A probe that raises costs that candidate, never the command. *)
let probe ~(root : string) (cx : ctx) (s : IS.slot) (c : IV.cand) : verdict =
  try
    match s.IS.path with
    | IS.Param x -> precondition ~root cx (PI.with_refinement cx.fd0 ~param:x ~mk:c.IV.c.PI.c_pred)
    | IS.Return -> return_ ~root cx (PO.with_return_refinement cx.fd0 ~mk:c.IV.c.PI.c_pred)
    | _ -> Reject ("not-useful", "kind not implemented")
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
let best_for_slot ~(root : string) ~(decls : A.decl list) (s : IS.slot) (cands : IV.cand list)
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
        let v = probe ~root cx s c in
        let best =
          match v, best with
          | Accept _, None -> Some (c, v)
          | Accept _, Some (_, bv) when score v > score bv -> Some (c, v)
          | _ -> best
        in
        go best (v :: verdicts) tl
    in
    go None [] cands
