(* Refinement checking (Phase A1b, minimal vertical slice).

   A post-typecheck pass over the parsed AST: it collects functions whose
   parameters carry an `{Int | predicate}` refinement, then walks every call
   site and, for each refined parameter, discharges a verification condition
   through the A0 Z3 bridge (`March_refine`):

     - a literal / refined-local argument is reflected into SMT and the
       precondition is proved (or refuted with a counterexample);
     - an argument we cannot soundly reflect (an unconstrained variable, a
       complex expression) is conservatively SKIPPED — no false positives.

   This is intentionally narrow: Int/Bool predicates over the binder `_` only,
   direct (named) calls only, no path sensitivity.  It exists to exercise the
   end-to-end pipeline; the full integration lives in the typechecker later. *)

module A = March_ast.Ast
module Smt = March_refine.Smt
module Refine = March_refine.Refine
module Err = March_errors.Errors

(* A refined parameter of some function: position, predicate binder, predicate. *)
type rparam = { idx : int; binder : string; pred : A.expr }

let binder_name : A.name option -> string = function
  | None -> "_"
  | Some n -> n.A.txt

let is_int_base : A.ty -> bool = function
  | A.TyCon ({ A.txt = "Int"; _ }, []) -> true
  | _ -> false

(* ── Translate the decidable predicate fragment to an SMT term ────────────── *)
(* [resolve] maps a variable name to its SMT term (the binder -> the actual
   argument; a refined-local -> its constant).  Returns None for anything
   outside the supported Int/Bool linear fragment. *)
let rec smt_of (resolve : string -> Smt.term option) (e : A.expr) : Smt.term option =
  let b2 f a b =
    match smt_of resolve a, smt_of resolve b with
    | Some x, Some y -> Some (f x y)
    | _ -> None
  in
  match e with
  | A.ELit (A.LitInt n, _) -> Some (Smt.IntLit n)
  | A.ELit (A.LitBool b, _) -> Some (Smt.BoolLit b)
  | A.EVar { A.txt; _ } -> resolve txt
  | A.EApp (A.EVar { A.txt = "&&"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.And (x, y)) a b
  | A.EApp (A.EVar { A.txt = "||"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Or (x, y)) a b
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) ->
    Option.map (fun x -> Smt.Not x) (smt_of resolve a)
  | A.EApp (A.EVar { A.txt = ">="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Ge (x, y)) a b
  | A.EApp (A.EVar { A.txt = "<="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Le (x, y)) a b
  | A.EApp (A.EVar { A.txt = ">"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Gt (x, y)) a b
  | A.EApp (A.EVar { A.txt = "<"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Lt (x, y)) a b
  | A.EApp (A.EVar { A.txt = "=="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Eq (x, y)) a b
  | A.EApp (A.EVar { A.txt = "!="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Ne (x, y)) a b
  | A.EApp (A.EVar { A.txt = "+"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Add (x, y)) a b
  | A.EApp (A.EVar { A.txt = "-"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Sub (x, y)) a b
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) ->
    Option.map (fun x -> Smt.Neg x) (smt_of resolve a)
  | A.EApp (A.EVar { A.txt = "*"; _ }, [ a; b ], _) ->
    (* linear arithmetic only: one factor must be an integer literal *)
    (match a, b with
     | A.ELit (A.LitInt k, _), _ -> Option.map (fun y -> Smt.MulLit (k, y)) (smt_of resolve b)
     | _, A.ELit (A.LitInt k, _) -> Option.map (fun x -> Smt.MulLit (k, x)) (smt_of resolve a)
     | _ -> None)
  | _ -> None

(* User-facing infix rendering of a predicate (best-effort; falls back to a
   generic phrase). *)
let rec pred_str (e : A.expr) : string =
  let binop op a b = pred_str a ^ " " ^ op ^ " " ^ pred_str b in
  match e with
  | A.ELit (A.LitInt n, _) -> string_of_int n
  | A.ELit (A.LitBool b, _) -> if b then "true" else "false"
  | A.EVar { A.txt; _ } -> txt
  | A.EApp (A.EVar { A.txt = ("&&" | "||" | ">=" | "<=" | ">" | "<" | "==" | "!=" | "+" | "-" | "*") as op; _ }, [ a; b ], _) ->
    binop op a b
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) -> "!" ^ pred_str a
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) -> "-" ^ pred_str a
  | _ -> "<predicate>"

(* ── Scope of refined locals/params: name -> (binder, predicate) ─────────── *)
type scope = (string * (string * A.expr)) list

let refined_int_ty : A.ty option -> (string * A.expr) option = function
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred)
  | _ -> None

let scope_add_param (sc : scope) (p : A.param) : scope =
  match refined_int_ty p.A.param_ty with
  | Some r -> (p.A.param_name.A.txt, r) :: sc
  | None -> sc

let scope_add_fnparam (sc : scope) : A.fn_param -> scope = function
  | A.FPNamed p | A.FPDefault (p, _) -> scope_add_param sc p
  | A.FPPat _ -> sc

let scope_add_binding (sc : scope) (b : A.binding) : scope =
  match b.A.bind_pat, refined_int_ty b.A.bind_ty with
  | A.PatVar n, Some r -> (n.A.txt, r) :: sc
  | _ -> sc

(* ── Collect refined-parameter signatures, keyed by bare + qualified name ── *)
type sigs = (string, rparam list) Hashtbl.t

let params_of_clause (c : A.fn_clause) : rparam list =
  List.filteri (fun _ _ -> true) c.A.fc_params
  |> List.mapi (fun idx p -> (idx, p))
  |> List.filter_map (fun (idx, fp) ->
         match fp with
         | A.FPNamed p | A.FPDefault (p, _) ->
           (match refined_int_ty p.A.param_ty with
            | Some (binder, pred) -> Some { idx; binder; pred }
            | None -> None)
         | A.FPPat _ -> None)

let rec collect_sigs (tbl : sigs) (prefix : string) (decls : A.decl list) : unit =
  List.iter
    (function
      | A.DFn (fd, _) ->
        let rps = List.concat_map params_of_clause fd.A.fn_clauses in
        if rps <> [] then begin
          Hashtbl.replace tbl fd.A.fn_name.A.txt rps;
          if prefix <> "" then Hashtbl.replace tbl (prefix ^ "." ^ fd.A.fn_name.A.txt) rps
        end
      | A.DMod (name, _, ds, _) ->
        let p = if prefix = "" then name.A.txt else prefix ^ "." ^ name.A.txt in
        collect_sigs tbl p ds
      | _ -> ())
    decls

(* ── Reflect an actual argument into (term, decls, assumptions) ──────────── *)
let reflect_actual (sc : scope) (actual : A.expr)
  : (Smt.term * (string * Smt.sort) list * Smt.term list) option =
  match actual with
  | A.EVar { A.txt = x; _ } ->
    (match List.assoc_opt x sc with
     | Some (b, q) ->
       let xc = Smt.Const x in
       let resolve n = if n = b || n = "_" then Some xc else None in
       let assumptions = match smt_of resolve q with Some qa -> [ qa ] | None -> [] in
       Some (xc, [ (x, Smt.SInt) ], assumptions)
     | None -> None (* unconstrained variable: cannot prove soundly — skip *))
  | _ -> (match smt_of (fun _ -> None) actual with Some t -> Some (t, [], []) | None -> None)

(* ── Check one (refined param, actual argument) pair at a call site ──────── *)
let check_call ~root errctx ~span (rp : rparam) (actual : A.expr) (sc : scope) : unit =
  match reflect_actual sc actual with
  | None -> ()
  | Some (aterm, decls, assumptions) ->
    let resolve n = if n = rp.binder || n = "_" then Some aterm else None in
    (match smt_of resolve rp.pred with
     | None -> () (* predicate outside the supported fragment — skip *)
     | Some goal ->
       let vc = { Smt.decls; assumptions; goal } in
       (match Refine.discharge ~root vc with
        | Refine.Verified -> ()
        | Refine.Refuted model ->
          let cx =
            model
            |> List.map (fun (k, v) -> k ^ " = " ^ v)
            |> String.concat ", "
          in
          Err.error errctx ~span
            (Printf.sprintf
               "refinement violation: argument does not satisfy precondition `%s`%s"
               (pred_str rp.pred)
               (if cx = "" then "" else Printf.sprintf " (counterexample: %s)" cx))
        | Refine.Unverified -> () (* z3 unavailable / unknown — silent in A1b *)))

(* ── Walk expressions, threading the refined-local scope ─────────────────── *)
let rec visit ~root errctx (tbl : sigs) (sc : scope) (e : A.expr) : unit =
  let go = visit ~root errctx tbl sc in
  match e with
  | A.EApp (A.EVar { A.txt = fname; _ }, args, sp) ->
    (match Hashtbl.find_opt tbl fname with
     | Some rps ->
       List.iter
         (fun rp ->
           match List.nth_opt args rp.idx with
           | Some actual -> check_call ~root errctx ~span:sp rp actual sc
           | None -> ())
         rps
     | None -> ());
    List.iter go args
  | A.EApp (f, args, _) -> go f; List.iter go args
  | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> List.iter go args
  | A.EBlock (es, _) ->
    (* block-scoped lets: thread scope left to right *)
    ignore
      (List.fold_left
         (fun sc e ->
           visit ~root errctx tbl sc e;
           match e with A.ELet (b, _) -> scope_add_binding sc b | _ -> sc)
         sc es)
  | A.ELet (b, _) -> go b.A.bind_expr
  | A.ELam (ps, body, _) ->
    let sc' = List.fold_left scope_add_param sc ps in
    visit ~root errctx tbl sc' body
  | A.ELetFn (_, ps, _, body, _) ->
    let sc' = List.fold_left scope_add_param sc ps in
    visit ~root errctx tbl sc' body
  | A.EMatch (subj, branches, _) ->
    go subj;
    List.iter (fun (br : A.branch) -> go br.A.branch_body) branches
  | A.EIf (c, t, e, _) -> go c; go t; go e
  | A.ECond (arms, _) -> List.iter (fun (c, b) -> go c; go b) arms
  | A.ERecord (fields, _) -> List.iter (fun (_, v) -> go v) fields
  | A.ERecordUpdate (r, fields, _) -> go r; List.iter (fun (_, v) -> go v) fields
  | A.EField (r, _, _) -> go r
  | A.EPipe (a, b, _) -> go a; go b
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _) -> go e
  | A.ESend (a, b, _) -> go a; go b
  | A.ELetQ (_, e1, e2, _) -> go e1; go e2
  | A.EDbg (Some e, _) -> go e
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> ()

(* Walk a function body with its refined Int params in scope. *)
let visit_fn ~root errctx (tbl : sigs) (fd : A.fn_def) : unit =
  List.iter
    (fun (c : A.fn_clause) ->
      let sc = List.fold_left scope_add_fnparam [] c.A.fc_params in
      visit ~root errctx tbl sc c.A.fc_body)
    fd.A.fn_clauses

let rec visit_decls ~root errctx (tbl : sigs) (decls : A.decl list) : unit =
  List.iter
    (function
      | A.DFn (fd, _) -> visit_fn ~root errctx tbl fd
      | A.DMod (_, _, ds, _) -> visit_decls ~root errctx tbl ds
      | _ -> ())
    decls

(** Entry point: check refinement preconditions across [m], emitting
    diagnostics into [errctx].  [root] is the project root for the VC cache. *)
let check_module ?(root = Sys.getcwd ()) (errctx : Err.ctx) (m : A.module_) : unit =
  let tbl : sigs = Hashtbl.create 64 in
  collect_sigs tbl "" m.A.mod_decls;
  if Hashtbl.length tbl > 0 then visit_decls ~root errctx tbl m.A.mod_decls
