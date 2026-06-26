(* Return-refinement inference for March functions.
   Given a function with Int-refined parameters, probes 6 sign candidates
   for the return value via Z3.  Results are informational — used by the IDE
   and documentation generator.  If Z3 is absent, every candidate returns
   Unverified and the list is empty (no noise, no false positives).

   Approach: for each function clause,
     1. Collect Int-refined parameters and build (decls, assumptions) from them.
     2. Walk the block body to collect let-binding equalities (propagation).
     3. Reflect the last (return) expression as an SMT term.
     4. For each of 6 sign candidates, discharge the VC.
   Only verified candidates are returned.  Multi-clause functions use the first
   clause; if clauses disagree the conservative empty result follows. *)

module A = March_ast.Ast
module Smt = March_refine.Smt
module Refine = March_refine.Refine

type inferred_return = { fn_name : string; verified_preds : string list }

(* Six candidate sign predicates as (human string, goal builder). *)
let candidates : (string * (Smt.term -> Smt.term)) list =
  [ ("r > 0",   fun r -> Smt.Gt (r, Smt.IntLit 0))
  ; ("r >= 0",  fun r -> Smt.Ge (r, Smt.IntLit 0))
  ; ("r >= 1",  fun r -> Smt.Ge (r, Smt.IntLit 1))
  ; ("r != 0",  fun r -> Smt.Ne (r, Smt.IntLit 0))
  ; ("r < 0",   fun r -> Smt.Lt (r, Smt.IntLit 0))
  ; ("r <= -1", fun r -> Smt.Le (r, Smt.IntLit (-1)))
  ]

(* ── SMT reflection ─────────────────────────────────────────────────────── *)

(* Reflect [e] to an SMT term.  [b] is a binder name that maps to Const [var];
   all other EVar names map to Const of their own name.
   Returns None for expressions outside the linear Int/Bool fragment. *)
let rec smt_of ~b ~var (e : A.expr) : Smt.term option =
  let go = smt_of ~b ~var in
  let bin op a rhs =
    match go a, go rhs with Some ta, Some tb -> Some (op ta tb) | _ -> None
  in
  match e with
  | A.ELit (A.LitInt n, _) -> Some (Smt.IntLit n)
  | A.ELit (A.LitBool v, _) -> Some (Smt.BoolLit v)
  | A.EVar { A.txt = x; _ } ->
    if x = b || x = "_" then Some (Smt.Const var) else Some (Smt.Const x)
  | A.EApp (A.EVar { A.txt = op; _ }, [ a; rhs ], _) ->
    (match op with
     | "+"  -> bin (fun a b -> Smt.Add (a, b)) a rhs
     | "-"  -> bin (fun a b -> Smt.Sub (a, b)) a rhs
     | "*"  ->
       (match go a, go rhs with
        | Some (Smt.IntLit k), Some t | Some t, Some (Smt.IntLit k) ->
          Some (Smt.MulLit (k, t))
        | _ -> None)
     | "==" -> bin (fun a b -> Smt.Eq  (a, b)) a rhs
     | "!=" -> bin (fun a b -> Smt.Ne  (a, b)) a rhs
     | "<"  -> bin (fun a b -> Smt.Lt  (a, b)) a rhs
     | "<=" -> bin (fun a b -> Smt.Le  (a, b)) a rhs
     | ">"  -> bin (fun a b -> Smt.Gt  (a, b)) a rhs
     | ">=" -> bin (fun a b -> Smt.Ge  (a, b)) a rhs
     | "&&" -> bin (fun a b -> Smt.And (a, b)) a rhs
     | "||" -> bin (fun a b -> Smt.Or  (a, b)) a rhs
     | _    -> None)
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) ->
    Option.map (fun t -> Smt.Not t) (go a)
  | A.EApp (A.EVar { A.txt = "-"; _ }, [ a ], _) ->
    Option.map (fun t -> Smt.Neg t) (go a)
  | _ -> None

(* Reflect [e] with no binder substitution: every EVar maps to its own name. *)
let rec smt_term (e : A.expr) : Smt.term option =
  let bin op a b = match smt_term a, smt_term b with Some ta, Some tb -> Some (op ta tb) | _ -> None in
  match e with
  | A.ELit (A.LitInt n, _) -> Some (Smt.IntLit n)
  | A.ELit (A.LitBool v, _) -> Some (Smt.BoolLit v)
  | A.EVar { A.txt = x; _ } -> Some (Smt.Const x)
  | A.EApp (A.EVar { A.txt = op; _ }, [ a; b ], _) ->
    (match op with
     | "+"  -> bin (fun a b -> Smt.Add (a, b)) a b
     | "-"  -> bin (fun a b -> Smt.Sub (a, b)) a b
     | "*"  ->
       (match smt_term a, smt_term b with
        | Some (Smt.IntLit k), Some t | Some t, Some (Smt.IntLit k) -> Some (Smt.MulLit (k, t))
        | _ -> None)
     | "==" -> bin (fun a b -> Smt.Eq  (a, b)) a b
     | "!=" -> bin (fun a b -> Smt.Ne  (a, b)) a b
     | "<"  -> bin (fun a b -> Smt.Lt  (a, b)) a b
     | "<=" -> bin (fun a b -> Smt.Le  (a, b)) a b
     | ">"  -> bin (fun a b -> Smt.Gt  (a, b)) a b
     | ">=" -> bin (fun a b -> Smt.Ge  (a, b)) a b
     | "&&" -> bin (fun a b -> Smt.And (a, b)) a b
     | "||" -> bin (fun a b -> Smt.Or  (a, b)) a b
     | _    -> None)
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) -> Option.map (fun t -> Smt.Not t) (smt_term a)
  | A.EApp (A.EVar { A.txt = "-"; _ }, [ a ], _) -> Option.map (fun t -> Smt.Neg t) (smt_term a)
  | _ -> None

(* ── Param collection (mirrors division_safety.ml) ──────────────────────── *)

let clause_refined_params (clause : A.fn_clause) =
  List.filter_map
    (function
      | A.FPNamed { A.param_name; param_ty = Some (A.TyRefine (base, binder, pred)); _ }
        when (match base with A.TyCon ({ A.txt = "Int"; _ }, []) -> true | _ -> false) ->
        let bdr = match binder with None -> "_" | Some n -> n.A.txt in
        Some (param_name.A.txt, bdr, pred)
      | A.FPDefault ({ A.param_name; param_ty = Some (A.TyRefine (base, binder, pred)); _ }, _)
        when (match base with A.TyCon ({ A.txt = "Int"; _ }, []) -> true | _ -> false) ->
        let bdr = match binder with None -> "_" | Some n -> n.A.txt in
        Some (param_name.A.txt, bdr, pred)
      | _ -> None)
    clause.A.fc_params

(* ── Base VC construction ────────────────────────────────────────────────── *)

(* Build (decls, assumptions) from Int-refined params. *)
let param_vc_base (params : (string * string * A.expr) list) :
    (string * Smt.sort) list * Smt.term list =
  List.fold_left
    (fun (decls, assume) (name, bdr, pred) ->
      let decls = (name, Smt.SInt) :: decls in
      match smt_of ~b:bdr ~var:name pred with
      | None -> (decls, assume)
      | Some a -> (decls, a :: assume))
    ([], []) params

(* Walk a block body and collect let-binding equalities for propagation.
   Returns (extra_decls, extra_assumptions, last_expr option). *)
let body_context (body : A.expr) :
    (string * Smt.sort) list * Smt.term list * A.expr option =
  match body with
  | A.EBlock (es, _) ->
    (match List.rev es with
     | [] -> ([], [], None)
     | last :: rev_prefix ->
       let extra_decls = ref [] and extra_assume = ref [] in
       List.iter
         (function
           | A.ELet (b, _) ->
             (match b.A.bind_pat with
              | A.PatVar n ->
                (match smt_term b.A.bind_expr with
                 | Some term ->
                   let vname = n.A.txt in
                   extra_decls := (vname, Smt.SInt) :: !extra_decls;
                   extra_assume := Smt.Eq (Smt.Const vname, term) :: !extra_assume
                 | None -> ())
              | _ -> ())
           | _ -> ())
         (List.rev rev_prefix);
       (!extra_decls, !extra_assume, Some last))
  | other -> ([], [], Some other)

(* ── Candidate probing ───────────────────────────────────────────────────── *)

(* Collect all Const names appearing in a term (for declaring undeclared vars). *)
let rec collect_consts (acc : (string, unit) Hashtbl.t) (t : Smt.term) : unit =
  match t with
  | Smt.Const x -> Hashtbl.replace acc x ()
  | Smt.Add (a, b) | Smt.Sub (a, b) | Smt.Eq (a, b) | Smt.Ne (a, b)
  | Smt.Lt (a, b) | Smt.Le (a, b) | Smt.Gt (a, b) | Smt.Ge (a, b)
  | Smt.And (a, b) | Smt.Or (a, b) | Smt.Implies (a, b) ->
    collect_consts acc a; collect_consts acc b
  | Smt.MulLit (_, t) | Smt.Neg t | Smt.Not t -> collect_consts acc t
  | Smt.App (_, ts) -> List.iter (collect_consts acc) ts
  | _ -> ()

let probe ~root (decls : (string * Smt.sort) list) (assumptions : Smt.term list)
    (return_term : Smt.term) (candidate_fn : Smt.term -> Smt.term) : bool =
  let goal = candidate_fn return_term in
  let vc = Smt.{ decls; assumptions; goal } in
  match Refine.discharge ~root vc with
  | Refine.Verified -> true
  | _ -> false

(* -- Return-position traversal --------------------------------------------- *)

(* Mirrors [tails] in refine_check.ml: collects all leaf return positions
   together with the accumulated path context (guard conditions) at each site. *)
let rec return_positions (path : (A.expr * bool) list) (e : A.expr)
    : ((A.expr * bool) list * A.expr) list =
  match e with
  | A.EBlock (es, _) ->
    (match List.rev es with
     | [] -> [ (path, e) ]
     | last :: _ -> return_positions path last)
  | A.EIf (c, t, el, _) ->
    return_positions ((c, false) :: path) t @
    return_positions ((c, true) :: path) el
  | A.ECond (arms, _) ->
    List.concat_map (fun (c, b) -> return_positions ((c, false) :: path) b) arms
  | A.EMatch (_, branches, _) ->
    List.concat_map
      (fun (br : A.branch) ->
        let p =
          match br.A.branch_guard with
          | Some g -> (g, false) :: path
          | None -> path
        in
        return_positions p br.A.branch_body)
      branches
  | other -> [ (path, other) ]

(* -- Per-clause inference -------------------------------------------------- *)

let infer_clause ~root (clause : A.fn_clause) : string list =
  let params = clause_refined_params clause in
  if params = [] then []
  else
    let (base_decls, base_assumptions) = param_vc_base params in
    let extra_decls       = ref [] in
    let extra_assumptions = ref [] in
    (match clause.A.fc_body with
     | A.EBlock (stmts, _) when stmts <> [] ->
       let n     = List.length stmts in
       let heads = List.filteri (fun i _ -> i < n - 1) stmts in
       List.iter
         (function
           | A.ELet (b, _) ->
             (match b.A.bind_pat with
              | A.PatVar { A.txt = vname; _ } ->
                (match smt_of ~b:"__none__" ~var:"__none__" b.A.bind_expr with
                 | Some t ->
                   extra_decls       := (vname, Smt.SInt) :: !extra_decls;
                   extra_assumptions := Smt.Eq (Smt.Const vname, t) :: !extra_assumptions
                 | None -> ())
              | _ -> ())
           | _ -> ())
         heads
     | _ -> ());
    let let_decls       = List.rev !extra_decls in
    let let_assumptions = List.rev !extra_assumptions in
    let decls           = base_decls @ let_decls in
    let base_assumes    = base_assumptions @ let_assumptions in
    let clause_path =
      match clause.A.fc_guard with Some g -> [ (g, false) ] | None -> []
    in
    let positions = return_positions clause_path clause.A.fc_body in
    let per_position =
      List.filter_map
        (fun (path, ret_expr) ->
          let guard_assumes =
            List.filter_map
              (fun (cond, negated) ->
                match smt_of ~b:"__none__" ~var:"__none__" cond with
                | None -> None
                | Some t -> Some (if negated then Smt.Not t else t))
              path
          in
          match smt_of ~b:"__none__" ~var:"__none__" ret_expr with
          | None -> None
          | Some return_term ->
            let assumptions = base_assumes @ guard_assumes in
            Some
              (List.filter_map
                 (fun (pred_str, candidate_fn) ->
                   if probe ~root decls assumptions return_term candidate_fn
                   then Some pred_str
                   else None)
                 candidates))
        positions
    in
    match per_position with
    | [] -> []
    | first :: rest ->
      List.fold_left
        (fun acc preds -> List.filter (fun p -> List.mem p preds) acc)
        first rest

(* -- Per-function inference ------------------------------------------------ *)

let infer_fn ~root (fd : A.fn_def) : inferred_return option =
  let any_refined = ref false in
  let all_verified =
    List.concat_map
      (fun clause ->
        let params = clause_refined_params clause in
        if params = [] then []
        else begin
          any_refined := true;
          infer_clause ~root clause
        end)
      fd.A.fn_clauses
  in
  if not !any_refined then None
  else begin
    let seen   = Hashtbl.create 8 in
    let unique =
      List.filter
        (fun p ->
          if Hashtbl.mem seen p then false
          else (Hashtbl.add seen p (); true))
        all_verified
    in
    Some { fn_name = fd.A.fn_name.A.txt; verified_preds = unique }
  end

(* -- Module-level entry point ---------------------------------------------- *)

let rec infer_decls ~root (decls : A.decl list) : inferred_return list =
  List.concat_map
    (function
      | A.DFn (fd, _) ->
        (match infer_fn ~root fd with
         | None -> []
         | Some r -> if r.verified_preds = [] then [] else [ r ])
      | A.DMod (_, _, inner, _) -> infer_decls ~root inner
      | _ -> [])
    decls

(** Infer return refinements for all functions in [m].
    Returns only functions for which at least one predicate is verified.
    If Z3 is unavailable, returns []. *)
let infer_module ?(root = Sys.getcwd ()) (m : A.module_) : inferred_return list =
  infer_decls ~root m.A.mod_decls
