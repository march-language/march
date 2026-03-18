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
  | Ast.EVar { txt = name; _ } ->
    k (Tir.AVar { v_name = name; v_ty = unknown_ty; v_lin = Tir.Unr })
  | _ ->
    let rhs = lower_expr e in
    let v = fresh_var unknown_ty in
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

  | Ast.EVar { txt = name; _ } ->
    Tir.EAtom (Tir.AVar { v_name = name; v_ty = unknown_ty; v_lin = Tir.Unr })

  (* --- Let bindings --- *)
  | Ast.ELet (b, _) ->
    lower_expr b.bind_expr

  (* --- Blocks → right-nested ELet --- *)
  | Ast.EBlock ([], _) -> Tir.EAtom (Tir.ALit (Ast.LitAtom "unit"))
  | Ast.EBlock ([e], _) -> lower_expr e
  | Ast.EBlock (Ast.ELet (b, _) :: rest, sp) ->
    let rhs = lower_expr b.bind_expr in
    let bind_name = match b.bind_pat with
      | Ast.PatVar n -> n.txt
      | _ -> fresh_name "p"
    in
    let v : Tir.var = {
      v_name = bind_name;
      v_ty = (match b.bind_ty with Some t -> lower_ty t | None -> unknown_ty);
      v_lin = lower_linearity b.bind_lin;
    } in
    let body = lower_expr (Ast.EBlock (rest, sp)) in
    Tir.ELet (v, rhs, body)
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
  | Ast.ELam (params, body, _) ->
    let fn_name = fresh_name "lam" in
    let params' = List.map (fun (p : Ast.param) ->
        { Tir.v_name = p.param_name.txt;
          v_ty = (match p.param_ty with Some t -> lower_ty t | None -> unknown_ty);
          v_lin = lower_linearity p.param_lin }
      ) params in
    let body' = lower_expr body in
    let ret_ty = unknown_ty in
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

  (* --- Send/Spawn (CPS for args) --- *)
  | Ast.ESend (cap, msg, _) ->
    lower_to_atom_k cap (fun cap' ->
      lower_to_atom_k msg (fun msg' ->
        let send_var : Tir.var = { v_name = "send"; v_ty = unknown_ty; v_lin = Tir.Unr } in
        Tir.EApp (send_var, [cap'; msg'])))

  | Ast.ESpawn (actor, _) ->
    lower_to_atom_k actor (fun actor' ->
      let spawn_var : Tir.var = { v_name = "spawn"; v_ty = unknown_ty; v_lin = Tir.Unr } in
      Tir.EApp (spawn_var, [actor']))

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
        { Tir.v_name = p.param_name.txt;
          v_ty = (match p.param_ty with Some t -> lower_ty t | None -> unknown_ty);
          v_lin = lower_linearity p.param_lin }
      | Ast.FPPat (Ast.PatVar n) ->
        { Tir.v_name = n.txt; v_ty = unknown_ty; v_lin = Tir.Unr }
      | _ -> failwith "TIR lower: unexpected pattern param after desugaring"
    ) clause.fc_params in
  let ret_ty = match def.fn_ret_ty with
    | Some t -> lower_ty t
    | None -> unknown_ty
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

(** Lower a module. *)
let lower_module (m : Ast.module_) : Tir.tir_module =
  reset_counter ();
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
      | Ast.DActor _ -> ()
      | Ast.DMod _ | Ast.DProtocol _ | Ast.DSig _ | Ast.DInterface _
      | Ast.DImpl _ | Ast.DExtern _ -> ()
    ) m.mod_decls;
  { tm_name = m.mod_name.txt;
    tm_fns = List.rev !fns;
    tm_types = List.rev !types }
