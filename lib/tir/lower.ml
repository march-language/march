(** AST → TIR lowering pass.

    Converts desugared [Ast.module_] to [Tir.tir_module] in A-normal form.
    Key transformations:
    - All intermediate results named via [Tir.ELet] using CPS-style let-insertion
    - Blocks → right-nested [ELet] chains
    - Nested patterns → nested [ECase]
    - [EIf] → [ECase] on bool

    ANF conversion uses continuation-passing: [lower_to_atom_k e k] lowers [e]
    and calls [k atom] with the resulting atom. If [e] is not already atomic,
    a fresh [ELet] binding wraps the continuation. This ensures all call
    arguments are atoms without dangling variable references. *)

module Ast = March_ast.Ast
module Typecheck = March_typecheck.Typecheck

(* ── Fresh name generation ──────────────────────────────────────── *)

let _lower_counter = ref 0

let fresh_name (prefix : string) : string =
  incr _lower_counter;
  Printf.sprintf "$%s%d" prefix !_lower_counter

let reset_counter () = _lower_counter := 0

let fresh_var ?(lin = Tir.Unr) (ty : Tir.ty) : Tir.var =
  { v_name = fresh_name "t"; v_ty = ty; v_lin = lin }

(* ── Type conversion: Ast.ty → Tir.ty ──────────────────────────── *)

(** Default type used when no annotation is available. A placeholder
    that will be resolved during monomorphization. *)
let unknown_ty = Tir.TVar "_"

(** Convert surface types to TIR types.
    Pre-monomorphization, type variables become [TVar]. *)
let rec lower_ty (t : Ast.ty) : Tir.ty =
  match t with
  | Ast.TyCon ({ txt = "Int"; _ }, [])    -> Tir.TInt
  | Ast.TyCon ({ txt = "Float"; _ }, [])  -> Tir.TFloat
  | Ast.TyCon ({ txt = "Bool"; _ }, [])   -> Tir.TBool
  | Ast.TyCon ({ txt = "String"; _ }, []) -> Tir.TString
  | Ast.TyCon ({ txt = "Unit"; _ }, [])   -> Tir.TUnit
  | Ast.TyCon ({ txt = name; _ }, args)   ->
    Tir.TCon (name, List.map lower_ty args)
  | Ast.TyVar { txt = name; _ }          -> Tir.TVar name
  | Ast.TyArrow (a, b)                   -> Tir.TFn ([lower_ty a], lower_ty b)
  | Ast.TyTuple ts                        -> Tir.TTuple (List.map lower_ty ts)
  | Ast.TyRecord fields                   ->
    let fs = List.map (fun (n, t) -> (n.Ast.txt, lower_ty t)) fields in
    Tir.TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) fs)
  | Ast.TyLinear (_, t)                   -> lower_ty t  (* linearity tracked on var *)
  | Ast.TyNat n                           -> Tir.TCon ("Nat", [Tir.TCon (string_of_int n, [])])
  | Ast.TyNatOp _                         -> Tir.TCon ("NatOp", [])  (* placeholder *)

(** Convert AST linearity to TIR linearity. *)
let lower_linearity : Ast.linearity -> Tir.linearity = function
  | Ast.Linear       -> Tir.Lin
  | Ast.Affine       -> Tir.Aff
  | Ast.Unrestricted -> Tir.Unr

(* ── Type conversion: Typecheck.ty → Tir.ty ─────────────────── *)

(** Convert an internal typechecker type to a TIR type.
    [Typecheck.TArrow] is curried; we uncurry into [Tir.TFn]. *)
let rec convert_ty (t : Typecheck.ty) : Tir.ty =
  match Typecheck.repr t with
  | Typecheck.TCon ("Int",    []) -> Tir.TInt
  | Typecheck.TCon ("Float",  []) -> Tir.TFloat
  | Typecheck.TCon ("Bool",   []) -> Tir.TBool
  | Typecheck.TCon ("String", []) -> Tir.TString
  | Typecheck.TCon ("Unit",   []) -> Tir.TUnit
  | Typecheck.TCon (name, args)   -> Tir.TCon (name, List.map convert_ty args)
  | Typecheck.TArrow _ as t ->
    let rec collect acc = function
      | Typecheck.TArrow (a, b) -> collect (convert_ty a :: acc) (Typecheck.repr b)
      | ret -> (List.rev acc, convert_ty ret)
    in
    let (params, ret) = collect [] t in
    Tir.TFn (params, ret)
  | Typecheck.TTuple tys ->
    Tir.TTuple (List.map convert_ty tys)
  | Typecheck.TRecord fields ->
    Tir.TRecord (List.map (fun (n, t) -> (n, convert_ty t)) fields)
  | Typecheck.TVar r ->
    (match !r with
     | Typecheck.Unbound (id, _) -> Tir.TVar (Printf.sprintf "_%d" id)
     | Typecheck.Link _ -> assert false)
  | Typecheck.TLin (_, inner) -> convert_ty inner
  | Typecheck.TNat n          -> Tir.TCon (Printf.sprintf "Nat_%d" n, [])
  | Typecheck.TNatOp _        -> Tir.TVar "_natop"
  | Typecheck.TError          -> Tir.TVar "_err"

(* ── Type map reference (set by lower_module, used by lower_expr) ── *)

(** Optional typechecker type_map threaded through lowering.
    Looked up by expression span to produce concrete types instead
    of [unknown_ty] placeholders. Set at [lower_module] entry. *)
let _type_map_ref : (Ast.span, Typecheck.ty) Hashtbl.t option ref = ref None

(** Look up the TIR type for an expression from the type_map.
    Falls back to [unknown_ty] when no type_map is set or the span
    is not present (e.g. spans introduced by desugaring). *)
let ty_of_span (sp : Ast.span) : Tir.ty =
  match !_type_map_ref with
  | None -> unknown_ty
  | Some tbl ->
    (match Hashtbl.find_opt tbl sp with
     | Some t -> convert_ty t
     | None   -> unknown_ty)

let ty_of_expr (e : Ast.expr) : Tir.ty =
  ty_of_span (Typecheck.span_of_expr e)

(* ── CPS-based ANF lowering ────────────────────────────────────── *)

(** Lower an expression, ensuring the result is an atom.
    [k] is called with the resulting atom, and any necessary [ELet]
    bindings are wrapped around the result of [k].

    This is the core ANF trick: non-atomic expressions get a fresh
    variable name, their lowered form becomes the RHS of an [ELet],
    and the continuation [k] receives the bound variable as an atom. *)
let rec lower_to_atom_k (e : Ast.expr) (k : Tir.atom -> Tir.expr) : Tir.expr =
  match e with
  | Ast.ELit (lit, _) -> k (Tir.ALit lit)
  | Ast.EVar { txt = name; span; _ } ->
    k (Tir.AVar { v_name = name; v_ty = ty_of_span span; v_lin = Tir.Unr })
  | _ ->
    let rhs = lower_expr e in
    let v = fresh_var (ty_of_expr e) in
    Tir.ELet (v, rhs, k (Tir.AVar v))

(** Lower a list of expressions to atoms using CPS. *)
and lower_atoms_k (es : Ast.expr list) (k : Tir.atom list -> Tir.expr) : Tir.expr =
  match es with
  | [] -> k []
  | e :: rest ->
    lower_to_atom_k e (fun a ->
      lower_atoms_k rest (fun rest_atoms ->
        k (a :: rest_atoms)))

(** Translate an AST expression to a TIR expression in ANF. *)
and lower_expr (e : Ast.expr) : Tir.expr =
  match e with
  (* --- Atoms --- *)
  | Ast.ELit (lit, _) -> Tir.EAtom (Tir.ALit lit)

  | Ast.EVar { txt = name; span; _ } ->
    Tir.EAtom (Tir.AVar { v_name = name; v_ty = ty_of_span span; v_lin = Tir.Unr })

  (* --- Let bindings --- *)
  | Ast.ELet (b, _) ->
    lower_expr b.bind_expr

  (* --- Blocks → right-nested ELet --- *)
  | Ast.EBlock ([], _) -> Tir.EAtom (Tir.ALit (Ast.LitAtom "unit"))
  | Ast.EBlock ([e], _) -> lower_expr e
  | Ast.EBlock (Ast.ELet (b, _) :: rest, sp) ->
    let rhs = lower_expr b.bind_expr in
    let body = lower_expr (Ast.EBlock (rest, sp)) in
    (match b.bind_pat with
     | Ast.PatVar n ->
       let v : Tir.var = {
         v_name = n.txt;
         v_ty = (match b.bind_ty with Some t -> lower_ty t | None -> ty_of_expr b.bind_expr);
         v_lin = lower_linearity b.bind_lin;
       } in
       Tir.ELet (v, rhs, body)
     | Ast.PatTuple (pats, _) ->
       (* let (a, b, ...) = rhs  →  let $p = rhs; let a = $p.$fv0; let b = $p.$fv1; … *)
       let tname = fresh_name "p" in
       let tv : Tir.var = { v_name = tname; v_ty = unknown_ty; v_lin = Tir.Lin } in
       let tv_atom = Tir.AVar tv in
       (* Build inner ELet chain: fold_right so field 0 is the outermost let *)
       let body_with_fields =
         List.fold_right (fun (i, pat) inner ->
           match pat with
           | Ast.PatVar n ->
             let fv : Tir.var = { v_name = n.txt; v_ty = unknown_ty; v_lin = Tir.Lin } in
             Tir.ELet (fv, Tir.EField (tv_atom, Printf.sprintf "$fv%d" i), inner)
           | _ -> inner  (* wildcard / other → skip *)
         ) (List.mapi (fun i p -> (i, p)) pats) body
       in
       Tir.ELet (tv, rhs, body_with_fields)
     | _ ->
       let bind_name = fresh_name "p" in
       let v : Tir.var = {
         v_name = bind_name;
         v_ty = (match b.bind_ty with Some t -> lower_ty t | None -> ty_of_expr b.bind_expr);
         v_lin = lower_linearity b.bind_lin;
       } in
       Tir.ELet (v, rhs, body))
  (* --- ELetFn as block statement → bind function name in rest of block --- *)
  | Ast.EBlock (Ast.ELetFn (name, params, ret_ty_ann, fn_body, _) :: rest, sp) ->
    let fn_name = name.Ast.txt in
    let params' = List.map (fun (p : Ast.param) ->
        { Tir.v_name = p.param_name.txt;
          v_ty = (match p.param_ty with Some t -> lower_ty t | None -> ty_of_span p.param_name.span);
          v_lin = lower_linearity p.param_lin }
      ) params in
    let fn_body' = lower_expr fn_body in
    let ret_ty = match ret_ty_ann with Some t -> lower_ty t | None -> ty_of_expr fn_body in
    let fn : Tir.fn_def = {
      fn_name; fn_params = params'; fn_ret_ty = ret_ty; fn_body = fn_body'
    } in
    let fn_var : Tir.var = {
      v_name = fn_name;
      v_ty = Tir.TFn (List.map (fun v -> v.Tir.v_ty) params', ret_ty);
      v_lin = Tir.Unr
    } in
    let fn_expr = Tir.ELetRec ([fn], Tir.EAtom (Tir.AVar fn_var)) in
    let block_body = lower_expr (Ast.EBlock (rest, sp)) in
    Tir.ELet (fn_var, fn_expr, block_body)
  | Ast.EBlock (e :: rest, sp) ->
    let e' = lower_expr e in
    let body = lower_expr (Ast.EBlock (rest, sp)) in
    Tir.ESeq (e', body)

  (* --- If → ECase on bool (CPS for condition) --- *)
  | Ast.EIf (cond, then_e, else_e, _) ->
    lower_to_atom_k cond (fun cond_atom ->
      let then' = lower_expr then_e in
      let else' = lower_expr else_e in
      Tir.ECase (cond_atom,
        [{ br_tag = "True"; br_vars = []; br_body = then' }],
        Some else'))

  (* --- Tuples (CPS for elements) --- *)
  | Ast.ETuple (es, _) ->
    lower_atoms_k es (fun atoms -> Tir.ETuple atoms)

  (* --- Records (CPS for field values) --- *)
  | Ast.ERecord (fields, _) ->
    let names = List.map (fun (n, _) -> n.Ast.txt) fields in
    let exprs = List.map snd fields in
    lower_atoms_k exprs (fun atoms ->
      Tir.ERecord (List.combine names atoms))

  | Ast.ERecordUpdate (base, updates, _) ->
    lower_to_atom_k base (fun base_atom ->
      let names = List.map (fun (n, _) -> n.Ast.txt) updates in
      let exprs = List.map snd updates in
      lower_atoms_k exprs (fun atoms ->
        Tir.EUpdate (base_atom, List.combine names atoms)))

  | Ast.EField (e, { txt = name; _ }, _) ->
    lower_to_atom_k e (fun a -> Tir.EField (a, name))

  (* --- Function application (CPS: all args must be atoms) --- *)
  | Ast.EApp (f_expr, args, _) ->
    lower_to_atom_k f_expr (fun f_atom ->
      lower_atoms_k args (fun arg_atoms ->
        let f_var = match f_atom with
          | Tir.AVar v -> v
          | Tir.ALit _ ->
            { v_name = "<lit>"; v_ty = unknown_ty; v_lin = Tir.Unr }
        in
        Tir.EApp (f_var, arg_atoms)))

  (* --- Constructor application (CPS for args) --- *)
  | Ast.ECon ({ txt = tag; _ }, args, _) ->
    lower_atoms_k args (fun arg_atoms ->
      Tir.EAlloc (Tir.TCon (tag, []), arg_atoms))

  (* --- Lambda → ELetRec with a single fn_def --- *)
  | Ast.ELam (params, body, lam_span) ->
    let fn_name = fresh_name "lam" in
    (* Extract param types from the lambda's inferred type when no annotation. *)
    let lam_ty = ty_of_span lam_span in
    let inferred_param_tys = match lam_ty with
      | Tir.TFn (ps, _) -> ps
      | _ -> List.map (fun _ -> unknown_ty) params
    in
    let params' = List.mapi (fun i (p : Ast.param) ->
        { Tir.v_name = p.param_name.txt;
          v_ty = (match p.param_ty with Some t -> lower_ty t
                  | None -> List.nth_opt inferred_param_tys i
                            |> Option.value ~default:unknown_ty);
          v_lin = lower_linearity p.param_lin }
      ) params in
    let body' = lower_expr body in
    let ret_ty = ty_of_expr body in
    let fn : Tir.fn_def = {
      fn_name; fn_params = params'; fn_ret_ty = ret_ty; fn_body = body'
    } in
    let fn_var : Tir.var = {
      v_name = fn_name;
      v_ty = Tir.TFn (List.map (fun v -> v.Tir.v_ty) params', ret_ty);
      v_lin = Tir.Unr
    } in
    Tir.ELetRec ([fn], Tir.EAtom (Tir.AVar fn_var))

  (* --- Match → ECase (CPS for scrutinee) --- *)
  | Ast.EMatch (scrut, branches, _) ->
    lower_to_atom_k scrut (fun scrut_atom ->
      lower_match scrut_atom branches)

  (* --- Annotations: lower the inner expr --- *)
  | Ast.EAnnot (e, _, _) -> lower_expr e

  (* --- Atoms (the :tag syntax) --- *)
  | Ast.EAtom (a, [], _) -> Tir.EAtom (Tir.ALit (Ast.LitAtom a))
  | Ast.EAtom (a, args, _) ->
    lower_atoms_k args (fun arg_atoms ->
      Tir.EAlloc (Tir.TCon (a, []), arg_atoms))

  (* --- Holes --- *)
  | Ast.EHole (name, _) ->
    let label = match name with Some n -> n.txt | None -> "?" in
    Tir.EAtom (Tir.ALit (Ast.LitAtom ("hole_" ^ label)))

  (* --- Pipe should be desugared already --- *)
  | Ast.EPipe _ -> failwith "TIR lower: EPipe should have been desugared"

  | Ast.EResultRef _ -> failwith "TIR lower: EResultRef is REPL-only and should be substituted before lowering"

  | Ast.EDbg _ ->
    failwith "TIR lower: EDbg is interpreter-only and cannot be lowered to TIR"

  (* --- Send/Spawn (CPS for args) --- *)
  | Ast.ESend (cap, msg, _) ->
    lower_to_atom_k cap (fun cap' ->
      lower_to_atom_k msg (fun msg' ->
        let send_var : Tir.var = {
          v_name = "send";
          v_ty = Tir.TFn ([Tir.TPtr Tir.TUnit; Tir.TPtr Tir.TUnit],
                           Tir.TCon ("Option", [Tir.TUnit]));
          v_lin = Tir.Unr } in
        Tir.EApp (send_var, [cap'; msg'])))

  (* Actor names are upper-case identifiers, parsed as ECon with no args.
     Lower spawn(ActorName) → call to ActorName_spawn() *)
  | Ast.ESpawn (Ast.ECon ({ txt = actor_name; _ }, [], _), _)
  | Ast.ESpawn (Ast.EVar { txt = actor_name; _ }, _) ->
    let spawn_fn : Tir.var = {
      v_name = actor_name ^ "_spawn";
      v_ty = Tir.TPtr Tir.TUnit;
      v_lin = Tir.Unr
    } in
    Tir.EApp (spawn_fn, [])

  | Ast.ESpawn _ ->
    failwith "TIR lower: ESpawn argument must be a plain actor name"

  (* --- Local named recursive fn → ELetRec with a single fn_def ---
     fn go(params) : ret do body end  is like ELam but the fn knows its own name,
     enabling recursion.  Defun lifts it and computes free-variable captures. *)
  | Ast.ELetFn (name, params, ret_ty_ann, body, _) ->
    let fn_name = name.Ast.txt in
    let params' = List.map (fun (p : Ast.param) ->
        { Tir.v_name = p.param_name.txt;
          v_ty = (match p.param_ty with Some t -> lower_ty t
                  | None -> ty_of_span p.param_name.span);
          v_lin = lower_linearity p.param_lin }
      ) params in
    let body' = lower_expr body in
    let ret_ty = match ret_ty_ann with Some t -> lower_ty t | None -> ty_of_expr body in
    let fn : Tir.fn_def = {
      fn_name; fn_params = params'; fn_ret_ty = ret_ty; fn_body = body'
    } in
    let fn_var : Tir.var = {
      v_name = fn_name;
      v_ty = Tir.TFn (List.map (fun v -> v.Tir.v_ty) params', ret_ty);
      v_lin = Tir.Unr
    } in
    Tir.ELetRec ([fn], Tir.EAtom (Tir.AVar fn_var))

(* ── Match lowering ─────────────────────────────────────────────── *)

(** Lower match branches to [ECase].
    - Constructor patterns → branches with bound variables
    - Literal patterns → branches with tag = string representation
    - Wildcard/var patterns → default arm
    - PatVar default arms: wraps body in [ELet] binding the scrutinee to the variable name
    - Guards: not yet supported (failwith if encountered) *)
and lower_match (scrut : Tir.atom) (branches : Ast.branch list) : Tir.expr =
  (* Check for guards — not supported yet *)
  List.iter (fun (br : Ast.branch) ->
      match br.branch_guard with
      | Some _ -> failwith "TIR lower: match guards are not yet supported"
      | None -> ()
    ) branches;
  let tir_branches = List.filter_map (fun (br : Ast.branch) ->
      match br.branch_pat with
      | Ast.PatCon ({ txt = tag; _ }, sub_pats) ->
        let vars = List.map (fun pat ->
            let name = match pat with
              | Ast.PatVar n -> n.txt
              | Ast.PatWild _ -> fresh_name "w"
              | _ -> fresh_name "p"
            in
            { Tir.v_name = name; v_ty = unknown_ty; v_lin = Tir.Unr }
          ) sub_pats in
        Some { Tir.br_tag = tag; br_vars = vars; br_body = lower_expr br.branch_body }
      | Ast.PatLit (Ast.LitInt n, _) ->
        Some { Tir.br_tag = string_of_int n; br_vars = [];
               br_body = lower_expr br.branch_body }
      | Ast.PatLit (Ast.LitBool b, _) ->
        Some { Tir.br_tag = string_of_bool b; br_vars = [];
               br_body = lower_expr br.branch_body }
      | Ast.PatLit (Ast.LitString s, _) ->
        Some { Tir.br_tag = "\"" ^ s ^ "\""; br_vars = [];
               br_body = lower_expr br.branch_body }
      | Ast.PatLit (Ast.LitAtom a, _) ->
        Some { Tir.br_tag = ":" ^ a; br_vars = [];
               br_body = lower_expr br.branch_body }
      | _ -> None
    ) branches in
  (* Default arm: wildcard or var pattern *)
  let default = List.find_map (fun (br : Ast.branch) ->
      match br.branch_pat with
      | Ast.PatWild _ -> Some (lower_expr br.branch_body)
      | Ast.PatVar n ->
        (* Bind the scrutinee to the variable name so the body can use it *)
        let v : Tir.var = { v_name = n.txt; v_ty = unknown_ty; v_lin = Tir.Unr } in
        Some (Tir.ELet (v, Tir.EAtom scrut, lower_expr br.branch_body))
      | _ -> None
    ) branches in
  Tir.ECase (scrut, tir_branches, default)

(* ── TIR renaming ───────────────────────────────────────────────── *)

(** Rename [AVar] atoms whose [v_name] appears in [names] by prefixing with
    [prefix].  Used when lowering [DMod] inner functions to rewrite unqualified
    intra-module call sites (e.g. [from_string] → [IOList.from_string]).

    Safe because TIR ANF let-bindings use fresh names ($t42, $lam5 …) and
    module function names are conventionally distinct from local variable names
    in stdlib code. *)
let rename_tir_vars (prefix : string) (names : string list) (fn : Tir.fn_def) : Tir.fn_def =
  let rename_var (v : Tir.var) : Tir.var =
    if List.mem v.Tir.v_name names
    then { v with Tir.v_name = prefix ^ v.Tir.v_name }
    else v
  in
  let rename_atom = function
    | Tir.AVar v -> Tir.AVar (rename_var v)
    | a -> a
  in
  let rec rename_expr = function
    | Tir.EAtom a        -> Tir.EAtom (rename_atom a)
    | Tir.EApp (v, args) -> Tir.EApp (rename_var v, List.map rename_atom args)
    | Tir.ECallPtr (f, args) -> Tir.ECallPtr (rename_atom f, List.map rename_atom args)
    | Tir.ELet (v, e1, e2) -> Tir.ELet (v, rename_expr e1, rename_expr e2)
    | Tir.ELetRec (fns, body) ->
      Tir.ELetRec (List.map rename_fn fns, rename_expr body)
    | Tir.ECase (scrut, branches, def) ->
      Tir.ECase (rename_atom scrut,
                 List.map (fun br -> { br with Tir.br_body = rename_expr br.Tir.br_body }) branches,
                 Option.map rename_expr def)
    | Tir.ETuple atoms   -> Tir.ETuple (List.map rename_atom atoms)
    | Tir.ERecord fields -> Tir.ERecord (List.map (fun (k, a) -> (k, rename_atom a)) fields)
    | Tir.EField (a, f)  -> Tir.EField (rename_atom a, f)
    | Tir.EUpdate (a, fields) ->
      Tir.EUpdate (rename_atom a, List.map (fun (k, v) -> (k, rename_atom v)) fields)
    | Tir.EAlloc (ty, args)      -> Tir.EAlloc (ty, List.map rename_atom args)
    | Tir.EStackAlloc (ty, args) -> Tir.EStackAlloc (ty, List.map rename_atom args)
    | Tir.EFree a   -> Tir.EFree (rename_atom a)
    | Tir.EIncRC a  -> Tir.EIncRC (rename_atom a)
    | Tir.EDecRC a  -> Tir.EDecRC (rename_atom a)
    | Tir.EReuse (a, ty, args) -> Tir.EReuse (rename_atom a, ty, List.map rename_atom args)
    | Tir.ESeq (e1, e2) -> Tir.ESeq (rename_expr e1, rename_expr e2)
  and rename_fn (f : Tir.fn_def) : Tir.fn_def =
    { f with Tir.fn_body = rename_expr f.Tir.fn_body }
  in
  rename_fn fn

(* ── Declaration lowering ───────────────────────────────────────── *)

(** Lower a single function definition (post-desugaring: exactly 1 clause). *)
let lower_fn_def (def : Ast.fn_def) : Tir.fn_def =
  let clause = match def.fn_clauses with
    | [c] -> c
    | _ -> failwith (Printf.sprintf "TIR lower: fn %s has %d clauses (expected 1 after desugaring)"
                       def.fn_name.txt (List.length def.fn_clauses))
  in
  let params = List.map (fun fp ->
      match fp with
      | Ast.FPNamed p ->
        let ty = match p.param_ty with
          | Some t -> lower_ty t
          | None   -> ty_of_span p.param_name.span
        in
        { Tir.v_name = p.param_name.txt;
          v_ty = ty;
          v_lin = lower_linearity p.param_lin }
      | Ast.FPPat (Ast.PatVar n) ->
        { Tir.v_name = n.txt; v_ty = ty_of_span n.span; v_lin = Tir.Unr }
      | _ -> failwith "TIR lower: unexpected pattern param after desugaring"
    ) clause.fc_params in
  let ret_ty = match def.fn_ret_ty with
    | Some t -> lower_ty t
    | None -> ty_of_expr clause.fc_body
  in
  let body = lower_expr clause.fc_body in
  { fn_name = def.fn_name.txt; fn_params = params; fn_ret_ty = ret_ty; fn_body = body }

(** Lower a type definition. *)
let lower_type_def (name : Ast.name) (_params : Ast.name list) (td : Ast.type_def) : Tir.type_def option =
  match td with
  | Ast.TDVariant variants ->
    let ctors = List.map (fun (v : Ast.variant) ->
        (v.var_name.txt, List.map lower_ty v.var_args)
      ) variants in
    Some (Tir.TDVariant (name.txt, ctors))
  | Ast.TDRecord fields ->
    let fs = List.map (fun (f : Ast.field) ->
        (f.fld_name.txt, lower_ty f.fld_ty)
      ) fields in
    Some (Tir.TDRecord (name.txt, fs))
  | Ast.TDAlias _ -> None

(* ── Actor lowering ─────────────────────────────────────────────── *)

(** Lower an actor declaration to TIR type defs + function defs.

    For actor [Name] with state fields [f1:T1, ..., fn:Tn] (alphabetical) and
    handlers [on H1(p...) body1, ...], we generate:

    Types:
      TDVariant("Name_Msg", [(H1, param_tys_1); ...])    -- in handler decl order
      TDRecord ("Name_Actor", [("$dispatch",TPtr TUnit);
                               ("$alive",TBool); f1:T1; ...fn:Tn])
                                                          -- $dispatch first, $alive second,
                                                          -- then state fields alphabetically

    Functions:
      Name_Hi(actor:ptr, p...) → Unit   -- one per handler
      Name_dispatch(actor:ptr, msg:ptr) → Unit
      Name_spawn() → ptr
*)
let lower_actor (name : string) (actor : Ast.actor_def) : Tir.type_def list * Tir.fn_def list =
  (* State fields sorted alphabetically (matches TRecord ordering) *)
  let state_fields_sorted : (string * Tir.ty) list =
    List.sort (fun (a, _) (b, _) -> String.compare a b)
      (List.map (fun (f : Ast.field) -> (f.fld_name.txt, lower_ty f.fld_ty))
         actor.actor_state)
  in

  (* ── 1. Message variant type ─────────────────────────────── *)
  let msg_type_name = name ^ "_Msg" in
  let msg_ctors : (string * Tir.ty list) list =
    List.map (fun (h : Ast.actor_handler) ->
        let param_tys = List.map (fun (p : Ast.param) ->
            match p.param_ty with Some t -> lower_ty t | None -> unknown_ty
          ) h.ah_params in
        (h.ah_msg.txt, param_tys)
      ) actor.actor_handlers
  in
  let msg_variant = Tir.TDVariant (msg_type_name, msg_ctors) in

  (* ── 2. Actor struct type ────────────────────────────────── *)
  let actor_type_name = name ^ "_Actor" in
  (* Layout order: $dispatch (field 0), $alive (field 1), state fields (fields 2+) *)
  let actor_struct_fields : (string * Tir.ty) list =
    [("$dispatch", Tir.TPtr Tir.TUnit); ("$alive", Tir.TBool)]
    @ state_fields_sorted
  in
  let actor_record = Tir.TDRecord (actor_type_name, actor_struct_fields) in

  (* ── 3. Handler functions ────────────────────────────────── *)
  (* For handler "Hi" with params [(p1,T1);...]:
       fn Name_Hi(actor: ptr, p1:T1, ...) : Unit =
         let $sf1 = EField(actor, "sf1")    -- load each state field
         ...
         let state = ERecord [(sf1, $sf1); ...]
         let $result = <body>
         let $nf1 = EField($result, "sf1")  -- extract new state fields
         ...
         ESeq(EReuse(actor, Name_Actor, [$dispatch, $alive, $nf1, ...]), EAtom(unit))
  *)
  let actor_var (n : string) (ty : Tir.ty) : Tir.var =
    { Tir.v_name = n; v_ty = ty; v_lin = Tir.Unr }
  in
  (* Using TCon(actor_type_name) (not TPtr TUnit) so that EField accesses on
     the actor pointer resolve field indices correctly via field_map lookups.
     All TCon → ptr in llvm_ty, so the LLVM function signatures are unaffected. *)
  let actor_param = actor_var "$actor" (Tir.TCon (actor_type_name, [])) in
  let actor_atom  = Tir.AVar actor_param in

  let lower_handler (h : Ast.actor_handler) : Tir.fn_def =
    let fn_name = name ^ "_" ^ h.ah_msg.txt in

    (* Handler params (after the implicit $actor) *)
    let params : Tir.var list =
      actor_param ::
      List.map (fun (p : Ast.param) ->
          { Tir.v_name = p.param_name.txt;
            v_ty = (match p.param_ty with Some t -> lower_ty t | None -> unknown_ty);
            v_lin = Tir.Unr }
        ) h.ah_params
    in

    (* Load each state field from actor struct and let-bind it.
       Build the continuation bottom-up: first build inner body, wrap in lets. *)

    (* Step 1: lower the handler body (uses `state` variable) *)
    let body_tir = lower_expr h.ah_body in

    let state_ty = Tir.TCon (name ^ "_State", []) in
    (* Step 2: let $result = body_tir *)
    let result_var = actor_var "$result" state_ty in

    (* Step 3: load new state fields from $result *)
    let new_field_vars : (string * Tir.var) list =
      List.map (fun (fname, fty) ->
          let v = actor_var ("$nf_" ^ fname) fty in
          (fname, v)
        ) state_fields_sorted
    in

    (* Step 4: build EReuse args: $dispatch, $alive, then new state fields *)
    let dispatch_var = actor_var "$dispatch_v" (Tir.TPtr Tir.TUnit) in
    let alive_var    = actor_var "$alive_v" Tir.TBool in

    (* Build the innermost expression: ESeq(EReuse(...), unit) *)
    let reuse_args : Tir.atom list =
      [Tir.AVar dispatch_var; Tir.AVar alive_var]
      @ List.map (fun (_, v) -> Tir.AVar v) new_field_vars
    in
    let reuse_expr =
      Tir.ESeq (
        Tir.EReuse (actor_atom, Tir.TCon (actor_type_name, []), reuse_args),
        Tir.EAtom (Tir.ALit (Ast.LitAtom "unit"))
      )
    in

    (* Wrap: let $nf_fi = EField($result, fi) for each state field *)
    let inner_with_new_fields =
      List.fold_right (fun (fname, nfv) acc ->
          Tir.ELet (nfv, Tir.EField (Tir.AVar result_var, fname), acc)
        ) new_field_vars reuse_expr
    in

    (* Wrap: let $result = body *)
    let inner_with_result =
      Tir.ELet (result_var, body_tir, inner_with_new_fields)
    in

    (* Wrap: let state = ERecord [(fname, AVar load_var); ...] *)
    let state_field_vars : (string * Tir.var) list =
      List.map (fun (fname, fty) ->
          (fname, actor_var ("$sf_" ^ fname) fty)
        ) state_fields_sorted
    in
    let state_record_fields : (string * Tir.atom) list =
      List.map (fun (fname, v) -> (fname, Tir.AVar v)) state_field_vars
    in
    let state_var = actor_var "state" state_ty in
    let inner_with_state =
      Tir.ELet (state_var, Tir.ERecord state_record_fields, inner_with_result)
    in

    (* Wrap: let $sf_fi = EField(actor, fi) for each state field *)
    let inner_with_state_loads =
      List.fold_right (fun (fname, sfv) acc ->
          Tir.ELet (sfv, Tir.EField (actor_atom, fname), acc)
        ) state_field_vars inner_with_state
    in

    (* Wrap: let $alive_v = EField(actor, "$alive") *)
    let inner_with_alive =
      Tir.ELet (alive_var, Tir.EField (actor_atom, "$alive"), inner_with_state_loads)
    in

    (* Wrap: let $dispatch_v = EField(actor, "$dispatch") *)
    let full_body =
      Tir.ELet (dispatch_var, Tir.EField (actor_atom, "$dispatch"), inner_with_alive)
    in

    { Tir.fn_name; fn_params = params; fn_ret_ty = Tir.TUnit; fn_body = full_body }
  in

  let handler_fns = List.map lower_handler actor.actor_handlers in

  (* ── 4. Dispatch function ────────────────────────────────── *)
  (* fn Name_dispatch(actor:ptr, msg:ptr) : Unit =
       ECase(AVar msg_as_msg_type, [
         {br_tag=H1; br_vars=[p1,...]; br_body=EApp(Name_H1, [actor, p1,...])};
         ...
       ], None)
  *)
  let msg_var = actor_var "$msg" (Tir.TCon (msg_type_name, [])) in
  let dispatch_branches : Tir.branch list =
    List.map (fun (h : Ast.actor_handler) ->
        (* Prefix each branch variable with the handler name to avoid name collisions
           when multiple handlers have parameters with the same name (e.g. both
           Increment(n) and Decrement(n) would otherwise both define %n.addr). *)
        let br_vars : Tir.var list =
          List.map (fun (p : Ast.param) ->
              { Tir.v_name = "$" ^ h.ah_msg.txt ^ "_" ^ p.param_name.txt;
                v_ty = (match p.param_ty with Some t -> lower_ty t | None -> unknown_ty);
                v_lin = Tir.Unr }
            ) h.ah_params
        in
        let handler_fn_var : Tir.var = {
          v_name = name ^ "_" ^ h.ah_msg.txt;
          v_ty = Tir.TFn (
            [Tir.TPtr Tir.TUnit] @ List.map (fun v -> v.Tir.v_ty) br_vars,
            Tir.TUnit);
          v_lin = Tir.Unr
        } in
        let call_args : Tir.atom list =
          actor_atom :: List.map (fun v -> Tir.AVar v) br_vars
        in
        { Tir.br_tag = h.ah_msg.txt;
          br_vars;
          br_body = Tir.EApp (handler_fn_var, call_args) }
      ) actor.actor_handlers
  in
  let dispatch_fn : Tir.fn_def = {
    fn_name   = name ^ "_dispatch";
    fn_params = [actor_param; msg_var];
    fn_ret_ty = Tir.TUnit;
    fn_body   = Tir.ECase (Tir.AVar msg_var, dispatch_branches, None);
  } in

  (* ── 5. Spawn function ───────────────────────────────────── *)
  (* fn Name_spawn() : ptr =
       let $init_state = <lowered init expr>
       let $sf1 = EField($init_state, "sf1")
       ...
       let $actor = EAlloc(Name_Actor, [AVar dispatch_fn_ptr, true, $sf1, ...])
       EAtom($actor)
  *)
  let dispatch_fn_ptr_var : Tir.var = {
    v_name = name ^ "_dispatch";
    v_ty   = Tir.TFn ([Tir.TPtr Tir.TUnit; Tir.TPtr Tir.TUnit], Tir.TUnit);
    v_lin  = Tir.Unr;
  } in
  let state_ty = Tir.TCon (name ^ "_State", []) in
  let init_var = actor_var "$init_state" state_ty in
  let init_field_vars : (string * Tir.var) list =
    List.map (fun (fname, fty) ->
        (fname, actor_var ("$init_" ^ fname) fty)
      ) state_fields_sorted
  in
  let alloc_args : Tir.atom list =
    [Tir.AVar dispatch_fn_ptr_var; Tir.ALit (Ast.LitBool true)]
    @ List.map (fun (_, v) -> Tir.AVar v) init_field_vars
  in
  let alloc_expr = Tir.EAlloc (Tir.TCon (actor_type_name, []), alloc_args) in
  let actor_result_var = actor_var "$spawned" (Tir.TPtr Tir.TUnit) in
  let spawn_inner =
    Tir.ELet (actor_result_var, alloc_expr, Tir.EAtom (Tir.AVar actor_result_var))
  in
  let spawn_with_fields =
    List.fold_right (fun (fname, ifv) acc ->
        Tir.ELet (ifv, Tir.EField (Tir.AVar init_var, fname), acc)
      ) init_field_vars spawn_inner
  in
  let spawn_body =
    Tir.ELet (init_var, lower_expr actor.actor_init, spawn_with_fields)
  in
  let spawn_fn : Tir.fn_def = {
    fn_name   = name ^ "_spawn";
    fn_params = [];
    fn_ret_ty = Tir.TPtr Tir.TUnit;
    fn_body   = spawn_body;
  } in

  (* Also register a state record type so EField accesses on the init state
     record resolve the correct field indices (needed when there are multiple
     state fields). *)
  let state_record = Tir.TDRecord (name ^ "_State", state_fields_sorted) in

  let type_defs = [state_record; msg_variant; actor_record] in
  let fn_defs   = handler_fns @ [dispatch_fn; spawn_fn] in
  (type_defs, fn_defs)

(** Built-in type definitions that must always be present in TIR so that
    their constructors have stable tag assignments in the LLVM emitter.
    These mirror the built-in constructor table in the typechecker. *)
let builtin_type_defs : Tir.type_def list = [
  (* Option a = None | Some(a) — None=tag0, Some=tag1 *)
  Tir.TDVariant ("Option", [("None", []); ("Some", [Tir.TVar "a"])]);
  (* Result a b = Ok(a) | Err(b) — Ok=tag0, Err=tag1 *)
  Tir.TDVariant ("Result", [("Ok", [Tir.TVar "a"]); ("Err", [Tir.TVar "b"])]);
  (* List a = Nil | Cons(a, List(a)) — Nil=tag0, Cons=tag1 *)
  Tir.TDVariant ("List", [("Nil", []); ("Cons", [Tir.TVar "a"; Tir.TCon ("List", [Tir.TVar "a"])])]);
]

(** Lower a module. *)
let lower_module ?type_map (m : Ast.module_) : Tir.tir_module =
  reset_counter ();
  _type_map_ref := type_map;
  let fns = ref [] in
  let types = ref [] in
  List.iter (fun d ->
      match d with
      | Ast.DFn (def, _) ->
        fns := lower_fn_def def :: !fns
      | Ast.DType (name, params, td, _) ->
        (match lower_type_def name params td with
         | Some td' -> types := td' :: !types
         | None -> ())
      | Ast.DLet _ -> ()
      | Ast.DActor (name, actor_def, _) ->
        let (new_types, new_fns) = lower_actor name.txt actor_def in
        types := List.rev_append new_types !types;
        fns   := List.rev_append new_fns   !fns
      | Ast.DMod (mod_name, _, inner_decls, _) ->
        (* Lower inner DFn/DType declarations, prefixing function names with
           "ModName." to produce the qualified names that call sites use.
           Intra-module calls are lowered with unqualified names (typecheck
           needs them that way), so after lowering we rename AVar references
           that match inner function names to their qualified form. *)
        let prefix = mod_name.txt ^ "." in
        let inner_fn_names = List.filter_map (function
            | Ast.DFn (def, _) -> Some def.fn_name.txt
            | _ -> None) inner_decls in
        List.iter (fun d ->
            match d with
            | Ast.DFn (def, _) ->
              let fn = lower_fn_def def in
              let fn = rename_tir_vars prefix inner_fn_names fn in
              fns := { fn with fn_name = prefix ^ fn.fn_name } :: !fns
            | Ast.DType (tname, params, td, _) ->
              (match lower_type_def tname params td with
               | Some td' -> types := td' :: !types
               | None -> ())
            | _ -> ()
          ) inner_decls
      | Ast.DProtocol _ | Ast.DSig _ | Ast.DInterface _
      | Ast.DImpl _ | Ast.DExtern _ | Ast.DUse _ | Ast.DNeeds _ -> ()
    ) m.mod_decls;
  let result : Tir.tir_module = { tm_name = m.mod_name.txt;
    tm_fns = List.rev !fns;
    tm_types = builtin_type_defs @ List.rev !types } in
  _type_map_ref := None;
  result
