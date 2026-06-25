(* Template-based return refinement inference for March functions.

   Given a function with refined Int params ({ v : Int | pred }), infers
   the tightest sign/bound on the return value without requiring a user
   annotation.  The algorithm is single-pass with no fixpoint: reflect the
   return expression into an Smt.term, then probe 6 candidate predicates
   (r > 0, r >= 0, r >= 1, r != 0, r < 0, r <= -1) via Z3.

   If Z3 is absent, Refine.discharge returns Unverified and no predicates
   are inferred -- the function simply produces an empty verified_preds list
   (conservative but never crashes).

   Let-binding propagation: an EBlock body is walked before the final
   expression; each ELet that reflects to an Smt.term extends the decl /
   assumption set available to the final-expression check.

   smt_of and clause_refined_params are copied verbatim from division_safety.ml
   to keep this module self-contained. *)

module A = March_ast.Ast
module Smt = March_refine.Smt
module Refine = March_refine.Refine

(* -- Type ------------------------------------------------------------------ *)

type inferred_return = {
  fn_name        : string;
  verified_preds : string list;
  (** Subset of: "r > 0", "r >= 0", "r >= 1", "r != 0", "r < 0", "r <= -1" *)
}

(* -- Candidate predicates -------------------------------------------------- *)

(* Each candidate is (string_label, goal_term_thunk). *)
let candidates : (string * (unit -> Smt.term)) list =
  [ "r > 0",   (fun () -> Smt.Gt (Smt.Const "r", Smt.IntLit 0))
  ; "r >= 0",  (fun () -> Smt.Ge (Smt.Const "r", Smt.IntLit 0))
  ; "r >= 1",  (fun () -> Smt.Ge (Smt.Const "r", Smt.IntLit 1))
  ; "r != 0",  (fun () -> Smt.Ne (Smt.Const "r", Smt.IntLit 0))
  ; "r < 0",   (fun () -> Smt.Lt (Smt.Const "r", Smt.IntLit 0))
  ; "r <= -1", (fun () -> Smt.Le (Smt.Const "r", Smt.IntLit (-1)))
  ]

(* -- SMT reflection -------------------------------------------------------- *)

(* Reflects [e] into an Smt.term, substituting binder [b] with const [var].
   Returns None for anything outside the linear Int/Bool fragment.
   Copied verbatim from division_safety.ml. *)
let rec smt_of ~b ~var (e : A.expr) : Smt.term option =
  let go = smt_of ~b ~var in
  let bin op a rhs =
    match go a, go rhs with
    | Some ta, Some tb -> Some (op ta tb)
    | _ -> None
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

(* -- Param collection ------------------------------------------------------ *)

(* Returns [(param_name, binder, pred)] for each Int-refined parameter.
   Copied verbatim from division_safety.ml. *)
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

(* -- VC construction helpers ----------------------------------------------- *)

(* Build the base (decls, assumptions) from the refined params for a clause. *)
let param_vc_base (params : (string * string * A.expr) list) :
    (string * Smt.sort) list * Smt.term list =
  List.fold_right
    (fun (param_name, bdr, pred) (decls, assumptions) ->
      match smt_of ~b:bdr ~var:param_name pred with
      | None -> (decls, assumptions)
      | Some assumption ->
        ((param_name, Smt.SInt) :: decls, assumption :: assumptions))
    params ([], [])

(* Probe one candidate; return its label on Verified, None otherwise. *)
let probe ~root ~decls ~assumptions ~return_term (label, mk_goal) =
  let vc : Smt.vc =
    { decls       = decls @ [ ("r", Smt.SInt) ]
    ; assumptions = assumptions @ [ Smt.Eq (Smt.Const "r", return_term) ]
    ; goal        = mk_goal ()
    }
  in
  match Refine.discharge ~root vc with
  | Refine.Verified    -> Some label
  | Refine.Refuted _   -> None
  | Refine.Unverified  -> None   (* Z3 absent or timeout -- conservative skip *)

(* -- Per-clause inference -------------------------------------------------- *)

let infer_clause ~root (params : (string * string * A.expr) list) (body : A.expr) :
    string list =
  (* Walk EBlock stmts before the final expression to propagate let-bindings.
     Each ELet whose RHS reflects to an Smt.term extends decls + assumptions. *)
  let extra_decls       = ref [] in
  let extra_assumptions = ref [] in
  let final_expr =
    match body with
    | A.EBlock (stmts, _) when stmts <> [] ->
      let n     = List.length stmts in
      let heads = List.filteri (fun i _ -> i < n - 1) stmts in
      let tail  = List.nth stmts (n - 1) in
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
        heads;
      tail
    | e -> e
  in
  (* Reflect the return expression.  No binder substitution: variables in the
     body are already named by their param_name identifiers. *)
  match smt_of ~b:"__none__" ~var:"__none__" final_expr with
  | None -> []   (* Body outside the supported fragment -- conservative skip *)
  | Some return_term ->
    let (base_decls, base_assumptions) = param_vc_base params in
    let decls       = base_decls       @ List.rev !extra_decls in
    let assumptions = base_assumptions @ List.rev !extra_assumptions in
    List.filter_map (probe ~root ~decls ~assumptions ~return_term) candidates

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
          infer_clause ~root params clause.A.fc_body
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

let infer_module ?(root = Sys.getcwd ()) (m : A.module_) : inferred_return list =
  List.filter_map
    (function
      | A.DFn (fd, _) -> infer_fn ~root fd
      | _ -> None)
    m.A.mod_decls
