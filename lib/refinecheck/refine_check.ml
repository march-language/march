(* Refinement checking (Phases A1b + A2, minimal vertical slice).

   A post-typecheck pass over the AST: it collects functions whose parameters
   carry an `{Int | predicate}` refinement, then walks every call site and, for
   each refined parameter, discharges a verification condition through the A0
   Z3 bridge (`March_refine`).

   A1b: Int/Bool predicates over the binder `_`, literal / refined-local args.
   A2 : the `len` measure and cross-argument predicates, so bounds such as
        `{Int | _ >= 0 && _ < len(xs)}` are checkable when the length is known
        (a list literal) or symbolically related.

   Soundness stance: an argument we cannot reflect (an unconstrained variable,
   a complex expression) is conservatively SKIPPED — no false positives.
   Scope: direct (named) calls only, no path sensitivity. *)

module A = March_ast.Ast
module Smt = March_refine.Smt
module Refine = March_refine.Refine
module Err = March_errors.Errors

(* A refined parameter: position, predicate binder, predicate expression. *)
type rparam = { idx : int; binder : string; pred : A.expr }

(* A function's signature: parameter names by position + its refined params. *)
type fn_sig = { param_names : string list; refined : rparam list }
type sigs = (string, fn_sig) Hashtbl.t

let binder_name : A.name option -> string = function
  | None -> "_"
  | Some n -> n.A.txt

let is_int_base : A.ty -> bool = function
  | A.TyCon ({ A.txt = "Int"; _ }, []) -> true
  | _ -> false

(* Length of a list literal (a Cons/Nil ECon chain); None if not a literal. *)
let rec list_len (e : A.expr) : int option =
  match e with
  | A.ECon ({ A.txt = "Nil"; _ }, _, _) -> Some 0
  | A.ECon ({ A.txt = "Cons"; _ }, [ _; tl ], _) ->
    (match list_len tl with Some n -> Some (n + 1) | None -> None)
  | _ -> None

(* ── Translate the decidable predicate fragment to an SMT term ────────────── *)
(* [resolve_var] maps a scalar variable to its SMT term; [resolve_len] maps a
   measure target name to a length term.  None => outside the supported
   Int/Bool linear fragment. *)
let rec smt_of ~resolve_var ~resolve_len (e : A.expr) : Smt.term option =
  let r = smt_of ~resolve_var ~resolve_len in
  let b2 f a b = match r a, r b with Some x, Some y -> Some (f x y) | _ -> None in
  match e with
  | A.ELit (A.LitInt n, _) -> Some (Smt.IntLit n)
  | A.ELit (A.LitBool b, _) -> Some (Smt.BoolLit b)
  | A.EApp (A.EVar { A.txt = "len"; _ }, [ a ], _) ->
    (match a with
     | A.EVar { A.txt; _ } -> resolve_len txt
     | _ -> (match list_len a with Some n -> Some (Smt.IntLit n) | None -> None))
  | A.EVar { A.txt; _ } -> resolve_var txt
  | A.EApp (A.EVar { A.txt = "&&"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.And (x, y)) a b
  | A.EApp (A.EVar { A.txt = "||"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Or (x, y)) a b
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) -> Option.map (fun x -> Smt.Not x) (r a)
  | A.EApp (A.EVar { A.txt = ">="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Ge (x, y)) a b
  | A.EApp (A.EVar { A.txt = "<="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Le (x, y)) a b
  | A.EApp (A.EVar { A.txt = ">"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Gt (x, y)) a b
  | A.EApp (A.EVar { A.txt = "<"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Lt (x, y)) a b
  | A.EApp (A.EVar { A.txt = "=="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Eq (x, y)) a b
  | A.EApp (A.EVar { A.txt = "!="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Ne (x, y)) a b
  | A.EApp (A.EVar { A.txt = "+"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Add (x, y)) a b
  | A.EApp (A.EVar { A.txt = "-"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Sub (x, y)) a b
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) -> Option.map (fun x -> Smt.Neg x) (r a)
  | A.EApp (A.EVar { A.txt = "*"; _ }, [ a; b ], _) ->
    (match a, b with
     | A.ELit (A.LitInt k, _), _ -> Option.map (fun y -> Smt.MulLit (k, y)) (r b)
     | _, A.ELit (A.LitInt k, _) -> Option.map (fun x -> Smt.MulLit (k, x)) (r a)
     | _ -> None)
  | _ -> None

(* User-facing infix rendering of a predicate (best-effort). *)
let rec pred_str (e : A.expr) : string =
  let binop op a b = pred_str a ^ " " ^ op ^ " " ^ pred_str b in
  match e with
  | A.ELit (A.LitInt n, _) -> string_of_int n
  | A.ELit (A.LitBool b, _) -> if b then "true" else "false"
  | A.EApp (A.EVar { A.txt = "len"; _ }, [ a ], _) -> "len(" ^ pred_str a ^ ")"
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

(* ── Collect signatures, keyed by bare + qualified name ──────────────────── *)
let param_name_of : A.fn_param -> string = function
  | A.FPNamed p | A.FPDefault (p, _) -> p.A.param_name.A.txt
  | A.FPPat _ -> "_"

let sig_of_clause (c : A.fn_clause) : fn_sig =
  let param_names = List.map param_name_of c.A.fc_params in
  let refined =
    List.mapi (fun idx fp -> (idx, fp)) c.A.fc_params
    |> List.filter_map (fun (idx, fp) ->
           match fp with
           | A.FPNamed p | A.FPDefault (p, _) ->
             (match refined_int_ty p.A.param_ty with
              | Some (binder, pred) -> Some { idx; binder; pred }
              | None -> None)
           | A.FPPat _ -> None)
  in
  { param_names; refined }

let rec collect_sigs (tbl : sigs) (prefix : string) (decls : A.decl list) : unit =
  List.iter
    (function
      | A.DFn (fd, _) ->
        let sg =
          match fd.A.fn_clauses with
          | c :: _ -> sig_of_clause c
          | [] -> { param_names = []; refined = [] }
        in
        if sg.refined <> [] then begin
          Hashtbl.replace tbl fd.A.fn_name.A.txt sg;
          if prefix <> "" then Hashtbl.replace tbl (prefix ^ "." ^ fd.A.fn_name.A.txt) sg
        end
      | A.DMod (name, _, ds, _) ->
        let p = if prefix = "" then name.A.txt else prefix ^ "." ^ name.A.txt in
        collect_sigs tbl p ds
      | _ -> ())
    decls

(* ── Reflect a scalar actual argument into (term, decls, assumptions) ─────── *)
let reflect_scalar (sc : scope) (actual : A.expr)
  : (Smt.term * (string * Smt.sort) list * Smt.term list) option =
  match actual with
  | A.EVar { A.txt = x; _ } ->
    let xc = Smt.Const x in
    (match List.assoc_opt x sc with
     | Some (b, q) ->
       (* A refined local: carry its own refinement as an assumption. *)
       let rv n = if n = b || n = "_" then Some xc else None in
       let assumptions =
         match smt_of ~resolve_var:rv ~resolve_len:(fun _ -> None) q with
         | Some qa -> [ qa ]
         | None -> []
       in
       Some (xc, [ (x, Smt.SInt) ], assumptions)
     | None ->
       (* An ordinary variable: reflect it as a constant so a path-context
          guard about it can constrain it.  Without a guard it stays
          unconstrained and the definite-failure check keeps us silent. *)
       Some (xc, [ (x, Smt.SInt) ], []))
  | _ ->
    (match smt_of ~resolve_var:(fun _ -> None) ~resolve_len:(fun _ -> None) actual with
     | Some t -> Some (t, [], [])
     | None -> None)

(* ── Check one refined parameter at a call site ──────────────────────────── *)
(* [path] is the path context: conditions known true here, each tagged with
   whether it is negated (the else-branch of an `if`). *)
let check_call ~root errctx ~span (sg : fn_sig) (args : A.expr list)
    (path : (A.expr * bool) list) (rp : rparam) (sc : scope) : unit =
  let name_pos = List.mapi (fun i n -> (n, i)) sg.param_names in
  let actual_of_name name =
    match List.assoc_opt name name_pos with
    | Some i -> List.nth_opt args i
    | None -> None
  in
  match List.nth_opt args rp.idx with
  | None -> ()
  | Some self_actual ->
    let decls = ref [] and assume = ref [] in
    let absorb = function
      | Some (t, d, a) -> decls := d @ !decls; assume := a @ !assume; Some t
      | None -> None
    in
    (* Resolve a scalar variable.  A predicate references callee parameters;
       a path condition references caller variables — both go through the
       actual caller values so the names line up in SMT. *)
    let resolve_var name =
      if name = rp.binder || name = "_" then absorb (reflect_scalar sc self_actual)
      else
        match actual_of_name name with
        | Some a -> absorb (reflect_scalar sc a)
        | None ->
          (* a caller-scope variable from the path context *)
          decls := (name, Smt.SInt) :: !decls;
          Some (Smt.Const name)
    in
    let len_of_var x =
      let c = Smt.Const ("len$" ^ x) in
      decls := ("len$" ^ x, Smt.SInt) :: !decls;
      assume := Smt.Ge (c, Smt.IntLit 0) :: !assume; (* measure axiom: len >= 0 *)
      Some c
    in
    let resolve_len name =
      match actual_of_name name with
      | Some a -> (
          match list_len a with
          | Some n -> Some (Smt.IntLit n)
          | None -> (match a with A.EVar { A.txt = x; _ } -> len_of_var x | _ -> None))
      | None -> len_of_var name (* a caller-scope list variable *)
    in
    (* Translate the path conditions into assumptions (dropping any that fall
       outside the supported fragment — sound, just weaker). *)
    List.iter
      (fun (cond, negated) ->
        match smt_of ~resolve_var ~resolve_len cond with
        | Some t -> assume := (if negated then Smt.Not t else t) :: !assume
        | None -> ())
      path;
    (match smt_of ~resolve_var ~resolve_len rp.pred with
     | None -> ()
     | Some goal ->
       (* de-duplicate decls (a symbol may be requested twice) *)
       let decls =
         List.fold_left
           (fun acc d -> if List.mem d acc then acc else d :: acc)
           [] !decls
       in
       let vc = { Smt.decls; assumptions = !assume; goal } in
       (* Report a violation ONLY when the precondition can *never* hold under
          the assumptions (a definite failure).  If it merely *might* fail
          (e.g. a symbolic, unknown length), that is unprovable either way and
          we stay silent — no false positives.

          - discharge(goal=G) Verified  => G always holds        => pass
          - else discharge(goal=¬G) Verified => G never holds     => violation
          - otherwise (G depends on unknowns / solver unsure)     => skip *)
       (match Refine.discharge ~root vc with
        | Refine.Verified -> ()
        | first ->
          (match Refine.discharge ~root { vc with Smt.goal = Smt.Not goal } with
           | Refine.Verified ->
             let cx =
               match first with
               | Refine.Refuted model ->
                 model |> List.map (fun (k, v) -> k ^ " = " ^ v) |> String.concat ", "
               | _ -> ""
             in
             Err.error errctx ~span
               (Printf.sprintf
                  "refinement violation: argument does not satisfy precondition `%s`%s"
                  (pred_str rp.pred)
                  (if cx = "" then "" else Printf.sprintf " (counterexample: %s)" cx))
           | _ -> ())))

(* ── Walk expressions, threading the refined-local scope and path context ── *)
let rec visit ~root errctx (tbl : sigs) (path : (A.expr * bool) list) (sc : scope)
    (e : A.expr) : unit =
  let go = visit ~root errctx tbl path sc in
  let go_path p = visit ~root errctx tbl p sc in
  match e with
  | A.EApp (A.EVar { A.txt = fname; _ }, args, sp) ->
    (match Hashtbl.find_opt tbl fname with
     | Some sg ->
       List.iter (fun rp -> check_call ~root errctx ~span:sp sg args path rp sc) sg.refined
     | None -> ());
    List.iter go args
  | A.EApp (f, args, _) -> go f; List.iter go args
  | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> List.iter go args
  | A.EBlock (es, _) ->
    ignore
      (List.fold_left
         (fun sc e ->
           visit ~root errctx tbl path sc e;
           match e with A.ELet (b, _) -> scope_add_binding sc b | _ -> sc)
         sc es)
  | A.ELet (b, _) -> go b.A.bind_expr
  | A.ELam (ps, body, _) ->
    visit ~root errctx tbl path (List.fold_left scope_add_param sc ps) body
  | A.ELetFn (_, ps, _, body, _) ->
    visit ~root errctx tbl path (List.fold_left scope_add_param sc ps) body
  | A.EMatch (subj, branches, _) ->
    go subj;
    List.iter
      (fun (br : A.branch) ->
        let p = match br.A.branch_guard with Some g -> (g, false) :: path | None -> path in
        go_path p br.A.branch_body)
      branches
  | A.EIf (c, t, e, _) ->
    go c;
    go_path ((c, false) :: path) t;
    go_path ((c, true) :: path) e
  | A.ECond (arms, _) ->
    List.iter (fun (c, b) -> go c; go_path ((c, false) :: path) b) arms
  | A.ERecord (fields, _) -> List.iter (fun (_, v) -> go v) fields
  | A.ERecordUpdate (r, fields, _) -> go r; List.iter (fun (_, v) -> go v) fields
  | A.EField (r, _, _) -> go r
  | A.EPipe (a, b, _) -> go a; go b
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _) -> go e
  | A.ESend (a, b, _) -> go a; go b
  | A.ELetQ (_, e1, e2, _) -> go e1; go e2
  | A.EDbg (Some e, _) -> go e
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> ()

let visit_fn ~root errctx (tbl : sigs) (fd : A.fn_def) : unit =
  List.iter
    (fun (c : A.fn_clause) ->
      let sc = List.fold_left scope_add_fnparam [] c.A.fc_params in
      let path = match c.A.fc_guard with Some g -> [ (g, false) ] | None -> [] in
      visit ~root errctx tbl path sc c.A.fc_body)
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
