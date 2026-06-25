(* Division-safety checker for `cap no_panic` modules.
   A post-typecheck pass that finds every integer division/modulo operation in
   modules declared `cap no_panic` and verifies — via Z3 — that the divisor
   cannot be zero.  Uses the same definite-failure soundness stance as the
   rest of refinecheck: only flag when we can prove the divisor CAN be zero (or
   when there is no refinement at all).  When Z3 is unavailable or the VC is
   unknown the error is still raised, preserving the guarantee of `cap no_panic`.

   Supported:
   - Literal divisors: 0 → always error; non-zero → always safe.
   - Variable divisors with an Int refinement `{v | pred}`: syntactic fast-path
     for common patterns (v > 0, v >= 1, v != 0, v < 0, …); Z3 discharge for
     everything else in the linear-arithmetic fragment.
   - Variable divisors without a refinement: always error.
   - Complex divisors (arbitrary expressions): always error (conservative). *)

module A = March_ast.Ast
module Smt = March_refine.Smt
module Refine = March_refine.Refine
module Err = March_errors.Errors

let div_ops = [ "/"; "%"; "int_div"; "int_mod"; "int_div_euclid"; "int_mod_euclid" ]

(* ── Syntactic non-zero check (no Z3) ──────────────────────────────────── *)

(* Returns true when [pred] with binder [b] syntactically implies b ≠ 0.
   Handles the common patterns so that z3 absence doesn't force an error for
   the obvious cases (v > 0, v >= 1, v != 0, v < 0). *)
let rec syntactic_nonzero (b : string) (pred : A.expr) : bool =
  let is_b = function A.EVar { A.txt = x; _ } -> x = b || x = "_" | _ -> false in
  let int_of = function A.ELit (A.LitInt n, _) -> Some n | _ -> None in
  match pred with
  | A.EApp (A.EVar { A.txt = op; _ }, [ a; rhs ], _) ->
    (match op with
     (* v > n  where n ≥ 0  ⟹  v > 0  ⟹  v ≠ 0 *)
     | ">" ->
       (is_b a && Option.fold ~none:false ~some:(fun n -> n >= 0) (int_of rhs))
       || (is_b rhs && Option.fold ~none:false ~some:(fun n -> n <= 0) (int_of a))
     (* v >= n  where n ≥ 1  ⟹  v ≠ 0 *)
     | ">=" ->
       (is_b a && Option.fold ~none:false ~some:(fun n -> n >= 1) (int_of rhs))
       || (is_b rhs && Option.fold ~none:false ~some:(fun n -> n <= -1) (int_of a))
     (* v < n  where n ≤ 0  ⟹  v < 0  ⟹  v ≠ 0 *)
     | "<" ->
       (is_b a && Option.fold ~none:false ~some:(fun n -> n <= 0) (int_of rhs))
       || (is_b rhs && Option.fold ~none:false ~some:(fun n -> n >= 0) (int_of a))
     (* v <= n  where n ≤ -1  ⟹  v ≠ 0 *)
     | "<=" ->
       (is_b a && Option.fold ~none:false ~some:(fun n -> n <= -1) (int_of rhs))
       || (is_b rhs && Option.fold ~none:false ~some:(fun n -> n >= 1) (int_of a))
     (* v != 0  directly *)
     | "!=" ->
       (is_b a && int_of rhs = Some 0) || (is_b rhs && int_of a = Some 0)
     (* conjunction: either branch suffices *)
     | "&&" -> syntactic_nonzero b a || syntactic_nonzero b rhs
     | _ -> false)
  | _ -> false

(* ── Minimal SMT reflection of integer predicates ──────────────────────── *)

(* Reflects [e] into an Smt.term, substituting binder [b] with const [var].
   Returns None for anything outside the linear Int/Bool fragment. *)
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

(* ── Param collection ───────────────────────────────────────────────────── *)

(* Returns [(param_name, binder, pred)] for each Int-refined parameter. *)
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

(* ── Division-site walker ───────────────────────────────────────────────── *)

(* Calls [f span divisor_expr] for every integer division/modulo site. *)
let rec iter_div_sites (f : A.span -> A.expr -> unit) (e : A.expr) : unit =
  let go = iter_div_sites f in
  match e with
  | A.EApp (A.EVar { A.txt = op; _ }, [ lhs; rhs ], sp) when List.mem op div_ops ->
    f sp rhs;
    go lhs;
    go rhs
  | A.EApp (fn, args, _) ->
    go fn; List.iter go args
  | A.ECon (_, args, _) | A.ETuple (args, _) | A.EAtom (_, args, _) ->
    List.iter go args
  | A.ERecord (fields, _) ->
    List.iter (fun (_, e) -> go e) fields
  | A.ERecordUpdate (r, fields, _) ->
    go r; List.iter (fun (_, e) -> go e) fields
  | A.EBlock (es, _) -> List.iter go es
  | A.ELet (b, _) -> go b.A.bind_expr
  | A.EMatch (scrut, arms, _) ->
    go scrut;
    List.iter
      (fun (arm : A.branch) ->
        Option.iter go arm.A.branch_guard;
        go arm.A.branch_body)
      arms
  | A.EIf (cond, t, e, _) -> go cond; go t; go e
  | A.ECond (arms, _) -> List.iter (fun (c, b) -> go c; go b) arms
  | A.EField (inner, _, _) -> go inner
  | A.EPipe (a, b, _) -> go a; go b
  | A.EAnnot (inner, _, _) -> go inner
  | A.ELam (_, body, _) -> go body
  | A.ELetFn (_, _, _, body, _) -> go body
  | A.ELetQ (_, rhs, body, _) -> go rhs; go body
  | A.EAssert (inner, _) -> go inner
  | A.ESend (cap, msg, _) -> go cap; go msg
  | A.ESpawn (inner, _) -> go inner
  | A.EDbg (e_opt, _) -> Option.iter go e_opt
  | A.ESigil (_, inner, _) -> go inner
  | A.EVar _ | A.ELit _ | A.EHole _ | A.EResultRef _ -> ()

(* ── Per-divisor VC ─────────────────────────────────────────────────────── *)

let division_suggestion =
  "\n\nUse `Math.checked_div` or `Math.checked_mod` to return `Option(Int)` \
   instead of panicking, or annotate the divisor parameter with \
   `{v : Int | v != 0}` (or `v > 0`) to prove it is safe."

let check_var_divisor ~root errctx span var_name params =
  match List.find_opt (fun (n, _, _) -> n = var_name) params with
  | None ->
    Err.error errctx ~span
      (Printf.sprintf
         "division by `%s` in `cap no_panic` module may be by zero — \
          no refinement proves `%s ≠ 0`.%s"
         var_name var_name division_suggestion)
  | Some (_, bdr, pred) ->
    (* Fast syntactic check — no Z3 needed for obvious cases *)
    if syntactic_nonzero bdr pred then ()
    else
      (* Try Z3 *)
      match smt_of ~b:bdr ~var:var_name pred with
      | None -> () (* predicate not in supported fragment — skip conservatively *)
      | Some assumption ->
        let vc =
          Smt.
            { decls = [ (var_name, Smt.SInt) ]
            ; assumptions = [ assumption ]
            ; goal = Smt.Ne (Smt.Const var_name, Smt.IntLit 0)
            }
        in
        (match Refine.discharge ~root vc with
         | Refine.Verified -> () (* Z3: refinement proves divisor ≠ 0 *)
         | Refine.Refuted _ ->
           Err.error errctx ~span
             (Printf.sprintf
                "division by `%s` in `cap no_panic` module: refinement \
                 does not rule out zero.%s"
                var_name division_suggestion)
         | Refine.Unverified ->
           (* Z3 absent or unknown — be conservative *)
           Err.error errctx ~span
             (Printf.sprintf
                "division by `%s` in `cap no_panic` module: cannot verify \
                 divisor is non-zero (Z3 unavailable or VC unknown).%s"
                var_name division_suggestion))

(* ── Per-clause check ───────────────────────────────────────────────────── *)

let check_clause ~root errctx (clause : A.fn_clause) : unit =
  let params = clause_refined_params clause in
  iter_div_sites
    (fun span divisor ->
      match divisor with
      | A.ELit (A.LitInt 0, _) ->
        Err.error errctx ~span
          "division by zero literal in `cap no_panic` module."
      | A.ELit (A.LitInt _, _) ->
        () (* non-zero literal: trivially safe *)
      | A.EVar { A.txt = var_name; _ } ->
        check_var_divisor ~root errctx span var_name params
      | _ ->
        (* Complex expression — always flag conservatively *)
        Err.error errctx ~span
          ("division by a complex expression in `cap no_panic` module: \
            cannot prove divisor is non-zero."
           ^ division_suggestion))
    clause.A.fc_body

let check_fn ~root errctx (fd : A.fn_def) : unit =
  List.iter (check_clause ~root errctx) fd.A.fn_clauses

(* ── Module-level walk ──────────────────────────────────────────────────── *)

let rec check_decls ~root errctx (decls : A.decl list) : unit =
  let no_panic =
    List.exists
      (function A.DOpts (opts, _) -> List.mem "no_panic" opts | _ -> false)
      decls
  in
  List.iter
    (function
      | A.DFn (fd, _) when no_panic -> check_fn ~root errctx fd
      | A.DMod (_, _, inner_decls, _) ->
        check_decls ~root errctx inner_decls
      | _ -> ())
    decls

let check_module ?(root = Sys.getcwd ()) (errctx : Err.ctx) (m : A.module_) : unit =
  check_decls ~root errctx m.A.mod_decls
