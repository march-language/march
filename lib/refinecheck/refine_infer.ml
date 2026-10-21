(* The module-wide inference fixpoint (`--refine-infer`)
   (specs/2026-10-20-refinement-suggest-lite-design.md §3).

   The caller has run [Refine_check.check_module] (registration globals).
   Rounds repeat until one accepts nothing (cap [rounds]):
     F-phase — facts: return slots (K2, K4, K5-return) and abstract (K6), in
               callees-first order; a return that is USEFUL but not TRUE tries
               a demand chain through its tail callee (depth ≤ 3);
     D-phase — demands: parameter slots (K1, K3, K5-param), callees first;
     A-phase — accumulators (K7).
   Facts go first: a return discharges caller debt and burdens no one, a
   precondition only moves debt up.  Every accepted proposal is installed (in
   the decl tree and in the checker's definition tables) so later probes see
   it; the tables are restored when the run ends.  The real checker is the
   only oracle ([Infer_oracle]). *)

module A = March_ast.Ast
module PI = Precond_infer
module IS = Infer_slot
module IV = Infer_vocab
module IO = Infer_oracle
module LD = Ledger_diff
module RC = Refine_check
module Ob = Obligation

type proposal = {
  id : string;
  round : int;
  slot : IS.slot;
  pred : string;
  annotation : string;
  source : IV.source;
  depends_on : string list;
  closes : LD.key list;
  new_skipped : LD.key list;
  external_callers : bool;
}

type result = {
  proposals : proposal list;
  rejected : (IS.slot * string * string * string) list;   (* slot, pred, reason, detail *)
  refused : (IS.slot * string * PI.refusal) list;          (* slot, pred, refusal *)
  notes : (string * string) list;                          (* fn, note *)
  before : LD.snapshot;
  after : LD.snapshot;
  after_counts : int * int;
    (* Raw user-code (skipped, violated) obligation counts of the final
       hypothesis tree — what `--check --refine-report` will print once the
       proposals are applied (the snapshot dedupes sites; the report does not). *)
  probes : int;
  rounds : int;
}

let all_kinds = IS.[ K1; K2; K3; K4; K5; K6; K7 ]
let default_budget = 3000
let default_rounds = 10
let chain_depth = 3

(* ── The decl tree ───────────────────────────────────────────────────────── *)

let rec replace_fn (prefix : string list) (q : string) (fd' : A.fn_def) (decls : A.decl list) : A.decl list =
  List.map
    (function
      | A.DFn (f, sp) when String.concat "." (prefix @ [ f.A.fn_name.A.txt ]) = q -> A.DFn (fd', sp)
      | A.DMod (n, vis, inner, sp) -> A.DMod (n, vis, replace_fn (prefix @ [ n.A.txt ]) q fd' inner, sp)
      | d -> d)
    decls

let find_fd (decls : A.decl list) (q : string) : A.fn_def option =
  List.find_map
    (fun ((_, fd) as pf) -> if PI.qualified_of pf = q then Some fd else None)
    (PI.enum_fns [] decls)

(* Strongly connected components of the user call graph, callees first
   (Tarjan emits them in reverse topological order). *)
let sccs ?(defined : (string, unit) Hashtbl.t option) (fns : (string * A.fn_def) list) : string list list =
  let defined =
    match defined with
    | Some d -> d
    | None -> let t = Hashtbl.create 16 in List.iter (fun (q, _) -> Hashtbl.replace t q ()) fns; t
  in
  let path_of q = match List.rev (String.split_on_char '.' q) with _ :: tl -> List.rev tl | [] -> [] in
  let caller_of = Hashtbl.create 16 in
  List.iter (fun (q, fd) -> Hashtbl.replace caller_of fd.A.fn_name.A.span (path_of q)) fns;
  let calls (f : A.fn_def) g =
    let caller = Option.value (Hashtbl.find_opt caller_of f.A.fn_name.A.span) ~default:[] in
    PI.fn_calls_target ~defined ~caller ~target:g f
  in
  let index = Hashtbl.create 16 and low = Hashtbl.create 16 and on = Hashtbl.create 16 in
  let stack = ref [] and counter = ref 0 and out = ref [] in
  let rec strong (v, fd) =
    Hashtbl.replace index v !counter;
    Hashtbl.replace low v !counter;
    incr counter;
    stack := v :: !stack;
    Hashtbl.replace on v ();
    List.iter
      (fun (w, wfd) ->
        if w <> v && calls fd w then
          if not (Hashtbl.mem index w) then begin
            strong (w, wfd);
            Hashtbl.replace low v (min (Hashtbl.find low v) (Hashtbl.find low w))
          end
          else if Hashtbl.mem on w then Hashtbl.replace low v (min (Hashtbl.find low v) (Hashtbl.find index w)))
      fns;
    if Hashtbl.find low v = Hashtbl.find index v then begin
      let rec pop acc =
        match !stack with
        | w :: tl ->
          stack := tl;
          Hashtbl.remove on w;
          if w = v then w :: acc else pop (w :: acc)
        | [] -> acc
      in
      out := List.sort compare (pop []) :: !out
    end
  in
  List.iter (fun ((v, _) as n) -> if not (Hashtbl.mem index v) then strong n) fns;
  List.rev !out

(* The direct tail call of [fd]'s body, if it is a call to a user function. *)
let tail_callee (fd : A.fn_def) : string option =
  let rec tail (e : A.expr) =
    match e with
    | A.EBlock (es, _) -> (match List.rev es with x :: _ -> tail x | [] -> None)
    | A.EApp (A.EVar { A.txt; _ }, _, _) -> Some txt
    | _ -> None
  in
  match fd.A.fn_clauses with [ c ] -> tail c.A.fc_body | _ -> None

(* ── The run ─────────────────────────────────────────────────────────────── *)

let run ?(root = Sys.getcwd ()) ?(kinds = all_kinds) ?(budget = default_budget)
    ?(rounds = default_rounds) ?(allow_caller_violations = false) ?(stdlib = false)
    ?(applicable : proposal -> accepted:proposal list -> string option = fun _ ~accepted:_ -> None)
    ~(is_user : A.span -> bool) (m : A.module_) : result =
  let is_target sp = stdlib || is_user sp in
  Ob.with_scratch @@ fun () ->
  let saved_defs = Hashtbl.copy Refine_param.fn_defs_tbl in
  let saved_proved = Hashtbl.copy Refine_param.elem_ret_proved in
  let saved_abs = Hashtbl.copy RC.abstracts_tbl in
  let restore () =
    let back dst src =
      Hashtbl.reset dst;
      Hashtbl.iter (fun k v -> Hashtbl.replace dst k v) src
    in
    back Refine_param.fn_defs_tbl saved_defs;
    back Refine_param.elem_ret_proved saved_proved;
    back RC.abstracts_tbl saved_abs
  in
  Fun.protect ~finally:restore @@ fun () ->
  let decls = ref m.A.mod_decls in
  let user_snapshot () =
    let defs = RC.collect_all_defs !decls in
    let snap = PI.walk_ledger ~root ~defs !decls in
    (List.filter (fun ((k : LD.key), _) -> is_user k.LD.span) snap, Ob.all ())
  in
  let before, _ = user_snapshot () in
  let budget = ref budget in
  let start_budget = !budget in
  let proposals = ref [] and rejected = ref [] and refused = ref [] and notes = ref [] in
  let next_id = ref 0 in
  let note fn n = if not (List.mem (fn, n) !notes) then notes := (fn, n) :: !notes in
  (* Install an accepted hypothesis: in the tree, and in the checker's tables. *)
  let install (s : IS.slot) (hyp : A.fn_def) =
    decls := replace_fn [] s.IS.fn hyp !decls;
    (match Hashtbl.find_opt Refine_param.fn_defs_tbl s.IS.fn with
     | Some (prefix, _) -> Hashtbl.replace Refine_param.fn_defs_tbl s.IS.fn (prefix, hyp)
     | None -> ());
    Hashtbl.remove RC.abstracts_tbl s.IS.fn;
    match s.IS.path with
    | IS.Return | IS.Param _ | IS.Lambda_param _ -> ()
    | p -> if IS.root p = IS.Return || List.mem IS.K6 s.IS.kinds then Hashtbl.replace Refine_param.elem_ret_proved s.IS.fn ()
  in
  let current_slot (s : IS.slot) =
    match find_fd !decls s.IS.fn with Some fd -> Some { s with IS.fd = fd } | None -> None
  in
  let annotation_of (s : IS.slot) (pred : string) =
    match s.IS.path with
    | IS.Lambda_param _ -> Printf.sprintf "{Int | %s}" pred
    | _ -> Option.value (IS.respell s ~pred) ~default:pred
  in
  (* [applicable] (the driver's, under --refine-infer-apply/-diff) withholds a
     proposal that will not be written — external callers without
     --apply-public, an edit that must be made by hand — BEFORE it is
     installed, so no later probe and no prediction counts on it.  A withheld
     proposal is reported as refused with that reason. *)
  let proposal_of ~round ~(s : IS.slot) ~pred ~annotation ~source ~depends ~(v : IO.verdict) =
    let id = Printf.sprintf "P%d" (!next_id + 1) in
    let closes, new_skipped = match v with IO.Accept { closes; new_skipped } -> (closes, new_skipped) | _ -> ([], []) in
    let path, name = IO.split_qualified s.IS.fn in
    let external_callers =
      (match IS.root s.IS.path with IS.Param _ -> true | _ -> false)
      && s.IS.fd.A.fn_vis = A.Public
      && not (PI.has_in_unit_callers path name !decls)
    in
    { id; round; slot = s; pred; annotation; source; depends_on = depends; closes; new_skipped; external_callers }
  in
  let withheld (p : proposal) =
    match applicable p ~accepted:(List.rev !proposals) with
    | None -> false
    | Some why ->
      refused := (p.slot, p.pred, { PI.rf_reason = why; rf_sites = [] }) :: !refused;
      true
  in
  let commit (p : proposal) =
    incr next_id;
    proposals := p :: !proposals;
    p.id
  in
  let note_verdicts (s : IS.slot) (pairs : (string * IO.verdict) list) =
    List.iter
      (fun (pred, v) ->
        match v with
        | IO.Reject (("not-true" | "opens-site" | "unsatisfiable") as r, d) -> rejected := (s, pred, r, d) :: !rejected
        | IO.Reject ("budget", _) -> note s.IS.fn "budget-exhausted"
        | IO.Refuse rf -> refused := (s, pred, rf) :: !refused
        | _ -> ())
      pairs
  in
  (* One ordinary slot (K1-K5, K7): best candidate, or a chain for a return. *)
  let try_slot ~round ~ledger ~depth (s : IS.slot) : bool =
    match current_slot s with
    | None -> false
    | Some s ->
      let cands, truncated = IV.mine_full s ~ledger ~unit_decls:!decls in
      if truncated then note s.IS.fn "vocabulary-truncated";
      let cands = IV.order ~root ~scope:(IO.scope_types s) ~base:s.IS.base cands in
      let per_fn = ref (min !budget (if IO.is_return s then 60 else 200)) in
      let used0 = !per_fn in
      (* [~allow_caller_violations] (D2's override): a candidate refused only
         for the callers it would break is taken as if admissible — still
         only if some value satisfies it. *)
      let best, verdicts = IO.best_for_slot ~allow_caller_violations ~root ~decls:!decls s cands ~budget:per_fn in
      budget := !budget - (used0 - !per_fn);
      let pairs = List.mapi (fun i v -> ((match List.nth_opt cands i with Some c -> c.IV.c.PI.c_text | None -> ""), v)) verdicts in
      match best with
      | Some (c, v) ->
        let p =
          proposal_of ~round ~s ~pred:c.IV.c.PI.c_text ~annotation:(annotation_of s c.IV.c.PI.c_text)
            ~source:c.IV.source ~depends:[] ~v
        in
        if withheld p then false
        else begin
          let hyp = IS.install s ~mk:c.IV.c.PI.c_pred in
          install s hyp;
          ignore (commit p);
          true
        end
      | None ->
        (* Demand chain (§3.3): a return candidate that is not TRUE because
           its tail calls a user function whose own return could carry it. *)
        let chained =
          IO.is_return s && depth < chain_depth
          && (match tail_callee s.IS.fd with
              | None -> false
              | Some callee ->
                let caller, _ = IO.split_qualified s.IS.fn in
                let callee = PI.resolve_call ~defined:(PI.defined_fns !decls) ~caller callee in
                let callee_slot =
                  List.find_opt
                    (fun (t : IS.slot) -> Some t.IS.fn = callee && t.IS.path = s.IS.path)
                    (IS.enumerate ~is_user:is_target !decls)
                in
                match callee_slot with
                | None -> false
                | Some cs ->
                  List.exists
                    (fun ((pred, v) : string * IO.verdict) ->
                      match v with
                      | IO.Reject ("not-true", _) when !budget > 0 -> (
                        match List.find_opt (fun c -> c.IV.c.PI.c_text = pred) cands with
                        | None -> false
                        | Some c ->
                          decr budget;
                          if not (IO.holds ~root ~decls:!decls cs c) then false
                          else begin
                            (* Tentatively install the callee link, then re-probe. *)
                            let saved_decls = !decls in
                            let saved_tbl = Hashtbl.find_opt Refine_param.fn_defs_tbl cs.IS.fn in
                            let saved_proved = Hashtbl.mem Refine_param.elem_ret_proved cs.IS.fn in
                            let csf = Option.value (current_slot cs) ~default:cs in
                            let chyp = IS.install csf ~mk:c.IV.c.PI.c_pred in
                            install csf chyp;
                            let b2 = ref 1 in
                            match IO.best_for_slot ~root ~decls:!decls s [ c ] ~budget:b2 with
                            | Some (_, v2), _
                              when (let dp =
                                      proposal_of ~round ~s:csf ~pred
                                        ~annotation:(Option.value (IS.respell csf ~pred) ~default:pred)
                                        ~source:c.IV.source ~depends:[] ~v:(IO.Accept { closes = []; new_skipped = [] })
                                    in
                                    not (withheld dp)
                                    && (let dep = commit dp in
                                        let mp =
                                          proposal_of ~round ~s ~pred
                                            ~annotation:(Option.value (IS.respell s ~pred) ~default:pred)
                                            ~source:c.IV.source ~depends:[ dep ] ~v:v2
                                        in
                                        if withheld mp then begin
                                          (* The link alone closes nothing: take it back. *)
                                          proposals := List.tl !proposals;
                                          decr next_id;
                                          false
                                        end
                                        else begin
                                          let hyp = IS.install s ~mk:c.IV.c.PI.c_pred in
                                          install s hyp;
                                          ignore (commit mp);
                                          true
                                        end)) ->
                              true
                            | _, _ ->
                              decls := saved_decls;
                              (match saved_tbl with
                               | Some v -> Hashtbl.replace Refine_param.fn_defs_tbl cs.IS.fn v
                               | None -> ());
                              if not saved_proved then Hashtbl.remove Refine_param.elem_ret_proved cs.IS.fn;
                              false
                          end)
                      | _ -> false)
                    pairs)
        in
        if not chained then note_verdicts s pairs;
        chained
  in
  let try_k6 ~round (s : IS.slot) : bool =
    match current_slot s with
    | None -> false
    | Some s -> (
      let per_fn = ref (min !budget 60) in
      let used0 = !per_fn in
      let best, verdicts = IO.best_k6 ~root ~decls:!decls s ~budget:per_fn in
      budget := !budget - (used0 - !per_fn);
      match best with
      | Some (shape, v) -> (
        match IS.graft s shape with
        | Some hyp ->
          let p =
            proposal_of ~round ~s ~pred:"p" ~annotation:(shape.IS.k6_callback ^ " / " ^ shape.IS.k6_return)
              ~source:IV.House ~depends:[] ~v
          in
          if withheld p then false
          else begin
            install s hyp;
            ignore (commit p);
            true
          end
        | None -> false)
      | None ->
        note_verdicts s (List.map (fun v -> ("p", v)) verdicts);
        false)
  in
  let rec loop round =
    if round > rounds || !budget <= 0 then round - 1
    else begin
      let _, ledger = user_snapshot () in
      let slots =
        IS.enumerate ~is_user:is_target !decls
        |> List.filter (fun (s : IS.slot) -> List.exists (fun k -> List.mem k kinds) s.IS.kinds)
      in
      let user_fns =
        List.filter_map
          (fun ((_, fd) as pf) -> if is_target fd.A.fn_name.A.span then Some (PI.qualified_of pf, fd) else None)
          (PI.enum_fns [] !decls)
      in
      let order = sccs ~defined:(PI.defined_fns !decls) user_fns in
      let rank = Hashtbl.create 16 in
      List.iteri (fun i comp -> List.iter (fun f -> Hashtbl.replace rank f i) comp) order;
      let by_order ss =
        List.stable_sort
          (fun (a : IS.slot) (b : IS.slot) ->
            compare (Hashtbl.find_opt rank a.IS.fn) (Hashtbl.find_opt rank b.IS.fn))
          ss
      in
      let is_k6 (s : IS.slot) = List.mem IS.K6 s.IS.kinds in
      let is_k7 (s : IS.slot) = List.mem IS.K7 s.IS.kinds in
      let facts = by_order (List.filter (fun s -> (not (is_k6 s)) && (not (is_k7 s)) && IO.is_return s) slots) in
      let k6s = by_order (List.filter is_k6 slots) in
      let demands = by_order (List.filter (fun s -> (not (is_k6 s)) && (not (is_k7 s)) && not (IO.is_return s)) slots) in
      let accs = List.filter is_k7 slots in
      let accepted = ref false in
      let go f ss = List.iter (fun s -> if f s then accepted := true) ss in
      go (try_slot ~round ~ledger ~depth:0) facts;
      go (try_k6 ~round) k6s;
      go (try_slot ~round ~ledger ~depth:0) demands;
      go (try_slot ~round ~ledger ~depth:0) accs;
      (* An SCC of size > 1 whose members got nothing. *)
      List.iter
        (fun comp ->
          if List.length comp > 1
             && not (List.exists (fun (p : proposal) -> List.mem p.slot.IS.fn comp) !proposals)
          then List.iter (fun f -> note f "scc-unsupported") comp)
        order;
      if !accepted then loop (round + 1) else round
    end
  in
  let rounds_run = loop 1 in
  let after, after_obs = user_snapshot () in
  let after_counts =
    List.fold_left
      (fun (sk, vi) (o : Ob.t) ->
        if not (is_user o.Ob.span) then (sk, vi)
        else match o.Ob.verdict with Ob.Skipped _ -> (sk + 1, vi) | Ob.Violated -> (sk, vi + 1) | _ -> (sk, vi))
      (0, 0) after_obs
  in
  { proposals = List.rev !proposals;
    rejected = List.rev !rejected;
    refused = List.rev !refused;
    notes = List.rev !notes;
    before;
    after;
    after_counts;
    probes = start_budget - !budget;
    rounds = rounds_run }
