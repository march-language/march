(* Postcondition inference: propose a RETURN refinement that lets a function's
   callers discharge obligations they currently cannot.

   ── Why this is not just [Precond_infer] with a different target ───────────
   [Precond_infer] asks one question — did hypothesising this refinement shrink
   THIS function's debt — because a precondition is a fact the body gets to
   assume.  A postcondition is not: it discharges nothing here, it discharges
   obligations in the CALLERS.  So two independent questions have to be answered,
   and answering only one of them is how this ships as noise:

     TRUE?    does the function actually return values satisfying it?
     USEFUL?  does any caller's obligation become provable because of it?

   A candidate failing the first is a wrong annotation the checker will strip
   ([Refine_check.gate_unverified_posts] drops an unverified postcondition
   rather than trusting it, so proposing one would produce an annotation that
   silently does nothing).  A candidate failing the second is TRUE and useless:
   `{Int | _ != 0}` on a function nobody calls in a context that needs it is
   noise, and a sweep full of true irrelevancies is indistinguishable from a
   broken tool.  Both are checked here, separately.

   ── Where the answers come from ───────────────────────────────────────────
   TRUE is answered by [Refine_check.check_fn_post_verdict ~emit:false] — the
   real checker's own postcondition oracle, the same one [gate_unverified_posts]
   consults.  Deliberately NOT by [Return_infer]'s Z3 probing, which builds its
   own verification conditions: a second prover can disagree with the first, and
   the disagreement surfaces as a suggestion `march check` then refuses.  That
   is the drift hazard [Precond_infer]'s design note is about.

   USEFUL is answered the same way [Precond_infer] answers its one question —
   by the obligation ledger — but over a decl tree that includes the CALLERS,
   since that is where the debt being discharged lives. *)

module A = March_ast.Ast
module Err = March_errors.Errors
module Ob = Obligation
module RC = Refine_check
module PI = Precond_infer

(* ── Candidates ───────────────────────────────────────────────────────────── *)

(* Ordered WEAKEST FIRST, and the order is the tie-break, exactly as for
   preconditions — but the reason differs.  A precondition that is too strong
   rejects callers; a postcondition that is too strong over-promises, freezing
   an implementation detail into the signature and constraining every future
   rewrite of the body.  Both argue for the weakest thing that does the job. *)
let int_candidates : PI.candidate list =
  List.map
    (fun (c_text, c_pred) -> { PI.c_text; c_pred })
    [ ("_ != 0", fun sp -> PI.bin sp "!=" (PI.hole sp) (PI.ilit sp 0));
      ("_ >= 0", fun sp -> PI.bin sp ">=" (PI.hole sp) (PI.ilit sp 0));
      ("_ > 0",  fun sp -> PI.bin sp ">"  (PI.hole sp) (PI.ilit sp 0));
      ("_ <= 0", fun sp -> PI.bin sp "<=" (PI.hole sp) (PI.ilit sp 0));
      ("_ < 0",  fun sp -> PI.bin sp "<"  (PI.hole sp) (PI.ilit sp 0)) ]

let float_candidates : PI.candidate list =
  List.map
    (fun (c_text, c_pred) -> { PI.c_text; c_pred })
    [ ("_ != 0.0", fun sp -> PI.bin sp "!=" (PI.hole sp) (PI.flit sp 0.0));
      ("_ >= 0.0", fun sp -> PI.bin sp ">=" (PI.hole sp) (PI.flit sp 0.0));
      ("_ > 0.0",  fun sp -> PI.bin sp ">"  (PI.hole sp) (PI.flit sp 0.0)) ]

let measured_candidates : PI.candidate list =
  [ { PI.c_text = "len(_) > 0";
      c_pred = (fun sp -> PI.bin sp ">" (PI.call1 sp "len" (PI.hole sp)) (PI.ilit sp 0)) } ]

let candidates_for (ty : A.ty) : PI.candidate list =
  if PI.already_refined ty then []
  else
    match PI.kind_of_ty ty with
    | PI.KInt -> int_candidates
    | PI.KFloat -> float_candidates
    | PI.KList | PI.KString -> measured_candidates
    | PI.KOther -> []

(* ── AST surgery ──────────────────────────────────────────────────────────── *)

let with_return_refinement (fd : A.fn_def) ~(mk : A.span -> A.expr) : A.fn_def =
  match fd.A.fn_ret_ty with
  | Some base when not (PI.already_refined base) ->
    { fd with
      A.fn_ret_ty = Some (A.TyRefine (base, None, mk fd.A.fn_name.A.span)) }
  | _ -> fd

(* ── Callers ──────────────────────────────────────────────────────────────── *)

(* Does [e] contain a call to [name]?  Syntactic and deliberately
   over-approximate: a false positive costs one extra function in the probe
   walk, whereas a false negative silently hides the debt the candidate was
   meant to discharge and makes a useful suggestion look useless. *)
let rec calls_name (name : string) (e : A.expr) : bool =
  let any = List.exists (calls_name name) in
  let is_target = function
    | A.EVar n -> n.A.txt = name || Filename.check_suffix n.A.txt ("." ^ name)
    | _ -> false
  in
  match e with
  | A.EApp (f, args, _) -> is_target f || calls_name name f || any args
  | A.EBlock (es, _) -> any es
  | A.ELet (b, _) -> calls_name name b.A.bind_expr
  | A.EIf (c, t, f, _) -> calls_name name c || calls_name name t || calls_name name f
  | A.EMatch (s, brs, _) ->
    calls_name name s
    || List.exists (fun (br : A.branch) -> calls_name name br.A.branch_body) brs
  | A.ETuple (es, _) | A.ECon (_, es, _) | A.EAtom (_, es, _) -> any es
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) -> calls_name name e
  | A.ELam (_, b, _) | A.ELetFn (_, _, _, b, _) -> calls_name name b
  | A.EPipe (a, b, _) | A.ESend (a, b, _) -> calls_name name a || calls_name name b
  | A.ERecord (fs, _) -> List.exists (fun (_, v) -> calls_name name v) fs
  | A.ERecordUpdate (r, fs, _) ->
    calls_name name r || List.exists (fun (_, v) -> calls_name name v) fs
  | A.EField (e, _, _) -> calls_name name e
  | _ -> false

let fn_calls (name : string) (fd : A.fn_def) : bool =
  List.exists (fun (c : A.fn_clause) -> calls_name name c.A.fc_body) fd.A.fn_clauses

(* Rebuild the decl tree keeping the target, everything that calls it, and the
   context-bearing decls at each level — the postcondition analogue of
   [Precond_infer.prune].  The callers are the point: they are where the debt a
   postcondition discharges actually lives. *)
let rec prune_with_callers (path : string list) (name : string)
    (decls : A.decl list) : (A.fn_def * (A.fn_def -> A.decl list)) option =
  match path with
  | [] ->
    let ctx = PI.context_decls decls in
    let callers =
      List.filter
        (function
          | A.DFn (fd, _) -> fd.A.fn_name.A.txt <> name && fn_calls name fd
          | _ -> false)
        decls
    in
    let rec find = function
      | [] -> None
      | A.DFn (fd, sp) :: _ when fd.A.fn_name.A.txt = name ->
        Some (fd, fun fd' -> ctx @ (A.DFn (fd', sp) :: callers))
      | _ :: tl -> find tl
    in
    find decls
  | m :: rest ->
    let rec find = function
      | [] -> None
      | A.DMod (n, vis, inner, sp) :: _ when n.A.txt = m ->
        (match prune_with_callers rest name inner with
         | None -> None
         | Some (fd, mk) ->
           Some (fd, fun fd' -> PI.context_decls decls @ [ A.DMod (n, vis, mk fd', sp) ]))
      | _ :: tl -> find tl
    in
    find decls

(* ── Probing ──────────────────────────────────────────────────────────────── *)

(* One probe.

   [defs] comes from the WHOLE module, not from the pruned tree.  Building it
   from the prune was the first attempt and it silently reported "no debt" for
   every function: the prune keeps the target and its callers, so a callee the
   CALLER invokes — the one whose precondition is the debt in question — has no
   entry, the obligation is never recorded, and zero debt looks exactly like a
   discharged one.  The tree being walked is pruned for cost; the signature
   table has to be complete for correctness. *)
let walk_debt ~root ~defs (decls : A.decl list) : PI.debt =
  Ob.reset ();
  let errctx = Err.create () in
  (try RC.visit_decls ~root errctx defs RC.rctx0 decls with _ -> ());
  PI.count_debt ()

(* A copy of [defs] in which [qualified]'s entry carries the hypothesised
   postcondition.  Overwriting one entry rather than re-collecting the module
   keeps the other signatures — including every already-gated stdlib one —
   exactly as [check_module] left them. *)
let defs_with_post (defs : (string, RC.fn_sig option) Hashtbl.t)
    ~(qualified : string) (hyp : A.fn_def) : (string, RC.fn_sig option) Hashtbl.t =
  let copy = Hashtbl.copy defs in
  Hashtbl.replace copy qualified (RC.entry_of_sig (RC.sig_of_fn hyp));
  copy

(* Is the candidate TRUE?  The real checker's own oracle, with emission off. *)
let post_holds ~root (fd : A.fn_def) : bool =
  let errctx = Err.create () in
  try RC.check_fn_post_verdict ~root errctx ~emit:false fd with _ -> false

(* ── Results ──────────────────────────────────────────────────────────────── *)

type status =
  | No_return_type    (* nothing to annotate *)
  | Already_refined   (* the author declared one; we do not second-guess it *)
  | No_callers        (* nothing that could benefit, so nothing to measure *)
  | No_debt           (* callers have no unproven obligations *)
  | Solved            (* the proposal discharges all of the callers' debt *)
  | Partial           (* it discharges some *)
  | No_candidate      (* debt exists, but nothing true-and-useful was found *)
  | Not_found

type t = {
  rs_fn : string;
  rs_span : A.span;
  rs_status : status;
  rs_base : string;          (* base return type, as it will be re-spelled *)
  rs_pred : string;          (* proposed predicate, "" when none *)
  rs_debt_before : int;      (* over the CALLERS *)
  rs_debt_after : int;
  rs_callers : int;
  rs_queries : int;
}

let status_name = function
  | No_return_type -> "no-return-type"
  | Already_refined -> "already-refined"
  | No_callers -> "no-callers"
  | No_debt -> "no-debt"
  | Solved -> "solved"
  | Partial -> "partial"
  | No_candidate -> "no-candidate"
  | Not_found -> "not-found"

(* ── Inference ────────────────────────────────────────────────────────────── *)

let default_budget = 60

let infer_fn ~root ~defs ~(decls : A.decl list) ~(path : string list)
    ~(budget : int ref) (fn_name : string) : t option =
  let qualified = String.concat "." (path @ [ fn_name ]) in
  match prune_with_callers path fn_name decls with
  | None -> None
  | Some (fd0, rebuild) ->
    let span = fd0.A.fn_name.A.span in
    let base_ty = fd0.A.fn_ret_ty in
    let mk ?(pred = "") ?(base = "") ~after ~callers status =
      Some { rs_fn = qualified; rs_span = span; rs_status = status; rs_base = base;
             rs_pred = pred; rs_debt_before = 0; rs_debt_after = after;
             rs_callers = callers; rs_queries = 0 }
    in
    (match base_ty with
     | None -> mk ~after:0 ~callers:0 No_return_type
     | Some t when PI.already_refined t -> mk ~after:0 ~callers:0 Already_refined
     | Some t ->
       (match PI.ty_text t with
        | None -> mk ~after:0 ~callers:0 No_candidate
        | Some base ->
          let tree = rebuild fd0 in
          let callers =
            List.length
              (List.filter
                 (function
                   | A.DFn (fd, _) -> fd.A.fn_name.A.txt <> fn_name
                   | A.DMod _ -> true
                   | _ -> false)
                 tree)
          in
          if callers = 0 then mk ~base ~after:0 ~callers:0 No_callers
          else begin
            let base_debt = walk_debt ~root ~defs tree in
            if base_debt.PI.d_total = 0 then
              mk ~base ~after:0 ~callers No_debt
            else begin
              let queries = ref 0 in
              let best = ref None in
              List.iter
                (fun (cand : PI.candidate) ->
                  if !budget > 0 && !best = None then begin
                    decr budget;
                    incr queries;
                    let hyp = with_return_refinement fd0 ~mk:cand.PI.c_pred in
                    (* TRUE first: it is the cheaper question, and a candidate
                       that fails it can never be proposed however much caller
                       debt it would appear to remove. *)
                    if post_holds ~root hyp then begin
                      let d =
                        walk_debt ~root
                          ~defs:(defs_with_post defs ~qualified hyp)
                          (rebuild hyp)
                      in
                      if d.PI.d_total < base_debt.PI.d_total
                         && d.PI.d_violated <= base_debt.PI.d_violated
                      then best := Some (cand, d)
                    end
                  end)
                (candidates_for t);
              match !best with
              | None ->
                Some { rs_fn = qualified; rs_span = span; rs_status = No_candidate;
                       rs_base = base; rs_pred = ""; rs_debt_before = base_debt.PI.d_total;
                       rs_debt_after = base_debt.PI.d_total; rs_callers = callers;
                       rs_queries = !queries }
              | Some (cand, d) ->
                Some { rs_fn = qualified; rs_span = span;
                       rs_status = (if d.PI.d_total = 0 then Solved else Partial);
                       rs_base = base; rs_pred = cand.PI.c_text;
                       rs_debt_before = base_debt.PI.d_total;
                       rs_debt_after = d.PI.d_total; rs_callers = callers;
                       rs_queries = !queries }
            end
          end))

(** Suggest a postcondition for [target].  The caller MUST have run
    [Refine_check.check_module] on [m] first — the registration globals it
    populates are what every probe reflects against. *)
(* [defs] mirrors what [check_module] builds and gates: collect over the whole
   module, then drop any postcondition the checker cannot verify, because only a
   positively-verified one may be assumed at a call site.  Skipping the gate here
   would let an unproven postcondition elsewhere in the module make a candidate
   look useful, and the suggestion would then predict a discharge `march check`
   does not perform. *)
let build_defs ~root (m : A.module_) : (string, RC.fn_sig option) Hashtbl.t =
  let defs = RC.collect_all_defs m.A.mod_decls in
  let errctx = Err.create () in
  (try RC.gate_unverified_posts ~root errctx defs m.A.mod_decls with _ -> ());
  defs

let suggest ?(root = Sys.getcwd ()) ?(budget = default_budget)
    ~(is_user : A.span -> bool) ~(target : string) (m : A.module_) : t list =
  let defs = build_defs ~root m in
  let all = PI.enum_fns [] m.A.mod_decls in
  let self = m.A.mod_name.A.txt ^ "." in
  let n = String.length self in
  let targets =
    target
    :: (if String.length target > n && String.sub target 0 n = self then
          [ String.sub target n (String.length target - n) ]
        else [])
  in
  let hits =
    List.filter
      (fun (_, (fd : A.fn_def)) -> is_user fd.A.fn_name.A.span)
      (List.filter
         (fun f -> List.exists (fun target -> PI.matches_target ~target f) targets)
         all)
  in
  match hits with
  | [] ->
    [ { rs_fn = target; rs_span = A.dummy_span; rs_status = Not_found; rs_base = "";
        rs_pred = ""; rs_debt_before = 0; rs_debt_after = 0; rs_callers = 0;
        rs_queries = 0 } ]
  | hits ->
    List.filter_map
      (fun (path, (fd : A.fn_def)) ->
        let budget = ref budget in
        infer_fn ~root ~defs ~decls:m.A.mod_decls ~path ~budget fd.A.fn_name.A.txt)
      hits

(** Sweep every user function, reporting only those with a proposal. *)
let suggest_all ?(root = Sys.getcwd ()) ?(budget = default_budget)
    ~(is_user : A.span -> bool) (m : A.module_) : t list =
  let defs = build_defs ~root m in
  PI.enum_fns [] m.A.mod_decls
  |> List.filter (fun (_, (fd : A.fn_def)) -> is_user fd.A.fn_name.A.span)
  |> List.filter_map (fun (path, (fd : A.fn_def)) ->
         let budget = ref budget in
         match infer_fn ~root ~defs ~decls:m.A.mod_decls ~path ~budget fd.A.fn_name.A.txt with
         | Some r when r.rs_pred <> "" -> Some r
         | _ -> None)
