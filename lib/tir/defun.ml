(** Defunctionalization pass for the March TIR.

    Eliminates lambdas (ELetRec-as-value) by:
    1. Computing free variables of each lambda
    2. Creating TDClosure structs for each lambda's captured environment
    3. Lifting lambda bodies to top-level functions with free vars as leading params
    4. Replacing lambda creation sites with EAlloc of the closure struct
    5. Replacing indirect calls (EApp of TFn-typed non-top-level vars) with ECallPtr *)

module StringSet = Set.Make(String)

(** Names that are globally known and should never be treated as free
    variables: built-in operators, primitives, and list helpers. *)
let builtin_names : StringSet.t =
  List.fold_left (fun s n -> StringSet.add n s) StringSet.empty
    [ "+"; "-"; "*"; "/"; "%"; "negate";
      "+."; "-."; "*."; "/.";
      "<"; ">"; "<="; ">="; "&&"; "||";
      "=="; "!="; "++";
      "print"; "println"; "print_int"; "print_float";
      "int_to_string"; "float_to_string"; "bool_to_string";
      "string_to_int"; "string_length"; "string_concat";
      "read_line"; "not";
      "head"; "tail"; "is_nil";
      "to_string"; "respond"; "kill"; "is_alive";
      "send"; "spawn" ]

(* ── Phase 0: collect top-level names ────────────────────────────── *)

let collect_top_level_names (m : Tir.tir_module) : StringSet.t =
  let user_fns = List.fold_left (fun s fn -> StringSet.add fn.Tir.fn_name s)
      StringSet.empty m.Tir.tm_fns in
  StringSet.union user_fns builtin_names

(* ── Phase 1: free variable analysis ─────────────────────────────── *)

(** Collect free variables of an expression.
    [bound] is the set of locally-bound names.
    [tl] is the set of top-level function names.
    Returns an association list of (name, ty) with no duplicates, sorted by name. *)
let free_vars_of_expr (top_level : StringSet.t) (body : Tir.expr) (params : Tir.var list) :
    (string * Tir.ty) list =
  (* Result stored as a name→ty map to avoid duplicates *)
  let result : (string, Tir.ty) Hashtbl.t = Hashtbl.create 8 in

  let add_fv name ty =
    if not (Hashtbl.mem result name) then
      Hashtbl.add result name ty
  in

  let fv_var (v : Tir.var) (bound : StringSet.t) =
    if StringSet.mem v.Tir.v_name bound || StringSet.mem v.Tir.v_name top_level then ()
    else add_fv v.Tir.v_name v.Tir.v_ty
  in

  let fv_atom (a : Tir.atom) (bound : StringSet.t) =
    match a with
    | Tir.AVar v -> fv_var v bound
    | Tir.ALit _ -> ()
  in

  let rec fv_expr (e : Tir.expr) (bound : StringSet.t) =
    match e with
    | Tir.EAtom a -> fv_atom a bound
    | Tir.EApp (f, args) ->
      fv_var f bound;
      List.iter (fun a -> fv_atom a bound) args
    | Tir.ECallPtr (f, args) ->
      fv_atom f bound;
      List.iter (fun a -> fv_atom a bound) args
    | Tir.ELet (v, e1, e2) ->
      fv_expr e1 bound;
      fv_expr e2 (StringSet.add v.Tir.v_name bound)
    | Tir.ELetRec (fns, body) ->
      let fn_names = List.fold_left (fun s fn -> StringSet.add fn.Tir.fn_name s)
          StringSet.empty fns in
      let inner = StringSet.union bound fn_names in
      List.iter (fun fn ->
        let inner_params = List.fold_left (fun s p -> StringSet.add p.Tir.v_name s)
            inner fn.Tir.fn_params in
        fv_expr fn.Tir.fn_body inner_params
      ) fns;
      fv_expr body inner
    | Tir.ECase (a, brs, def) ->
      fv_atom a bound;
      List.iter (fun (br : Tir.branch) ->
        let bound' = List.fold_left (fun s v -> StringSet.add v.Tir.v_name s)
            bound br.Tir.br_vars in
        fv_expr br.Tir.br_body bound'
      ) brs;
      (match def with Some e -> fv_expr e bound | None -> ())
    | Tir.ETuple atoms ->
      List.iter (fun a -> fv_atom a bound) atoms
    | Tir.ERecord fields ->
      List.iter (fun (_, a) -> fv_atom a bound) fields
    | Tir.EField (a, _) -> fv_atom a bound
    | Tir.EUpdate (a, fields) ->
      fv_atom a bound;
      List.iter (fun (_, a) -> fv_atom a bound) fields
    | Tir.EAlloc (_, args) | Tir.EStackAlloc (_, args) ->
      List.iter (fun a -> fv_atom a bound) args
    | Tir.EFree a -> fv_atom a bound
    | Tir.EIncRC a -> fv_atom a bound
    | Tir.EDecRC a -> fv_atom a bound
    | Tir.EReuse (a, _, args) ->
      fv_atom a bound;
      List.iter (fun a -> fv_atom a bound) args
    | Tir.ESeq (e1, e2) ->
      fv_expr e1 bound;
      fv_expr e2 bound
  in

  (* Initial bound = the lambda's own params *)
  let initial_bound = List.fold_left (fun s p -> StringSet.add p.Tir.v_name s)
      StringSet.empty params in
  fv_expr body initial_bound;
  (* Return sorted by name for determinism *)
  let pairs = Hashtbl.fold (fun k v acc -> (k, v) :: acc) result [] in
  List.sort (fun (a, _) (b, _) -> String.compare a b) pairs

(** A detected lambda with its free variables. *)
type lambda_info = {
  lam_fn   : Tir.fn_def;           (* the original fn_def inside ELetRec *)
  lam_fvs  : (string * Tir.ty) list;  (* free variables, sorted by name *)
}

(** Collect all lambdas from all top-level fn bodies. *)
let collect_lambdas (m : Tir.tir_module) (top_level : StringSet.t) : lambda_info list =
  let lambdas = ref [] in

  let rec collect_expr (e : Tir.expr) =
    match e with
    | Tir.ELetRec ([fn], Tir.EAtom (Tir.AVar ref_var))
      when fn.Tir.fn_name = ref_var.Tir.v_name ->
      (* This is a lambda *)
      let fvs = free_vars_of_expr top_level fn.Tir.fn_body fn.Tir.fn_params in
      lambdas := { lam_fn = fn; lam_fvs = fvs } :: !lambdas;
      (* Recurse into the lambda body too *)
      collect_expr fn.Tir.fn_body
    | Tir.ELetRec (fns, body) ->
      List.iter (fun fn -> collect_expr fn.Tir.fn_body) fns;
      collect_expr body
    | Tir.ELet (_, e1, e2) ->
      collect_expr e1; collect_expr e2
    | Tir.ECase (_, brs, def) ->
      List.iter (fun (br : Tir.branch) -> collect_expr br.Tir.br_body) brs;
      (match def with Some e -> collect_expr e | None -> ())
    | Tir.ESeq (e1, e2) ->
      collect_expr e1; collect_expr e2
    | _ -> ()
  in

  List.iter (fun fn -> collect_expr fn.Tir.fn_body) m.Tir.tm_fns;
  List.rev !lambdas

(* ── Phase 2: closure struct + lifted fn generation ──────────────── *)

(** Build the new top-level lifted fn and TDClosure type def for a lambda.

    Closure convention: field 0 of every closure struct is the apply fn ptr
    (typed TPtr TUnit).  The apply fn takes (ptr $clo, original_params) and
    loads its own free variables from $clo at entry.  This lets ECallPtr call
    uniformly through field 0 without knowing the specific lambda statically. *)
let lift_lambda (lam : lambda_info) : Tir.type_def * Tir.fn_def =
  let fn = lam.lam_fn in
  let fvs = lam.lam_fvs in
  let clo_name = "$Clo_" ^ fn.Tir.fn_name in
  let apply_name = fn.Tir.fn_name ^ "$apply" in
  (* TDClosure struct: [fn_ptr: TPtr(TUnit), fv0_ty, fv1_ty, ...] *)
  let td = Tir.TDClosure (clo_name, Tir.TPtr Tir.TUnit :: List.map snd fvs) in
  (* $clo parameter — opaque pointer to the closure struct itself *)
  let clo_param = { Tir.v_name = "$clo"; v_ty = Tir.TPtr Tir.TUnit; v_lin = Tir.Unr } in
  (* Wrap the original body with ELet bindings that load each free variable
     from the closure struct.  Field indices: fn_ptr=0, fv[i]=i+1. *)
  let wrapped_body =
    List.fold_right (fun (i, (fv_name, fv_ty)) acc ->
        let fv_var = { Tir.v_name = fv_name; v_ty = fv_ty; v_lin = Tir.Unr } in
        let field_name = "$fv" ^ string_of_int (i + 1) in
        let load_expr  = Tir.EField (Tir.AVar clo_param, field_name) in
        Tir.ELet (fv_var, load_expr, acc)
      ) (List.mapi (fun i fv -> (i, fv)) fvs) fn.Tir.fn_body
  in
  let apply_fn : Tir.fn_def = {
    fn_name   = apply_name;
    fn_params = clo_param :: fn.Tir.fn_params;
    fn_ret_ty = fn.Tir.fn_ret_ty;
    fn_body   = wrapped_body;
  } in
  (td, apply_fn)

(* ── Phase 3: expression rewriting ───────────────────────────────── *)

(** Rewrite expressions:
    - Lambda creation sites → EAlloc of closure struct
    - Indirect calls (EApp of TFn-typed non-top-level var) → ECallPtr *)
let rewrite_expr (known_lambdas : (string * lambda_info) list)
    (top_level : StringSet.t) (e : Tir.expr) : Tir.expr =
  let rec rw = function
    (* A. Lambda creation site *)
    | Tir.ELetRec ([fn], Tir.EAtom (Tir.AVar ref_var))
      when fn.Tir.fn_name = ref_var.Tir.v_name ->
      (match List.assoc_opt fn.Tir.fn_name known_lambdas with
       | Some lam ->
         let apply_name = fn.Tir.fn_name ^ "$apply" in
         let fn_ptr_atom = Tir.AVar { Tir.v_name = apply_name;
                                       v_ty = Tir.TPtr Tir.TUnit;
                                       v_lin = Tir.Unr } in
         let fv_atoms = List.map (fun (name, ty) ->
             Tir.AVar { Tir.v_name = name; v_ty = ty; v_lin = Tir.Unr }
           ) lam.lam_fvs in
         Tir.EAlloc (Tir.TCon ("$Clo_" ^ fn.Tir.fn_name, []), fn_ptr_atom :: fv_atoms)
       | None ->
         (* Not a known lambda — rewrite children *)
         Tir.ELetRec ([{ fn with Tir.fn_body = rw fn.Tir.fn_body }],
                      Tir.EAtom (Tir.AVar ref_var)))

    (* B. Indirect call: EApp of a TFn-typed non-top-level var *)
    | Tir.EApp (f_var, args)
      when (match f_var.Tir.v_ty with Tir.TFn _ -> true | _ -> false)
        && not (StringSet.mem f_var.Tir.v_name top_level) ->
      Tir.ECallPtr (Tir.AVar f_var, args)

    (* Recurse into all other forms *)
    | Tir.ELetRec (fns, body) ->
      let fns' = List.map (fun fn -> { fn with Tir.fn_body = rw fn.Tir.fn_body }) fns in
      Tir.ELetRec (fns', rw body)
    | Tir.ELet (v, e1, e2) ->
      Tir.ELet (v, rw e1, rw e2)
    | Tir.ECase (a, brs, def) ->
      let brs' = List.map (fun (br : Tir.branch) ->
          { br with Tir.br_body = rw br.Tir.br_body }
        ) brs in
      Tir.ECase (a, brs', Option.map rw def)
    | Tir.ESeq (e1, e2) ->
      Tir.ESeq (rw e1, rw e2)
    | e -> e
  in
  rw e

(* ── Entry point ─────────────────────────────────────────────────── *)

let defunctionalize (m : Tir.tir_module) : Tir.tir_module =
  (* Phase 0: top-level names *)
  let top_level = collect_top_level_names m in

  (* Phase 1: collect all lambdas and their free variables *)
  let lambdas = collect_lambdas m top_level in
  let known_lambdas = List.map (fun lam -> (lam.lam_fn.Tir.fn_name, lam)) lambdas in

  (* Phase 2: generate closure structs and lifted fns *)
  let (new_types, new_fns) = List.split (List.map lift_lambda lambdas) in

  (* Phase 3: rewrite all top-level fn bodies *)
  let rewritten_fns = List.map (fun fn ->
      { fn with Tir.fn_body = rewrite_expr known_lambdas top_level fn.Tir.fn_body }
    ) m.Tir.tm_fns in
  (* Also rewrite lifted apply fns (to handle nested lambdas) *)
  let rewritten_new_fns = List.map (fun fn ->
      { fn with Tir.fn_body = rewrite_expr known_lambdas top_level fn.Tir.fn_body }
    ) new_fns in

  {
    m with
    Tir.tm_fns   = rewritten_fns @ rewritten_new_fns;
    Tir.tm_types = m.Tir.tm_types @ new_types;
  }
