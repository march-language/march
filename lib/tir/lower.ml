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
  | Ast.TyChan _                          -> Tir.TCon ("Chan", [])   (* lowered to opaque Chan ptr *)

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
  | Typecheck.TChan _         -> Tir.TCon ("Chan", [])  (* lowered to opaque Chan ptr *)
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

(* ── Use import resolution ───────────────────────────────────────── *)

(** Maps unqualified names to their qualified module-prefixed names.
    Built from [DUse] declarations. E.g. [map] → [List.map]. *)
let _use_aliases : (string, string) Hashtbl.t ref = ref (Hashtbl.create 0)

(** Resolve a variable name through use-import aliases. *)
let resolve_use_alias (name : string) : string =
  match Hashtbl.find_opt !_use_aliases name with
  | Some qualified -> qualified
  | None -> name

(* ── Qualified module lowering (refs) ──────────────────────────── *)

(** Module-level refs for function and type accumulators, set by [lower_module].
    Needed so [ensure_module_lowered] can append stdlib module definitions. *)
let _fns_ref : Tir.fn_def list ref ref = ref (ref [])
let _types_ref : Tir.type_def list ref ref = ref (ref [])

(** Tracks which modules have already been lowered to avoid duplicates. *)
let _lowered_modules : (string, unit) Hashtbl.t ref = ref (Hashtbl.create 8)

(** Forward ref — filled after [lower_fn_def] / [lower_type_def] are defined. *)
let _ensure_module_lowered : (string -> unit) ref = ref (fun _ -> ())

(* ── Interface method resolution ────────────────────────────────── *)

(** Maps interface method names to a list of (concrete_type_name, mangled_fn_name).
    Used during lowering to rewrite calls like [show(42)] → [Show$Int.show(42)]. *)
let _iface_methods : (string, (string * string) list) Hashtbl.t ref
  = ref (Hashtbl.create 0)

(** Resolve an interface method call if possible.
    Given a method name and the inferred type of the first argument,
    returns the mangled impl function name, or None. *)
let resolve_iface_method (method_name : string) (arg_span : Ast.span) : string option =
  match Hashtbl.find_opt !_iface_methods method_name with
  | None -> None
  | Some impls ->
    match !_type_map_ref with
    | None -> None
    | Some tbl ->
      match Hashtbl.find_opt tbl arg_span with
      | None -> None
      | Some tc_ty ->
        let tc_ty = Typecheck.repr tc_ty in
        (* Extract the concrete type name from the typechecker type *)
        let type_name = match tc_ty with
          | Typecheck.TCon (name, _) -> Some name
          | Typecheck.TTuple _       -> Some "$Tuple"
          | Typecheck.TRecord _      -> Some "$Record"
          | _ -> None
        in
        match type_name with
        | None -> None
        | Some tname ->
          List.assoc_opt tname impls

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
    let name = resolve_use_alias name in
    (match String.index_opt name '.' with
     | Some i -> !_ensure_module_lowered (String.sub name 0 i)
     | None -> ());
    let ty = ty_of_span span in
    k (Tir.AVar { v_name = name; v_ty = ty; v_lin = Tir.Unr })
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
    let name = resolve_use_alias name in
    (match String.index_opt name '.' with
     | Some i -> !_ensure_module_lowered (String.sub name 0 i)
     | None -> ());
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

  (* --- match do cond_arm* end → nested ECase on bools --- *)
  | Ast.ECond (arms, _) ->
    let panic_var : Tir.var = {
      Tir.v_name = "panic"; Tir.v_ty = Tir.TCon ("Never", []); Tir.v_lin = Tir.Unr } in
    let no_match = Tir.EApp (panic_var, [Tir.ALit (Ast.LitString "non-exhaustive match do")]) in
    let rec lower_cond = function
      | [] -> no_match
      | (cond_e, body_e) :: rest ->
        lower_to_atom_k cond_e (fun cond_atom ->
          let body' = lower_expr body_e in
          let rest' = lower_cond rest in
          Tir.ECase (cond_atom,
            [{ br_tag = "True"; br_vars = []; br_body = body' }],
            Some rest'))
    in
    lower_cond arms

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
    (* Check for interface method resolution: if f is a plain EVar that
       names an interface method, and we can determine the concrete type
       of the first argument, redirect to the mangled impl function. *)
    let resolved_f = match f_expr, args with
      | Ast.EVar { txt = name; _ }, first_arg :: _ ->
        (match resolve_iface_method name (Typecheck.span_of_expr first_arg) with
         | Some mangled_name -> Ast.EVar { txt = mangled_name;
             span = Typecheck.span_of_expr f_expr }
         | None -> f_expr)
      | _ -> f_expr
    in
    lower_to_atom_k resolved_f (fun f_atom ->
      lower_atoms_k args (fun arg_atoms ->
        let f_var = match f_atom with
          | Tir.AVar v -> v
          | Tir.ADefRef did ->
            { v_name = did.Tir.did_name; v_ty = unknown_ty; v_lin = Tir.Unr }
          | Tir.ALit _ ->
            { v_name = "<lit>"; v_ty = unknown_ty; v_lin = Tir.Unr }
        in
        (* Special case: own(pid, value) → register_resource + drop closure.
           Transforms own(pid, value : TypeName) into:
             let $own_dropN = fn _ -> Drop$TypeName.drop(value) in
             register_resource(pid, "drop_TypeName", $own_dropN)
           This keeps the Drop impl alive through the mono pass and wires
           the cleanup callback into the actor's kill/crash path. *)
        if f_var.v_name = "own" && List.length arg_atoms = 2 then
          let pid_atom   = List.nth arg_atoms 0 in
          let value_atom = List.nth arg_atoms 1 in
          let value_ty = match value_atom with
            | Tir.AVar v -> v.Tir.v_ty
            | _ -> Tir.TVar "_"
          in
          let type_name = match value_ty with
            | Tir.TCon (n, _) -> n
            | _ -> ""
          in
          if type_name = "" then Tir.EApp (f_var, arg_atoms)
          else
            let drop_fn_name = Printf.sprintf "Drop$%s.drop" type_name in
            let lam_name     = fresh_name "own_drop" in
            let drop_var  = { Tir.v_name = drop_fn_name;
                              v_ty = Tir.TFn ([value_ty], Tir.TUnit);
                              v_lin = Tir.Unr } in
            let dummy_param = { Tir.v_name = "$_"; v_ty = Tir.TUnit; v_lin = Tir.Unr } in
            let drop_body   = Tir.EApp (drop_var, [value_atom]) in
            let lam_fn : Tir.fn_def = {
              fn_name   = lam_name;
              fn_params = [dummy_param];
              fn_ret_ty = Tir.TUnit;
              fn_body   = drop_body;
            } in
            let lam_ty  = Tir.TFn ([Tir.TUnit], Tir.TUnit) in
            let lam_var = { Tir.v_name = lam_name; v_ty = lam_ty; v_lin = Tir.Unr } in
            (* Bind the closure to a fresh variable so defun can see the
               canonical ELetRec([fn], EAtom(AVar fn)) → closure alloc pattern. *)
            let clo_var = fresh_var lam_ty in
            let name_atom = Tir.ALit (March_ast.Ast.LitString ("drop_" ^ type_name)) in
            let reg_var   = { Tir.v_name = "register_resource";
                              v_ty = Tir.TFn ([Tir.TVar "_"; Tir.TString; lam_ty], Tir.TUnit);
                              v_lin = Tir.Unr } in
            Tir.ELet (clo_var,
              Tir.ELetRec ([lam_fn], Tir.EAtom (Tir.AVar lam_var)),
              Tir.EApp (reg_var, [pid_atom; name_atom; Tir.AVar clo_var]))
        else
          Tir.EApp (f_var, arg_atoms)))

  (* --- Constructor application (CPS for args) --- *)
  (* Embed the parent type name in the TCon key so that different ADTs with
     the same constructor name (e.g. List.Cons vs Tree.Cons) produce distinct
     keys in the emitter's ctor_info table.  The span carries the inferred
     result type from the typechecker; when it is TCon(type_name, _) we use
     "type_name.ctor_name" as the key, otherwise fall back to the bare name. *)
  | Ast.ECon ({ txt = tag; _ }, args, span) ->
    lower_atoms_k args (fun arg_atoms ->
      let ctor_key = match ty_of_span span with
        | Tir.TCon (type_name, _) -> type_name ^ "." ^ tag
        | _ -> tag
      in
      Tir.EAlloc (Tir.TCon (ctor_key, []), arg_atoms))

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
    (* Try to get the return type from the lambda body's span first.
       When that span isn't in the type_map (e.g. desugared lambdas passed to
       builtins), fall back to the lambda's own inferred type (lam_ty) which
       the typechecker does annotate.  Without this fallback a lambda such as
         fn conn -> run_pipeline(conn, plugs)
       would get fn_ret_ty = TVar "_" → void LLVM return → result silently
       dropped → NULL returned to the caller. *)
    let ret_ty =
      let from_body = ty_of_expr body in
      match from_body with
      | Tir.TVar "_" ->
        (match lam_ty with
         | Tir.TFn (_, r) -> r
         | _ -> from_body)
      | _ -> from_body
    in
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

  | Ast.EDbg (None, _) ->
    (* dbg() with no argument: compile to unit in compiled mode *)
    Tir.EAtom (Tir.ALit (Ast.LitAtom "unit"))
  | Ast.EDbg (Some inner, _) ->
    (* dbg(expr): compile to just the expression (strip the debug wrapper) *)
    lower_expr inner

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
    let march_spawn : Tir.var = {
      v_name = "spawn";
      v_ty = Tir.TPtr Tir.TUnit;
      v_lin = Tir.Unr
    } in
    let raw_var : Tir.var = {
      v_name = "$raw_actor";
      v_ty = Tir.TPtr Tir.TUnit;
      v_lin = Tir.Unr
    } in
    Tir.ELet (raw_var, Tir.EApp (spawn_fn, []),
              Tir.EApp (march_spawn, [Tir.AVar raw_var]))

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

  (* --- Assert: lower to a runtime panic call on failure (for compiled path) --- *)
  | Ast.EAssert (inner, _) ->
    (* Lower assert to: if inner then () else panic("assertion failed")
       Uses same CPS-based bool dispatch as EIf. *)
    lower_to_atom_k inner (fun cond_atom ->
      let unit_v = Tir.EAtom (Tir.ALit (Ast.LitAtom "unit")) in
      let panic_var : Tir.var = {
        v_name = "panic";
        v_ty = Tir.TFn ([Tir.TCon ("String", [])], Tir.TCon ("Unit", []));
        v_lin = Tir.Unr
      } in
      let panic_v = Tir.EApp (panic_var, [Tir.ALit (Ast.LitString "assertion failed")]) in
      Tir.ECase (cond_atom,
        [{ br_tag = "True"; br_vars = []; br_body = unit_v }],
        Some panic_v))

  | Ast.ESigil _ ->
    failwith "lower_expr: ESigil should be desugared before lowering"

(* ── Match lowering ─────────────────────────────────────────────── *)

(** True if [pat] matches everything without discriminating (wildcard / var / as-var). *)
and is_trivial_pat : Ast.pattern -> bool = function
  | Ast.PatWild _ | Ast.PatVar _ -> true
  | Ast.PatAs (p, _, _) -> is_trivial_pat p
  | _ -> false

(** Wrap [body] with bindings from a trivial pattern on [scrut].
    Handles PatVar (bind), PatWild (no-op), PatAs (bind outer name + recurse). *)
and bind_trivial_pat (scrut : Tir.atom) (pat : Ast.pattern) (body : Tir.expr) : Tir.expr =
  match pat with
  | Ast.PatWild _ -> body
  | Ast.PatVar n ->
    let v : Tir.var = { v_name = n.txt; v_ty = unknown_ty; v_lin = Tir.Unr } in
    Tir.ELet (v, Tir.EAtom scrut, body)
  | Ast.PatAs (inner, n, _) ->
    let v : Tir.var = { v_name = n.txt; v_ty = unknown_ty; v_lin = Tir.Unr } in
    let named_body = Tir.ELet (v, Tir.EAtom scrut, body) in
    bind_trivial_pat scrut inner named_body
  | _ -> body

(** Return the string tag and sub-pattern list for a pattern that discriminates.
    PatCon → (tag, subs); PatTuple → ("$Tuple", subs); PatLit → (repr, []).
    Returns None for trivial patterns. *)
and pat_tag_and_subs (pat : Ast.pattern) : (string * Ast.pattern list) option =
  match pat with
  | Ast.PatCon ({ txt = tag; _ }, subs) -> Some (tag, subs)
  | Ast.PatTuple (subs, _) ->
    Some (Printf.sprintf "$Tuple%d" (List.length subs), subs)
  | Ast.PatLit (Ast.LitInt n, _)    -> Some (string_of_int n, [])
  | Ast.PatLit (Ast.LitBool b, _)   -> Some (string_of_bool b, [])
  | Ast.PatLit (Ast.LitString s, _) -> Some ("\"" ^ s ^ "\"", [])
  | Ast.PatLit (Ast.LitAtom a, _)   -> Some (":" ^ a, [])
  | _ -> None

(** Compile a pattern matrix to a TIR expression (decision tree).

    [scruts]   — list of TIR atoms currently under scrutiny (one per column).
    [rows]     — list of (pattern list, body): each pattern list has exactly
                 one element per scrutinee.  Rows are tried top-to-bottom; the
                 first matching row wins.
    [fallback] — optional expression used when no row matches (non-exhaustive). *)
and compile_matrix
    (scruts   : Tir.atom list)
    (rows     : (Ast.pattern list * Tir.expr) list)
    (fallback : Tir.expr option)
  : Tir.expr =
  match rows with
  | [] ->
    (match fallback with Some f -> f | None -> Tir.EAtom (Tir.ALit (Ast.LitInt 0)))
  | ([], body) :: _ -> body   (* zero scrutinees remaining → first row wins *)
  | _ ->
    match scruts with
    | [] ->
      (match rows with (_, body) :: _ -> body | [] ->
        (match fallback with Some f -> f | None -> Tir.EAtom (Tir.ALit (Ast.LitInt 0))))
    | scrut :: rest_scruts ->
      (* Split rows into a front block of non-trivial first-column rows and
         a (possibly empty) suffix starting at the first trivial first-column
         row.  The suffix becomes the default for all ECase branches. *)
      let rec split_at_trivial acc = function
        | [] -> (List.rev acc, [])
        | ((fp :: _), _) as row :: rest ->
          if is_trivial_pat fp then (List.rev acc, row :: rest)
          else split_at_trivial (row :: acc) rest
        | rows -> (List.rev acc, rows)  (* empty pattern list — treat as trivial *)
      in
      let (ctor_rows, default_rows) = split_at_trivial [] rows in

      (* Build the fallback expression for rows at and after the first trivial row. *)
      let default =
        match default_rows with
        | [] -> fallback
        | (fp :: rest_pats, body) :: more ->
          (* Bind the trivial first-column pattern on [scrut], then continue
             matching remaining columns (rest_scruts) with remaining patterns
             (rest_pats).  Any further rows (more) become the inner fallback. *)
          let inner_fb = compile_matrix (scrut :: rest_scruts) more fallback in
          let body_with_bindings = bind_trivial_pat scrut fp body in
          (* If there are more columns, we still need to compile them.
             For the trivial row itself, the remaining columns are rest_pats
             matched against rest_scruts. *)
          let full_body =
            if rest_pats = [] || rest_scruts = [] then body_with_bindings
            else
              let inner_rows = [(rest_pats, body_with_bindings)] in
              compile_matrix rest_scruts inner_rows (Some inner_fb)
          in
          (* The full default also handles any subsequent trivial rows via inner_fb *)
          let _ = inner_fb in   (* inner_fb used above only as compile_matrix fallback *)
          Some full_body
        | ([], body) :: _ -> Some body
      in

      (* Group non-trivial ctor_rows by their first-column tag, preserving order. *)
      (* tag_groups: assoc list of (tag, (arity, rows_rev ref)) *)
      let tag_groups : (string * (int * (Ast.pattern list * Tir.expr) list ref)) list ref
          = ref [] in
      List.iter (fun (pats, body) ->
          match pats with
          | fp :: rest_pats ->
            (match pat_tag_and_subs fp with
             | None -> ()   (* trivial — should not appear here *)
             | Some (tag, subs) ->
               let arity = List.length subs in
               let row_entry = (subs @ rest_pats, body) in
               (match List.assoc_opt tag !tag_groups with
                | Some (_, rows_ref) -> rows_ref := !rows_ref @ [row_entry]
                | None ->
                  tag_groups := !tag_groups @ [(tag, (arity, ref [row_entry]))]))
          | [] -> ()
        ) ctor_rows;

      (* For each tag group, compile sub-pattern rows recursively. *)
      let tir_branches =
        List.filter_map (fun (tag, (arity, rows_ref)) ->
            let sub_vars = List.init arity (fun _ ->
                { Tir.v_name = fresh_name "f"; v_ty = unknown_ty; v_lin = Tir.Unr }
              ) in
            let sub_atoms = List.map (fun v -> Tir.AVar v) sub_vars in
            let combined_scruts = sub_atoms @ rest_scruts in
            let branch_body =
              compile_matrix combined_scruts !rows_ref default
            in
            Some { Tir.br_tag = tag; br_vars = sub_vars; br_body = branch_body }
          ) !tag_groups
      in

      (* If there are no ECase branches (all rows were trivial), the default
         already covers everything — just return it. *)
      if tir_branches = [] then
        (match default with Some d -> d | None -> Tir.EAtom (Tir.ALit (Ast.LitInt 0)))
      else
        Tir.ECase (scrut, tir_branches, default)

(** Lower a single-scrutinee match to a TIR decision tree.
    Branches with [when] guards are handled by embedding a boolean check
    in the branch body: if the guard is false, control falls through to the
    remaining branches. *)
and lower_match (scrut : Tir.atom) (branches : Ast.branch list) : Tir.expr =
  let has_guards = List.exists (fun (br : Ast.branch) ->
      br.branch_guard <> None) branches in
  if not has_guards then begin
    (* Fast path: no guards — use efficient matrix compilation. *)
    let rows = List.map (fun (br : Ast.branch) ->
        ([br.branch_pat], lower_expr br.branch_body)) branches in
    compile_matrix [scrut] rows None
  end else begin
    (* Guards present: compile each branch individually with fallthrough
       to the remaining branches when the guard fails. *)
    let rec go = function
      | [] -> Tir.EAtom (Tir.ALit (Ast.LitInt 0))  (* match failure *)
      | (br : Ast.branch) :: rest ->
        let rest_expr = go rest in
        let body = lower_expr br.branch_body in
        let guarded_body = match br.branch_guard with
          | None -> body
          | Some guard ->
            let guard_expr = lower_expr guard in
            let gv : Tir.var = { v_name = fresh_name "guard";
                                 v_ty = Tir.TBool; v_lin = Tir.Unr } in
            Tir.ELet (gv, guard_expr,
              Tir.ECase (Tir.AVar gv,
                [{ br_tag = "true"; br_vars = []; br_body = body }],
                Some rest_expr))
        in
        compile_matrix [scrut] [([br.branch_pat], guarded_body)] (Some rest_expr)
    in
    go branches
  end

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
    | Tir.EIncRC a       -> Tir.EIncRC (rename_atom a)
    | Tir.EDecRC a       -> Tir.EDecRC (rename_atom a)
    | Tir.EAtomicIncRC a -> Tir.EAtomicIncRC (rename_atom a)
    | Tir.EAtomicDecRC a -> Tir.EAtomicDecRC (rename_atom a)
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

(* ── Qualified module lowering (implementation) ───────────────── *)

(** Lower all declarations from a stdlib module's body, adding functions
    and types to the current module-level accumulator refs. *)
let rec lower_stdlib_mod_decls prefix decls =
  let direct_fn_names = List.filter_map (function
      | Ast.DFn (def, _) -> Some def.fn_name.txt
      | _ -> None) decls in
  List.iter (fun d ->
      match d with
      | Ast.DFn (def, _) ->
        let fn = lower_fn_def def in
        let fn = rename_tir_vars prefix direct_fn_names fn in
        !_fns_ref := { fn with fn_name = prefix ^ fn.fn_name } :: !(!_fns_ref)
      | Ast.DType (_, tname, params, td, _) ->
        (match lower_type_def tname params td with
         | Some td' -> !_types_ref := td' :: !(!_types_ref)
         | None -> ())
      | Ast.DMod (sub_name, _, sub_decls, _) ->
        lower_stdlib_mod_decls (prefix ^ sub_name.txt ^ ".") sub_decls
      | _ -> ()
    ) decls

let () = _ensure_module_lowered := (fun mod_name ->
  if not (Hashtbl.mem !_lowered_modules mod_name) then begin
    Hashtbl.replace !_lowered_modules mod_name ();
    match March_modules.Module_registry.find_stdlib_file mod_name with
    | None -> ()
    | Some path ->
      (try
         let ic = open_in_bin path in
         let n = in_channel_length ic in
         let b = Bytes.create n in
         really_input ic b 0 n;
         close_in ic;
         let src = Bytes.to_string b in
         let lexbuf = Lexing.from_string src in
         lexbuf.Lexing.lex_curr_p <-
           { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
         let ast = March_parser.Parser.module_
                     (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
         let ast = March_desugar.Desugar.desugar_module ast in
         lower_stdlib_mod_decls (mod_name ^ ".") ast.mod_decls
       with _ -> ())
  end)

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
  (* Mark actor param as Lin so Perceus won't add incrc for field loads.
     The actor is uniquely owned — FBIP can safely mutate it in-place. *)
  let actor_param = { Tir.v_name = "$actor";
                      v_ty = Tir.TCon (actor_type_name, []);
                      v_lin = Tir.Lin } in
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
  (* ── 5b. Supervision registration ───────────────────────────────── *)
  (* If this actor declares a supervise block, call march_register_supervisor
     from the spawn function body so the runtime knows the supervision strategy.
     Encoding: OneForOne=0, OneForAll=1, RestForOne=2. *)
  let strategy_int (s : Ast.restart_strategy) : int =
    match s with
    | Ast.OneForOne  -> 0
    | Ast.OneForAll  -> 1
    | Ast.RestForOne -> 2
  in
  let mk_reg_sup_call (spawned_atom : Tir.atom) (sc : Ast.supervise_config) : Tir.expr =
    let reg_sup_var : Tir.var = {
      v_name = "register_supervisor";
      v_ty   = Tir.TFn ([Tir.TPtr Tir.TUnit; Tir.TInt; Tir.TInt; Tir.TInt], Tir.TUnit);
      v_lin  = Tir.Unr;
    } in
    Tir.EApp (reg_sup_var, [
      spawned_atom;
      Tir.ALit (Ast.LitInt (strategy_int sc.Ast.sc_strategy));
      Tir.ALit (Ast.LitInt sc.Ast.sc_max_restarts);
      Tir.ALit (Ast.LitInt sc.Ast.sc_window_secs);
    ])
  in
  (* Wrap the spawn body: after allocating the actor, register supervision if needed. *)
  let spawn_body_with_sup =
    match actor.actor_supervise with
    | None -> Tir.ELet (init_var, lower_expr actor.actor_init, spawn_with_fields)
    | Some sc ->
      (* Replace the final EAtom($spawned) with:
           let $reg_sup_result = register_supervisor($spawned, strat, max, window) in
           EAtom($spawned)
         We thread the $spawned var through by wrapping the full body. *)
      let rec wrap_sup (e : Tir.expr) : Tir.expr =
        match e with
        | Tir.ELet (v, Tir.EAlloc (ty, args), rest) when v.Tir.v_name = "$spawned" ->
          (* After allocating, call march_spawn, then register_supervisor, then return *)
          Tir.ELet (v, Tir.EAlloc (ty, args),
            Tir.ELet ({ v_name = "$sup_reg"; v_ty = Tir.TUnit; v_lin = Tir.Unr },
              mk_reg_sup_call (Tir.AVar v) sc,
              rest))
        | Tir.ELet (v, rhs, body) -> Tir.ELet (v, rhs, wrap_sup body)
        | other -> other
      in
      Tir.ELet (init_var, lower_expr actor.actor_init, wrap_sup spawn_with_fields)
  in
  let spawn_fn : Tir.fn_def = {
    fn_name   = name ^ "_spawn";
    fn_params = [];
    fn_ret_ty = Tir.TPtr Tir.TUnit;
    fn_body   = spawn_body_with_sup;
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
  _iface_methods := Hashtbl.create 16;
  _use_aliases := Hashtbl.create 16;
  _lowered_modules := Hashtbl.create 8;
  let fns = ref [] in
  let types = ref [] in
  _fns_ref := fns;
  _types_ref := types;
  let top_lets = ref [] in
  let externs = ref [] in
  (* Pre-populate _iface_methods with standard interface builtins:
     Eq, Ord, Show, Hash for Int/Float/String/Bool/Unit.
     These mirror the builtin_impls registered in the typechecker.
     Synthetic TIR functions delegate to the corresponding built-in ops.
     Only injected when a type_map is available (full pipeline mode). *)
  if !_type_map_ref <> None then begin
  let mk_var name ty = { Tir.v_name = name; v_ty = ty; v_lin = Tir.Unr } in
  let call2 op_name x_ty y_ty ret_ty =
    (* fn(x, y) -> op(x, y) *)
    let x = mk_var "x" x_ty and y = mk_var "y" y_ty in
    { Tir.fn_name   = op_name;
      fn_params     = [x; y];
      fn_ret_ty     = ret_ty;
      fn_body       = Tir.EApp (mk_var op_name unknown_ty, [Tir.AVar x; Tir.AVar y]) }
  in
  let call1 op_name x_ty ret_ty =
    (* fn(x) -> op(x) *)
    let x = mk_var "x" x_ty in
    { Tir.fn_name   = op_name;
      fn_params     = [x];
      fn_ret_ty     = ret_ty;
      fn_body       = Tir.EApp (mk_var op_name unknown_ty, [Tir.AVar x]) }
  in
  let reg_method meth_name ty_name mangled_name =
    let existing = match Hashtbl.find_opt !_iface_methods meth_name with
      | Some l -> l | None -> [] in
    Hashtbl.replace !_iface_methods meth_name ((ty_name, mangled_name) :: existing)
  in
  let emit_builtin_fn name params ret_ty body_fn_name body_params =
    let fn : Tir.fn_def = {
      fn_name   = name;
      fn_params = params;
      fn_ret_ty = ret_ty;
      fn_body   = Tir.EApp (mk_var body_fn_name unknown_ty,
                             List.map (fun v -> Tir.AVar v) body_params);
    } in
    fns := fn :: !fns
  in
  ignore (call2 "" Tir.TInt Tir.TInt Tir.TInt);  (* suppress unused warnings *)
  ignore (call1 "" Tir.TInt Tir.TInt);
  (* Eq implementations: eq(x, y) -> x == y *)
  let eq_types = [("Int", Tir.TInt); ("Float", Tir.TFloat);
                  ("String", Tir.TString); ("Bool", Tir.TBool)] in
  List.iter (fun (ty_name, tir_ty) ->
      let mangled = Printf.sprintf "Eq$%s.eq" ty_name in
      let x = mk_var "x" tir_ty and y = mk_var "y" tir_ty in
      let fn : Tir.fn_def = {
        fn_name = mangled; fn_params = [x; y]; fn_ret_ty = Tir.TBool;
        fn_body = Tir.EApp (mk_var "==" unknown_ty, [Tir.AVar x; Tir.AVar y]);
      } in
      fns := fn :: !fns;
      reg_method "eq" ty_name mangled
    ) eq_types;
  (* Ord implementations: compare(x, y) — delegate to typed C runtime builtins *)
  let ord_specs = [
    ("Int",    Tir.TInt,    "march_compare_int");
    ("Float",  Tir.TFloat,  "march_compare_float");
    ("String", Tir.TString, "march_compare_string");
  ] in
  List.iter (fun (ty_name, tir_ty, c_fn) ->
      let mangled = Printf.sprintf "Ord$%s.compare" ty_name in
      let x = mk_var "x" tir_ty and y = mk_var "y" tir_ty in
      let fn : Tir.fn_def = {
        fn_name = mangled; fn_params = [x; y]; fn_ret_ty = Tir.TInt;
        fn_body = Tir.EApp (mk_var c_fn unknown_ty, [Tir.AVar x; Tir.AVar y]);
      } in
      fns := fn :: !fns;
      reg_method "compare" ty_name mangled
    ) ord_specs;
  (* Show implementations: show(x) -> type_specific_to_string(x) *)
  let show_specs = [
    ("Int",    Tir.TInt,    "int_to_string");
    ("Float",  Tir.TFloat,  "float_to_string");
    ("Bool",   Tir.TBool,   "bool_to_string");
  ] in
  List.iter (fun (ty_name, tir_ty, to_str_fn) ->
      let mangled = Printf.sprintf "Show$%s.show" ty_name in
      emit_builtin_fn mangled [mk_var "x" tir_ty] Tir.TString to_str_fn
        [mk_var "x" tir_ty];
      reg_method "show" ty_name mangled
    ) show_specs;
  (* Show$String.show: identity — the string is already its own representation *)
  let str_x = mk_var "x" Tir.TString in
  let show_str_fn : Tir.fn_def = {
    fn_name = "Show$String.show"; fn_params = [str_x];
    fn_ret_ty = Tir.TString;
    fn_body = Tir.EAtom (Tir.AVar str_x);
  } in
  fns := show_str_fn :: !fns;
  reg_method "show" "String" "Show$String.show";
  (* Hash implementations: hash(x) — delegate to typed C runtime builtins *)
  let hash_specs = [
    ("Int",    Tir.TInt,    "march_hash_int");
    ("Float",  Tir.TFloat,  "march_hash_float");
    ("String", Tir.TString, "march_hash_string");
    ("Bool",   Tir.TBool,   "march_hash_bool");
  ] in
  List.iter (fun (ty_name, tir_ty, c_fn) ->
      let mangled = Printf.sprintf "Hash$%s.hash" ty_name in
      let x = mk_var "x" tir_ty in
      let fn : Tir.fn_def = {
        fn_name = mangled; fn_params = [x]; fn_ret_ty = Tir.TInt;
        fn_body = Tir.EApp (mk_var c_fn unknown_ty, [Tir.AVar x]);
      } in
      fns := fn :: !fns;
      reg_method "hash" ty_name mangled
    ) hash_specs;
  end; (* end of builtin iface injection *)
  (* Pass 1: Collect interface/impl declarations first so that interface
     method resolution is available when lowering function bodies. *)
  List.iter (fun d ->
      match d with
      | Ast.DInterface (idef, _) ->
        List.iter (fun (m : Ast.method_decl) ->
            if not (Hashtbl.mem !_iface_methods m.md_name.txt) then
              Hashtbl.replace !_iface_methods m.md_name.txt []
          ) idef.iface_methods
      | Ast.DImpl (idef, _) ->
        let type_name = match idef.impl_ty with
          | Ast.TyCon ({ txt = name; _ }, _) -> name
          | Ast.TyTuple _  -> "$Tuple"
          | Ast.TyRecord _ -> "$Record"
          | _ -> "$Unknown"
        in
        List.iter (fun ((mname : Ast.name), (mdef : Ast.fn_def)) ->
            let mangled = Printf.sprintf "%s$%s.%s"
              idef.impl_iface.txt type_name mname.txt in
            let fn = lower_fn_def mdef in
            fns := { fn with fn_name = mangled } :: !fns;
            let existing = match Hashtbl.find_opt !_iface_methods mname.txt with
              | Some l -> l | None -> [] in
            Hashtbl.replace !_iface_methods mname.txt
              ((type_name, mangled) :: existing)
          ) idef.impl_methods
      | _ -> ()
    ) m.mod_decls;
  (* Pass 2: Lower all other declarations. *)
  List.iter (fun d ->
      match d with
      | Ast.DFn (def, _) ->
        fns := lower_fn_def def :: !fns
      | Ast.DType (_, name, params, td, _) ->
        (match lower_type_def name params td with
         | Some td' -> types := td' :: !types
         | None -> ())
      | Ast.DLet (_, b, _) ->
        let rhs = lower_expr b.bind_expr in
        (match b.bind_pat with
         | Ast.PatVar n ->
           let v : Tir.var = {
             v_name = n.txt;
             v_ty = (match b.bind_ty with Some t -> lower_ty t
                     | None -> ty_of_expr b.bind_expr);
             v_lin = lower_linearity b.bind_lin;
           } in
           top_lets := (v, rhs) :: !top_lets
         | _ -> ())
      | Ast.DActor (_, name, actor_def, _) ->
        let (new_types, new_fns) = lower_actor name.txt actor_def in
        types := List.rev_append new_types !types;
        fns   := List.rev_append new_fns   !fns
      | Ast.DMod (mod_name, _, inner_decls, _) ->
        let rec lower_mod_decls prefix decls =
          let direct_fn_names = List.filter_map (function
              | Ast.DFn (def, _) -> Some def.fn_name.txt
              | _ -> None) decls in
          List.iter (fun d ->
              match d with
              | Ast.DFn (def, _) ->
                let fn = lower_fn_def def in
                let fn = rename_tir_vars prefix direct_fn_names fn in
                fns := { fn with fn_name = prefix ^ fn.fn_name } :: !fns
              | Ast.DType (_, tname, params, td, _) ->
                (match lower_type_def tname params td with
                 | Some td' -> types := td' :: !types
                 | None -> ())
              | Ast.DMod (sub_name, _, sub_decls, _) ->
                lower_mod_decls (prefix ^ sub_name.txt ^ ".") sub_decls
              | _ -> ()
            ) decls
        in
        lower_mod_decls (mod_name.txt ^ ".") inner_decls
      | Ast.DExtern (edef, _) ->
        List.iter (fun (ef : Ast.extern_fn) ->
            let params = List.map (fun (_, t) -> lower_ty t) ef.ef_params in
            let ret = lower_ty ef.ef_ret_ty in
            let c_name = edef.ext_lib_name ^ "_" ^ ef.ef_name.txt in
            externs := { Tir.ed_march_name = ef.ef_name.txt;
                         ed_c_name = c_name;
                         ed_params = params;
                         ed_ret = ret } :: !externs
          ) edef.ext_fns
      | Ast.DInterface _ | Ast.DImpl _ -> ()  (* handled in pass 1 *)
      | Ast.DProtocol _ | Ast.DSig _
      | Ast.DNeeds _ | Ast.DApp _ | Ast.DDeriving _
      | Ast.DTest _ | Ast.DSetup _ | Ast.DSetupAll _ -> ()
      | Ast.DUse (ud, _) ->
        (* Build use-import aliases: map unqualified names to qualified names.
           The qualified fn_defs are already in [fns] from DMod processing above. *)
        let prefix = String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) ^ "." in
        let all_fn_names = List.map (fun (fn : Tir.fn_def) -> fn.fn_name) !fns in
        (match ud.use_sel with
         | Ast.UseSingle -> ()
         | Ast.UseAll ->
           (* Find all functions with the matching prefix *)
           List.iter (fun fn_name ->
               let plen = String.length prefix in
               if String.length fn_name > plen
                  && String.sub fn_name 0 plen = prefix
               then begin
                 let short = String.sub fn_name plen (String.length fn_name - plen) in
                 Hashtbl.replace !_use_aliases short fn_name
               end
             ) all_fn_names
         | Ast.UseNames names ->
           List.iter (fun (n : Ast.name) ->
               let qualified = prefix ^ n.txt in
               if List.mem qualified all_fn_names then
                 Hashtbl.replace !_use_aliases n.txt qualified
             ) names
         | Ast.UseExcept excluded ->
           let excl_set = List.map (fun (n : Ast.name) -> n.txt) excluded in
           List.iter (fun fn_name ->
               let plen = String.length prefix in
               if String.length fn_name > plen
                  && String.sub fn_name 0 plen = prefix
               then begin
                 let short = String.sub fn_name plen (String.length fn_name - plen) in
                 if not (List.mem short excl_set) then
                   Hashtbl.replace !_use_aliases short fn_name
               end
             ) all_fn_names)
      | Ast.DAlias (ad, _) ->
        (* alias Long.Name, as: Short — map Short.f → Long.Name.f *)
        let orig_prefix = String.concat "." (List.map (fun n -> n.Ast.txt) ad.alias_path) ^ "." in
        let short_name = ad.alias_name.Ast.txt in
        let short_prefix = short_name ^ "." in
        let all_fn_names = List.map (fun (fn : Tir.fn_def) -> fn.fn_name) !fns in
        List.iter (fun fn_name ->
            let plen = String.length orig_prefix in
            if String.length fn_name > plen
               && String.sub fn_name 0 plen = orig_prefix
            then begin
              let rest = String.sub fn_name plen (String.length fn_name - plen) in
              Hashtbl.replace !_use_aliases (short_prefix ^ rest) fn_name
            end
          ) all_fn_names
      | Ast.DDescribe _ -> ()
    ) m.mod_decls;
  (* Inject top-level let bindings into main's body as a chain of ELet. *)
  let all_fns = List.rev !fns in
  let all_fns =
    match List.rev !top_lets with
    | [] -> all_fns
    | lets ->
      List.map (fun (fn : Tir.fn_def) ->
          let is_main = fn.fn_name = "main" ||
            (String.length fn.fn_name > 5 &&
             String.sub fn.fn_name (String.length fn.fn_name - 5) 5 = ".main") in
          if is_main then
            let body = List.fold_right (fun (v, rhs) body ->
                Tir.ELet (v, rhs, body)) lets fn.fn_body in
            { fn with fn_body = body }
          else fn
        ) all_fns
  in
  let result : Tir.tir_module = { tm_name = m.mod_name.txt;
    tm_fns = all_fns;
    tm_types = builtin_type_defs @ List.rev !types;
    tm_externs = List.rev !externs;
    tm_exports = [] } in
  _type_map_ref := None;
  _iface_methods := Hashtbl.create 0;
  _use_aliases := Hashtbl.create 0;
  result
