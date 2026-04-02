(** Monomorphization pass for the March TIR.

    Specializes all polymorphic function definitions to their concrete
    call-site types, eliminating all [Tir.TVar] placeholders.

    Algorithm:
    1. Build a table of all fn_defs by name.
    2. Seed the worklist with all root functions (no TVar in params).
    3. For each dequeued (fn_def, subst): apply subst, walk body for
       EApp calls to functions whose type has TVar, derive a new
       substitution from arg types, clone + rename callee, enqueue.
    4. Output: only the reachable monomorphic fn_defs. *)

(* ── Type detection ─────────────────────────────────────────────── *)

let rec has_tvar : Tir.ty -> bool = function
  | Tir.TVar "_"      -> false  (* lowering fallback placeholder, not a real polymorph *)
  | Tir.TVar _        -> true
  | Tir.TTuple ts     -> List.exists has_tvar ts
  | Tir.TRecord fs    -> List.exists (fun (_, t) -> has_tvar t) fs
  | Tir.TCon (_, args)-> List.exists has_tvar args
  | Tir.TFn (ps, ret) -> List.exists has_tvar ps || has_tvar ret
  | Tir.TPtr t        -> has_tvar t
  | _                 -> false   (* TInt, TFloat, TBool, TString, TUnit *)

(* ── Type substitution ──────────────────────────────────────────── *)

type ty_subst = (string * Tir.ty) list

let rec subst_ty (s : ty_subst) : Tir.ty -> Tir.ty = function
  | Tir.TVar name      ->
    (match List.assoc_opt name s with Some t -> t | None -> Tir.TVar name)
  | Tir.TTuple ts      -> Tir.TTuple (List.map (subst_ty s) ts)
  | Tir.TRecord fs     -> Tir.TRecord (List.map (fun (n, t) -> (n, subst_ty s t)) fs)
  | Tir.TCon (n, args) -> Tir.TCon (n, List.map (subst_ty s) args)
  | Tir.TFn (ps, ret)  -> Tir.TFn (List.map (subst_ty s) ps, subst_ty s ret)
  | Tir.TPtr t         -> Tir.TPtr (subst_ty s t)
  | t                  -> t

let subst_var (s : ty_subst) (v : Tir.var) : Tir.var =
  { v with Tir.v_ty = subst_ty s v.Tir.v_ty }

let subst_atom (s : ty_subst) : Tir.atom -> Tir.atom = function
  | Tir.AVar v    -> Tir.AVar (subst_var s v)
  | Tir.ADefRef _ as a -> a  (* global ref — no type vars to substitute *)
  | a             -> a

let rec subst_expr (s : ty_subst) : Tir.expr -> Tir.expr = function
  | Tir.EAtom a           -> Tir.EAtom (subst_atom s a)
  | Tir.EApp (f, args)    -> Tir.EApp (subst_var s f, List.map (subst_atom s) args)
  | Tir.ECallPtr (f, args)-> Tir.ECallPtr (subst_atom s f, List.map (subst_atom s) args)
  | Tir.ELet (v, e1, e2)  -> Tir.ELet (subst_var s v, subst_expr s e1, subst_expr s e2)
  | Tir.ELetRec (fns, body)->
    Tir.ELetRec (List.map (subst_fn_def s) fns, subst_expr s body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (subst_atom s a, List.map (subst_branch s) brs,
               Option.map (subst_expr s) def)
  | Tir.ETuple atoms      -> Tir.ETuple (List.map (subst_atom s) atoms)
  | Tir.ERecord fs        -> Tir.ERecord (List.map (fun (n, a) -> (n, subst_atom s a)) fs)
  | Tir.EField (a, n)     -> Tir.EField (subst_atom s a, n)
  | Tir.EUpdate (a, fs)   ->
    Tir.EUpdate (subst_atom s a, List.map (fun (n, a) -> (n, subst_atom s a)) fs)
  | Tir.EAlloc (ty, args)      -> Tir.EAlloc (subst_ty s ty, List.map (subst_atom s) args)
  | Tir.EStackAlloc (ty, args) -> Tir.EStackAlloc (subst_ty s ty, List.map (subst_atom s) args)
  | Tir.EFree a           -> Tir.EFree (subst_atom s a)
  | Tir.EIncRC a          -> Tir.EIncRC (subst_atom s a)
  | Tir.EDecRC a          -> Tir.EDecRC (subst_atom s a)
  | Tir.EAtomicIncRC a    -> Tir.EAtomicIncRC (subst_atom s a)
  | Tir.EAtomicDecRC a    -> Tir.EAtomicDecRC (subst_atom s a)
  | Tir.EReuse (a, ty, args) ->
    Tir.EReuse (subst_atom s a, subst_ty s ty, List.map (subst_atom s) args)
  | Tir.ESeq (e1, e2)     -> Tir.ESeq (subst_expr s e1, subst_expr s e2)

and subst_branch (s : ty_subst) (br : Tir.branch) : Tir.branch =
  { br with Tir.br_vars = List.map (subst_var s) br.Tir.br_vars;
            Tir.br_body = subst_expr s br.Tir.br_body }

and subst_fn_def (s : ty_subst) (fn : Tir.fn_def) : Tir.fn_def =
  { fn with Tir.fn_params = List.map (subst_var s) fn.Tir.fn_params;
            Tir.fn_ret_ty = subst_ty s fn.Tir.fn_ret_ty;
            Tir.fn_body   = subst_expr s fn.Tir.fn_body }

(* ── Name mangling ──────────────────────────────────────────────── *)

(** Produce a stable, readable string for a monomorphic type.
    Used to construct specialized function names like [map$Int$Bool]. *)
let rec mangle_ty : Tir.ty -> string = function
  | Tir.TInt          -> "Int"
  | Tir.TFloat        -> "Float"
  | Tir.TBool         -> "Bool"
  | Tir.TString       -> "String"
  | Tir.TUnit         -> "Unit"
  | Tir.TTuple ts     -> "T_" ^ String.concat "_" (List.map mangle_ty ts)
  | Tir.TRecord fs    ->
    "R_" ^ String.concat "_" (List.map (fun (n, t) -> n ^ "_" ^ mangle_ty t) fs)
  | Tir.TCon (n, [])  -> n
  | Tir.TCon (n, args)-> n ^ "_" ^ String.concat "_" (List.map mangle_ty args)
  | Tir.TFn (ps, ret) ->
    "Fn_" ^ String.concat "_" (List.map mangle_ty ps) ^ "_" ^ mangle_ty ret
  | Tir.TPtr t        -> "Ptr_" ^ mangle_ty t
  | Tir.TVar name     -> "V_" ^ name

(** [mangle_name base tys] appends a "$"-separated mangled suffix to [base].
    Returns [base] unchanged if [tys] is empty (already monomorphic). *)
let mangle_name (base : string) (tys : Tir.ty list) : string =
  match tys with
  | [] -> base
  | _  -> base ^ "$" ^ String.concat "$" (List.map mangle_ty tys)

(* ── Type matching (poly → concrete → subst) ────────────────────── *)

(** [match_ty poly conc acc] extends substitution [acc] by matching
    the polymorphic type [poly] (which may contain TVar) against the
    concrete type [conc]. Does not fail — unmatched combinations are
    silently skipped (this is not unification; types must be structurally
    compatible after lowering). *)
let rec match_ty (poly : Tir.ty) (conc : Tir.ty) (acc : ty_subst) : ty_subst =
  match poly, conc with
  | Tir.TVar name, t ->
    if List.mem_assoc name acc then acc else (name, t) :: acc
  | Tir.TCon (n1, ps1), Tir.TCon (n2, ps2) when n1 = n2 && List.length ps1 = List.length ps2 ->
    List.fold_left2 (fun acc p c -> match_ty p c acc) acc ps1 ps2
  | Tir.TTuple ps1, Tir.TTuple ps2 when List.length ps1 = List.length ps2 ->
    List.fold_left2 (fun acc p c -> match_ty p c acc) acc ps1 ps2
  | Tir.TFn (ps1, r1), Tir.TFn (ps2, r2) when List.length ps1 = List.length ps2 ->
    let acc = List.fold_left2 (fun acc p c -> match_ty p c acc) acc ps1 ps2 in
    match_ty r1 r2 acc
  | Tir.TPtr p, Tir.TPtr c -> match_ty p c acc
  | _ -> acc

(* ── Worklist monomorphization ──────────────────────────────────── *)

(** Derive the type substitution for calling [fn_def] with arguments
    of types [arg_tys]. Matches each parameter's type against the
    corresponding argument type to collect TVar bindings. *)
let build_subst (fn : Tir.fn_def) (arg_tys : Tir.ty list) : ty_subst =
  let param_tys = List.map (fun v -> v.Tir.v_ty) fn.Tir.fn_params in
  let pairs =
    if List.length param_tys = List.length arg_tys
    then List.combine param_tys arg_tys
    else []   (* arity mismatch — don't substitute *)
  in
  List.fold_left (fun acc (poly, conc) -> match_ty poly conc acc) [] pairs

(** Ensure any function referenced as a value (atom) is enqueued for emission. *)
let ensure_atom_fns fn_table done_set worklist atoms =
  List.iter (function
    | Tir.AVar v ->
      let name = v.Tir.v_name in
      (match Hashtbl.find_opt fn_table name with
       | Some orig_fn when not (Hashtbl.mem done_set name) ->
         Queue.add (name, orig_fn, []) worklist
       | _ -> ())
    | Tir.ADefRef _ -> ()  (* global def ref — not in fn_table, skip *)
    | _ -> ()
  ) atoms

(** Rewrite all [EApp] and [ELetRec] calls in [expr] that target
    polymorphic functions, replacing them with calls to the
    specialized (mangled) version and enqueuing the specialization
    if not already done. *)
let rec rewrite_calls
    (fn_table  : (string, Tir.fn_def) Hashtbl.t)
    (done_set  : (string, unit) Hashtbl.t)
    (worklist  : (string * Tir.fn_def * ty_subst) Queue.t)
    (expr      : Tir.expr)
  : Tir.expr =
  match expr with
  | Tir.EApp (f_var, args) ->
    (* Ensure functions passed as arguments are discovered *)
    ensure_atom_fns fn_table done_set worklist args;
    (* Check if the *callee's definition* is polymorphic (has TVar in params),
       NOT whether f_var.v_ty has TVar. After Task 1, call sites have concrete
       types from the type_map, so f_var.v_ty is already monomorphic there —
       but the fn_def it refers to may still be the generic version. *)
    let orig_name = f_var.Tir.v_name in
    (match Hashtbl.find_opt fn_table orig_name with
     | None -> expr   (* builtin or external, leave as-is *)
     | Some orig_fn
       when not (List.exists (fun v -> has_tvar v.Tir.v_ty) orig_fn.Tir.fn_params) ->
       (* Callee params are monomorphic but it may not have been seeded
          (e.g. return type has TVar).  Ensure it's enqueued. *)
       if not (Hashtbl.mem done_set orig_name) then
         Queue.add (orig_name, orig_fn, []) worklist;
       expr
     | Some orig_fn ->
       let lit_ty = function
         | March_ast.Ast.LitInt _    -> Tir.TInt
         | March_ast.Ast.LitFloat _  -> Tir.TFloat
         | March_ast.Ast.LitBool _   -> Tir.TBool
         | March_ast.Ast.LitString _ -> Tir.TString
         | March_ast.Ast.LitAtom _   -> Tir.TUnit
       in
       let arg_tys = List.map (function
           | Tir.AVar v -> v.Tir.v_ty
           | Tir.ADefRef _ -> Tir.TPtr Tir.TUnit  (* global ref, treat as opaque ptr *)
           | Tir.ALit l -> lit_ty l
         ) args in
       let subst = build_subst orig_fn arg_tys in
       if subst = [] then begin
         (* No specialization needed (monomorphic or unresolved TVar args) —
            but still enqueue to ensure the function is emitted.  Matches the
            ECallPtr branch below which already handles this case correctly. *)
         if not (Hashtbl.mem done_set orig_name) then
           Queue.add (orig_name, orig_fn, []) worklist;
         expr
       end
       else begin
         let param_tys_concrete = List.map (fun v -> subst_ty subst v.Tir.v_ty)
             orig_fn.Tir.fn_params in
         let mangled = mangle_name orig_name param_tys_concrete in
         if not (Hashtbl.mem done_set mangled) then
           Queue.add (mangled, orig_fn, subst) worklist;
         let f_var' = { f_var with Tir.v_name = mangled;
                                   v_ty = subst_ty subst f_var.Tir.v_ty } in
         Tir.EApp (f_var', args)
       end)
  (* ECallPtr: if the callee is a known top-level fn, ensure it's discovered *)
  | Tir.ECallPtr (fn_atom, args) ->
    (match fn_atom with
     | Tir.AVar v ->
       let orig_name = v.Tir.v_name in
       (match Hashtbl.find_opt fn_table orig_name with
        | None -> expr  (* unknown / builtin *)
        | Some orig_fn ->
          (* If callee is polymorphic, try to build a substitution from args *)
          let lit_ty = function
            | March_ast.Ast.LitInt _    -> Tir.TInt
            | March_ast.Ast.LitFloat _  -> Tir.TFloat
            | March_ast.Ast.LitBool _   -> Tir.TBool
            | March_ast.Ast.LitString _ -> Tir.TString
            | March_ast.Ast.LitAtom _   -> Tir.TUnit
          in
          let arg_tys = List.map (function
              | Tir.AVar v -> v.Tir.v_ty
              | Tir.ADefRef _ -> Tir.TPtr Tir.TUnit  (* global ref, treat as opaque ptr *)
              | Tir.ALit l -> lit_ty l
            ) args in
          (* Partial application: only first N params have concrete args *)
          let param_vars = orig_fn.Tir.fn_params in
          let n = min (List.length arg_tys) (List.length param_vars) in
          let pairs = List.combine
              (List.filteri (fun i _ -> i < n) (List.map (fun v -> v.Tir.v_ty) param_vars))
              (List.filteri (fun i _ -> i < n) arg_tys) in
          let subst = List.fold_left (fun acc (poly, conc) -> match_ty poly conc acc) [] pairs in
          if subst = [] then begin
            (* No specialization needed — just ensure it's enqueued as-is *)
            if not (Hashtbl.mem done_set orig_name) then
              Queue.add (orig_name, orig_fn, []) worklist;
            expr
          end else begin
            let param_tys_concrete = List.map (fun v -> subst_ty subst v.Tir.v_ty) param_vars in
            let mangled = mangle_name orig_name param_tys_concrete in
            if not (Hashtbl.mem done_set mangled) then
              Queue.add (mangled, orig_fn, subst) worklist;
            let v' = { v with Tir.v_name = mangled;
                              v_ty = subst_ty subst v.Tir.v_ty } in
            Tir.ECallPtr (Tir.AVar v', args)
          end)
     | _ -> expr)
  | Tir.ELet (v, e1, e2) ->
    Tir.ELet (v,
      rewrite_calls fn_table done_set worklist e1,
      rewrite_calls fn_table done_set worklist e2)
  | Tir.ELetRec (fns, body) ->
    let fns' = List.map (fun fn ->
        { fn with Tir.fn_body = rewrite_calls fn_table done_set worklist fn.Tir.fn_body }
      ) fns in
    Tir.ELetRec (fns', rewrite_calls fn_table done_set worklist body)
  | Tir.ECase (a, brs, def) ->
    let brs' = List.map (fun br ->
        { br with Tir.br_body = rewrite_calls fn_table done_set worklist br.Tir.br_body }
      ) brs in
    Tir.ECase (a, brs', Option.map (rewrite_calls fn_table done_set worklist) def)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (rewrite_calls fn_table done_set worklist e1,
              rewrite_calls fn_table done_set worklist e2)
  | other -> other

(** Main entry point. Returns a new [tir_module] with no [TVar] in
    any fn_def that is reachable from a monomorphic root. Polymorphic
    fn_defs with no monomorphic callers are dropped (unreachable). *)
let monomorphize (m : Tir.tir_module) : Tir.tir_module =
  (* Build lookup table for original fn_defs *)
  let fn_table : (string, Tir.fn_def) Hashtbl.t = Hashtbl.create 32 in
  List.iter (fun fn -> Hashtbl.replace fn_table fn.Tir.fn_name fn) m.Tir.tm_fns;

  let result   : Tir.fn_def list ref = ref [] in
  let done_set : (string, unit) Hashtbl.t = Hashtbl.create 32 in
  (* worklist entries: (target_name, original_fn_def, subst_to_apply) *)
  let worklist : (string * Tir.fn_def * ty_subst) Queue.t = Queue.create () in

  (* Seed: all fns that are already monomorphic (no TVar in params or ret),
     plus always seed "main" / "*.main" as entry points. *)
  List.iter (fun fn ->
    let is_mono =
      (not (List.exists (fun v -> has_tvar v.Tir.v_ty) fn.Tir.fn_params)) &&
      not (has_tvar fn.Tir.fn_ret_ty)
    in
    let is_main =
      fn.Tir.fn_name = "main" ||
      (let n = fn.Tir.fn_name in
       let suf = ".main" in
       let ln = String.length n and ls = String.length suf in
       ln >= ls && String.sub n (ln - ls) ls = suf)
    in
    let is_export = List.mem fn.Tir.fn_name m.Tir.tm_exports in
    if is_mono || is_main || is_export then
      Queue.add (fn.Tir.fn_name, fn, []) worklist
  ) m.Tir.tm_fns;

  while not (Queue.is_empty worklist) do
    let (target_name, orig_fn, subst) = Queue.pop worklist in
    if not (Hashtbl.mem done_set target_name) then begin
      Hashtbl.add done_set target_name ();
      (* Apply substitution to get the specialized version *)
      let fn' = subst_fn_def subst orig_fn in
      let fn' = { fn' with Tir.fn_name = target_name } in
      (* Rewrite calls in the body, enqueuing new specializations *)
      let body' = rewrite_calls fn_table done_set worklist fn'.Tir.fn_body in
      result := { fn' with Tir.fn_body = body' } :: !result
    end
  done;

  { m with Tir.tm_fns = List.rev !result }
