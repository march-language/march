(** March desugaring pass.

    Transforms the surface AST into a simpler "core" form that the type
    checker and all subsequent passes can handle uniformly.  The key
    transformations are:

    1. **Multi-head function desugaring** — consecutive fn clauses with the
       same name are already grouped into a single [DFn] by the parser's
       [group_fn_clauses].  Here we turn a [fn_def] with more than one
       clause (or with pattern params in a single clause) into a single
       clause whose body is a [match] expression.

       Before:
         fn fib(0) do 1 end
         fn fib(1) do 1 end
         fn fib(n) do fib(n-1) + fib(n-2) end

       After grouping (done by parser):
         DFn { fn_clauses = [clause0; clause1; clause2] }

       After desugaring (done here):
         DFn { fn_clauses = [
           { fc_params  = [FPNamed "__arg0"]
           ; fc_guard   = None
           ; fc_body    = EMatch(__arg0, [
               0   -> 1
               1   -> 1
               n   -> fib(n-1) + fib(n-2)
             ])
           }
         ]}

    2. **Pipe desugaring** — [x |> f] becomes [f(x)].

    3. **If without else** (future) — for now [if] always requires else.

    The output is still an [Ast.module_] — we don't introduce a separate
    Core AST yet.  That will come when we have enough typed information to
    make it worthwhile. *)

open March_ast.Ast

(* ---- Utilities ---- *)

(** Counter for generating unique synthetic spans for synthesised params.
    Each call to [fresh_arg_name] gets a distinct [start_line] so that
    the typechecker can annotate each synthesised [__argN] param at its
    own slot in the type_map, avoiding collisions across functions that
    previously all shared [dummy_span] and got the wrong inferred type. *)
let _synth_counter = ref 0

(** Generate fresh argument names __arg0, __arg1 … for synthesised match
    scrutinees.  These are prefixed with "__" to avoid shadowing user
    bindings.  Each generated name gets a unique synthetic span so the
    typechecker's type_map entries don't collide across functions. *)
let fresh_arg_name i =
  incr _synth_counter;
  let txt = Printf.sprintf "__arg%d" i in
  { txt; span = { file = "__synth__";
                  start_line = !_synth_counter;
                  start_col  = i;
                  end_line   = 0;
                  end_col    = 0 } }

(** True if a fn_param is "trivially named" — i.e. it is an [FPNamed]
    with no need to match.  A single clause of all trivially-named params
    needs no match desugaring. *)
let is_trivial_param = function
  | FPNamed _ -> true
  | FPPat (PatVar _) -> true   (* single var pattern is just a binding *)
  | FPPat _ -> false

(** A guard looks like a type-class constraint (e.g. [Eq(a)]) when it is a
    constructor application whose constructor name starts with an uppercase
    letter.  Such guards should be preserved in [fc_guard] rather than
    pushed into a match-branch guard so that the type checker can recognize
    and handle them as interface constraints on the function's scheme. *)
let is_class_constraint_guard = function
  | Some (ECon (name, _, _))
    when String.length name.txt > 0
      && Char.uppercase_ascii name.txt.[0] = name.txt.[0] -> true
  | _ -> false

(** True if a single-clause fn needs no match desugaring at all. *)
let clause_is_trivial (clause : fn_clause) =
  (clause.fc_guard = None || is_class_constraint_guard clause.fc_guard)
  && List.for_all is_trivial_param clause.fc_params

(** Convert an [fn_param] into the [pattern] used as a branch arm.
    - [FPNamed p]        → PatVar p.param_name
    - [FPPat p]          → p  (already a pattern) *)
let fn_param_to_pattern : fn_param -> pattern = function
  | FPNamed p -> PatVar p.param_name
  | FPPat  p  -> p

(** Convert an [fn_param] into the "declaration" form used in the
    single merged clause.  We always use an [FPNamed] with the generated
    arg name so the type checker sees a simple named param. *)
let mk_named_param name : fn_param =
  FPNamed { param_name = name; param_ty = None; param_lin = Unrestricted }

(* ---- Pipe desugaring ---- *)

(** Desugar [EPipe (l, r, sp)] → [EApp (r, [l], sp)].
    Works recursively; all other nodes are walked to catch nested pipes. *)
let rec desugar_expr (e : expr) : expr =
  match e with
  (* --- Pipe: x |> f(a,b)  ⟶  f(x,a,b) --- *)
  (* Elixir-style pipe: the LHS becomes the FIRST argument of the RHS.
     When the RHS is already an application, prepend the LHS to its
     argument list so we get a single saturated call instead of a
     curried (partial-apply) chain. *)
  | EPipe (l, r, sp) ->
    let l' = desugar_expr l in
    let r' = desugar_expr r in
    (match r' with
     | EApp (f, args, _) -> EApp (f, l' :: args, sp)
     | _ -> EApp (r', [l'], sp))

  (* --- Recurse into all other nodes --- *)
  | ELit _ | EVar _ | EHole _ | EResultRef _ -> e
  | EDbg (None, _) -> e
  | EDbg (Some inner, sp) -> EDbg (Some (desugar_expr inner), sp)

  | EApp (f, args, sp) ->
    let f' = desugar_expr f in
    let args' = List.map desugar_expr args in
    (* When a qualified constructor reference (e.g. Result.Error, desugared
       from EField to ECon("Result.Error",[],_)) is applied to arguments,
       fold the args directly into the ECon so the typechecker and eval see a
       proper constructor application rather than a function call. *)
    (match f' with
     | ECon (name, [], _) when String.contains name.txt '.' ->
       ECon (name, args', sp)
     | _ ->
       EApp (f', args', sp))

  | ECon (name, args, sp) ->
    ECon (name, List.map desugar_expr args, sp)

  | ELam (ps, body, sp) ->
    ELam (ps, desugar_expr body, sp)

  | EBlock (es, sp) ->
    EBlock (List.map desugar_expr es, sp)

  | ELet (b, sp) ->
    ELet ({ b with bind_expr = desugar_expr b.bind_expr }, sp)

  | EMatch (scrut, branches, sp) ->
    let branches' = List.map (fun br ->
        { br with branch_guard = Option.map desugar_expr br.branch_guard
                ; branch_body  = desugar_expr br.branch_body }) branches in
    EMatch (desugar_expr scrut, branches', sp)

  | ETuple (es, sp) ->
    ETuple (List.map desugar_expr es, sp)

  | ERecord (fields, sp) ->
    ERecord (List.map (fun (n, ex) -> (n, desugar_expr ex)) fields, sp)

  | ERecordUpdate (base, fields, sp) ->
    ERecordUpdate (desugar_expr base,
                   List.map (fun (n, ex) -> (n, desugar_expr ex)) fields,
                   sp)

  | EField (ex, name, sp) ->
    (* Desugar module member access: A.B.fn(...) → EVar "A.B.fn"
       If the base is a chain of ECon/EField that looks like a module path,
       flatten it into a single qualified name.
       When the field name is uppercase (a constructor), emit ECon so that the
       typechecker resolves it through the constructor table rather than vars. *)
    let rec flatten_module_path = function
      | ECon (mod_name, [], _) -> Some mod_name.txt
      | EField (inner, field, _) ->
        (match flatten_module_path inner with
         | Some prefix -> Some (prefix ^ "." ^ field.txt)
         | None -> None)
      | _ -> None
    in
    (match flatten_module_path ex with
     | Some prefix ->
       let qualified_txt = prefix ^ "." ^ name.txt in
       if String.length name.txt > 0 && Char.uppercase_ascii name.txt.[0] = name.txt.[0]
       then ECon ({ txt = qualified_txt; span = sp }, [], sp)
       else EVar { txt = qualified_txt; span = sp }
     | None -> EField (desugar_expr ex, name, sp))

  | EIf (cond, t, f, sp) ->
    EIf (desugar_expr cond, desugar_expr t, desugar_expr f, sp)

  | EAnnot (ex, ty, sp) ->
    EAnnot (desugar_expr ex, ty, sp)

  | EAtom (a, args, sp) ->
    EAtom (a, List.map desugar_expr args, sp)

  | ESend (cap, msg, sp) ->
    ESend (desugar_expr cap, desugar_expr msg, sp)

  | ESpawn (actor, sp) ->
    ESpawn (desugar_expr actor, sp)

  | ELetFn (name, params, ret_ty, body, sp) ->
    ELetFn (name, params, ret_ty, desugar_expr body, sp)

  | EAssert (e, sp) ->
    EAssert (desugar_expr e, sp)

(* ---- Multi-head fn desugaring ---- *)

(** Desugar a [fn_def] that may have multiple clauses (or pattern params)
    into one that always has exactly one clause with only [FPNamed] params.

    Strategy:
    - Count params by looking at the first clause (all clauses must have
      the same arity — a later validation pass can enforce this).
    - Generate fresh arg names [__arg0 … __argN].
    - Build a tuple scrutinee if arity > 1, otherwise use the single arg.
    - Build one [branch] per clause, turning its [fn_param list] into a
      [PatTuple] (or direct pattern for arity 1), plus the clause guard.
    - The body of the merged clause is [EMatch(scrutinee, branches)].
    - If there is only one clause AND it is trivial (all named params, no
      guard), skip the match and return as-is — no-op for simple functions. *)
let desugar_fn_def (def : fn_def) (fn_span : span) : fn_def =
  let clauses = def.fn_clauses in
  match clauses with
  | [] -> def   (* degenerate — validation pass will catch this *)

  | [only] when clause_is_trivial only ->
    (* Fast path: single clause, all named params, no guard — nothing to do
       except recursively desugar the body. *)
    let only' = { only with fc_body = desugar_expr only.fc_body
                           ; fc_guard = Option.map desugar_expr only.fc_guard }
    in
    { def with fn_clauses = [only'] }

  | first :: _ ->
    (* General path: synthesise fresh arg names based on first clause's arity. *)
    let arity = List.length first.fc_params in
    let arg_names = List.init arity fresh_arg_name in

    (* Build the scrutinee expression from the generated arg names. *)
    let scrutinee : expr =
      match arg_names with
      | [n] -> EVar n
      | ns  -> ETuple (List.map (fun n -> EVar n) ns, fn_span)
    in

    (* Convert one clause into a match branch. *)
    let clause_to_branch (clause : fn_clause) : branch =
      let patterns = List.map fn_param_to_pattern clause.fc_params in
      let pat : pattern =
        match patterns with
        | [p] -> p
        | ps  -> PatTuple (ps, clause.fc_span)
      in
      { branch_pat   = pat
      ; branch_guard = Option.map desugar_expr clause.fc_guard
      ; branch_body  = desugar_expr clause.fc_body
      }
    in

    let branches = List.map clause_to_branch clauses in

    (* Build the merged body: match (arg0, …, argN) do … end *)
    let body = EMatch (scrutinee, branches, fn_span) in

    (* Single merged clause with all FPNamed params *)
    let merged_clause : fn_clause =
      { fc_params = List.map mk_named_param arg_names
      ; fc_guard  = None
      ; fc_body   = body
      ; fc_span   = fn_span
      }
    in
    { def with fn_clauses = [merged_clause] }

(* ---- Declaration desugaring ---- *)

let rec desugar_decl (d : decl) : decl =
  match d with
  | DFn (def, sp) ->
    DFn (desugar_fn_def def sp, sp)

  | DLet (vis, b, sp) ->
    DLet (vis, { b with bind_expr = desugar_expr b.bind_expr }, sp)

  | DType _ ->
    (* Type declarations have no expressions to desugar. *)
    d

  | DActor (vis, name, actor, sp) ->
    let init'     = desugar_expr actor.actor_init in
    let handlers' = List.map (fun h ->
        { h with ah_body = desugar_expr h.ah_body }) actor.actor_handlers in
    DActor (vis, name, { actor with actor_init = init'; actor_handlers = handlers' }, sp)

  | DMod (name, vis, decls, sp) ->
    DMod (name, vis, List.map desugar_decl decls, sp)

  | DInterface (idef, sp) ->
    (* Desugar default method bodies *)
    let methods' = List.map (fun (m : method_decl) ->
        { m with md_default = Option.map desugar_expr m.md_default }
      ) idef.iface_methods in
    DInterface ({ idef with iface_methods = methods' }, sp)

  | DImpl (idef, sp) ->
    (* Desugar each provided method's fn_def *)
    let methods' = List.map (fun (name, def) ->
        (name, desugar_fn_def def sp)
      ) idef.impl_methods in
    DImpl ({ idef with impl_methods = methods' }, sp)

  | DProtocol _ | DSig _ | DExtern _ | DUse _ | DAlias _ | DNeeds _ ->
    d

  | DDeriving _ ->
    (* DDeriving is expanded by desugar_module before desugar_decl is called *)
    d

  | DTest (tdef, sp) ->
    DTest ({ tdef with test_body = desugar_expr tdef.test_body }, sp)

  | DDescribe (name, decls, sp) ->
    DDescribe (name, List.map desugar_decl decls, sp)

  | DSetup (body, sp) ->
    DSetup (desugar_expr body, sp)

  | DSetupAll (body, sp) ->
    DSetupAll (desugar_expr body, sp)

  | DApp (adef, sp) ->
    (* Desugar: DApp → private __app_init__ function that returns a record
       { spec, on_start, on_stop }.  The interpreter detects __app_init__ in
       the environment and uses it to drive the supervisor lifecycle. *)
    let body' = desugar_expr adef.app_body in
    let on_start' = Option.map desugar_expr adef.app_on_start in
    let on_stop'  = Option.map desugar_expr adef.app_on_stop  in
    (* Build: fn __app_init__() -> { spec = <body>, on_start = <fn>, on_stop = <fn> } *)
    let none_val = ECon ({ txt = "None"; span = sp }, [], sp) in
    let wrap_opt = function
      | None   -> none_val
      | Some e -> ECon ({ txt = "Some"; span = sp }, [ELam ([], e, sp)], sp)
    in
    (* Annotate the spec field so the type checker verifies the body
       returns SupervisorSpec, rather than silently accepting any type. *)
    let spec_ty = TyCon ({ txt = "SupervisorSpec"; span = sp }, []) in
    let annotated_body = EAnnot (body', spec_ty, sp) in
    let result_expr = ERecord (
      [ ({ txt = "spec";     span = sp }, annotated_body)
      ; ({ txt = "on_start"; span = sp }, wrap_opt on_start')
      ; ({ txt = "on_stop";  span = sp }, wrap_opt on_stop')
      ], sp) in
    let init_fn : fn_def = {
      fn_name    = { txt = "__app_init__"; span = sp };
      fn_vis     = Private;
      fn_doc     = None;
      fn_ret_ty  = None;
      fn_clauses = [{
        fc_params = [];
        fc_guard  = None;
        fc_body   = result_expr;
        fc_span   = sp;
      }];
    } in
    DFn (init_fn, sp)

(* ---- Module entry point ---- *)

(** Collect interface definitions from a declaration list (one level deep). *)
let collect_interfaces (decls : decl list) : (string * interface_def) list =
  List.filter_map (function
    | DInterface (idef, _) -> Some (idef.iface_name.txt, idef)
    | _ -> None
  ) decls

(** Inject default methods from the interface into an impl that omits them. *)
let inject_defaults (interfaces : (string * interface_def) list) (d : decl) : decl =
  match d with
  | DImpl (idef, sp) ->
    (match List.assoc_opt idef.impl_iface.txt interfaces with
     | None -> d
     | Some iface ->
       let provided_names = List.map (fun (n, _) -> n.txt) idef.impl_methods in
       let extra_methods = List.filter_map (fun (m : method_decl) ->
           if List.mem m.md_name.txt provided_names then None
           else match m.md_default with
             | None -> None
             | Some default_expr ->
               (* Synthesise a fn_def for the default: fn method_name = default_expr
                  The default body is a value of the method type (often a lambda),
                  so wrap it in a zero-param clause. *)
               let fn_def : fn_def = {
                 fn_name = m.md_name;
                 fn_vis = Private;
                 fn_doc = None;
                 fn_ret_ty = None;
                 fn_clauses = [{
                   fc_params = [];
                   fc_guard = None;
                   fc_body = desugar_expr default_expr;
                   fc_span = m.md_name.span;
                 }];
               } in
               Some (m.md_name, fn_def)
         ) iface.iface_methods
       in
       if extra_methods = [] then d
       else DImpl ({ idef with impl_methods = idef.impl_methods @ extra_methods }, sp))
  | _ -> d

(* ── Derive expansion ──────────────────────────────────────────────────── *)

(** Collect DType definitions: name → (type_params, type_def). *)
let collect_type_defs (decls : decl list) : (string * (name list * type_def)) list =
  List.filter_map (function
    | DType (_, name, tparams, td, _) -> Some (name.txt, (tparams, td))
    | _ -> None
  ) decls

(** Make a name with a dummy span. *)
let mk_name txt = { txt; span = dummy_span }

(** Make a single-clause fn_def with named params and a body expression. *)
let mk_fn_def name params body : fn_def =
  { fn_name   = mk_name name;
    fn_vis     = Private;
    fn_doc     = None;
    fn_ret_ty  = None;
    fn_clauses = [{
      fc_params = List.map (fun p ->
        FPNamed { param_name = mk_name p; param_ty = None; param_lin = Unrestricted }
      ) params;
      fc_guard  = None;
      fc_body   = body;
      fc_span   = dummy_span;
    }] }

(** Build a [DImpl] for one derived interface on [type_name]. *)
let derive_impl (type_name : name) (sp : span)
    (iface : string) (tparams : name list) (td : type_def) : decl option =
  (* Type annotation for the type being implemented *)
  let self_ty : ty =
    if tparams = [] then TyCon (type_name, [])
    else TyCon (type_name, List.map (fun tp -> TyVar tp) tparams)
  in
  (* Helper: build an impl_def with a single method *)
  let impl_one meth_name fn_body_params fn_body =
    let fn_def = mk_fn_def meth_name fn_body_params fn_body in
    let idef : impl_def = {
      impl_iface       = mk_name iface;
      impl_ty          = self_ty;
      impl_constraints = [];
      impl_assoc_types = [];
      impl_methods     = [(mk_name meth_name, fn_def)];
    } in
    DImpl (idef, sp)
  in
  match iface with
  | "Eq" ->
    (* derive Eq: structural comparison using == on each field/variant.
       For variant types: match on pairs of constructors.
       For records: compare field-by-field.
       For aliases: delegate to the aliased type. *)
    let body = match td with
      | TDVariant variants ->
        (* match (a, b) with | (CtorA(args...), CtorA(args...)) -> all args eq | _ -> false *)
        let pair = ETuple ([EVar (mk_name "a"); EVar (mk_name "b")], dummy_span) in
        let branches = List.mapi (fun _i (v : variant) ->
            let n = List.length v.var_args in
            if n = 0 then
              (* no-arg ctor: Red, Red -> true *)
              { branch_pat = PatTuple (
                    [PatCon (v.var_name, []); PatCon (v.var_name, [])], dummy_span);
                branch_guard = None;
                branch_body  = ELit (LitBool true, dummy_span) }
            else begin
              (* ctor with args: Wrap(a0), Wrap(b0) -> a0 == b0 && ... *)
              let avar_names = List.init n (fun i -> Printf.sprintf "_da%d" i) in
              let bvar_names = List.init n (fun i -> Printf.sprintf "_db%d" i) in
              let pats_a = List.map (fun s -> PatVar (mk_name s)) avar_names in
              let pats_b = List.map (fun s -> PatVar (mk_name s)) bvar_names in
              let eq_exprs = List.map2 (fun sa sb ->
                  EApp (EVar (mk_name "=="),
                        [EVar (mk_name sa); EVar (mk_name sb)],
                        dummy_span)
                ) avar_names bvar_names in
              let body_expr = List.fold_right (fun eq_e acc ->
                  EApp (EVar (mk_name "&&"), [eq_e; acc], dummy_span)
                ) (List.rev (List.tl (List.rev eq_exprs)))
                  (List.nth eq_exprs (List.length eq_exprs - 1))
              in
              { branch_pat = PatTuple (
                    [PatCon (v.var_name, pats_a); PatCon (v.var_name, pats_b)], dummy_span);
                branch_guard = None;
                branch_body  = body_expr }
            end
          ) variants
        in
        (* wildcard arm: _ -> false *)
        let wild_branch = {
          branch_pat  = PatWild dummy_span;
          branch_guard = None;
          branch_body  = ELit (LitBool false, dummy_span);
        } in
        EMatch (pair, branches @ [wild_branch], dummy_span)
      | TDRecord fields ->
        (* compare each field: a.f == b.f && a.g == b.g && ... *)
        (match fields with
         | [] -> ELit (LitBool true, dummy_span)
         | [f] ->
           EApp (EVar (mk_name "=="),
                 [EField (EVar (mk_name "a"), f.fld_name, dummy_span);
                  EField (EVar (mk_name "b"), f.fld_name, dummy_span)],
                 dummy_span)
         | f :: rest ->
           let field_eq fld =
             EApp (EVar (mk_name "=="),
                   [EField (EVar (mk_name "a"), fld.fld_name, dummy_span);
                    EField (EVar (mk_name "b"), fld.fld_name, dummy_span)],
                   dummy_span)
           in
           List.fold_left (fun acc fld ->
               EApp (EVar (mk_name "&&"), [acc; field_eq fld], dummy_span)
             ) (field_eq f) rest)
      | TDAlias _ ->
        (* Delegate to the underlying type's eq *)
        EApp (EVar (mk_name "=="), [EVar (mk_name "a"); EVar (mk_name "b")], dummy_span)
    in
    Some (impl_one "eq" ["a"; "b"] body)

  | "Show" ->
    let body = match td with
      | TDVariant variants ->
        let branches = List.map (fun (v : variant) ->
            let n = List.length v.var_args in
            if n = 0 then
              { branch_pat  = PatCon (v.var_name, []);
                branch_guard = None;
                branch_body  = ELit (LitString v.var_name.txt, dummy_span) }
            else begin
              let arg_names = List.init n (fun i -> Printf.sprintf "_sv%d" i) in
              let pats = List.map (fun s -> PatVar (mk_name s)) arg_names in
              (* "Ctor(" ++ show(a0) ++ ", " ++ show(a1) ++ ... ++ ")" *)
              let parts = List.mapi (fun i s ->
                  let show_e = EApp (EVar (mk_name "show"), [EVar (mk_name s)], dummy_span) in
                  if i = 0 then show_e
                  else EApp (EVar (mk_name "++"),
                             [ELit (LitString ", ", dummy_span); show_e],
                             dummy_span)
                ) arg_names
              in
              let inner = List.fold_left (fun acc p ->
                  EApp (EVar (mk_name "++"), [acc; p], dummy_span)
                ) (ELit (LitString (v.var_name.txt ^ "("), dummy_span)) parts
              in
              let full = EApp (EVar (mk_name "++"),
                               [inner; ELit (LitString ")", dummy_span)],
                               dummy_span)
              in
              { branch_pat  = PatCon (v.var_name, pats);
                branch_guard = None;
                branch_body  = full }
            end
          ) variants
        in
        EMatch (EVar (mk_name "x"), branches, dummy_span)
      | TDRecord fields ->
        (* "TypeName { f1 = " ++ show(x.f1) ++ ", f2 = " ++ show(x.f2) ++ " }" *)
        let field_strs = List.mapi (fun i f ->
            let prefix = if i = 0 then f.fld_name.txt ^ " = " else ", " ^ f.fld_name.txt ^ " = " in
            let show_e = EApp (EVar (mk_name "show"),
                               [EField (EVar (mk_name "x"), f.fld_name, dummy_span)],
                               dummy_span)
            in
            EApp (EVar (mk_name "++"),
                  [ELit (LitString prefix, dummy_span); show_e],
                  dummy_span)
          ) fields
        in
        let header = ELit (LitString (type_name.txt ^ " { "), dummy_span) in
        let mid = List.fold_left (fun acc e ->
            EApp (EVar (mk_name "++"), [acc; e], dummy_span)
          ) header field_strs
        in
        EApp (EVar (mk_name "++"), [mid; ELit (LitString " }", dummy_span)], dummy_span)
      | TDAlias _ ->
        EApp (EVar (mk_name "show"), [EVar (mk_name "x")], dummy_span)
    in
    Some (impl_one "show" ["x"] body)

  | "Hash" ->
    (* Avoid calling hash() recursively (check_fn shadows the polymorphic binding).
       For variants: return the constructor index directly (stable hash).
       For records: use int_hash(field) via the builtin int hashing path. *)
    let body = match td with
      | TDVariant variants ->
        let branches = List.mapi (fun i (v : variant) ->
            let n = List.length v.var_args in
            let pats = List.init n (fun _ -> PatWild dummy_span) in
            { branch_pat  = PatCon (v.var_name, pats);
              branch_guard = None;
              branch_body  = ELit (LitInt i, dummy_span) }
          ) variants
        in
        EMatch (EVar (mk_name "x"), branches, dummy_span)
      | TDRecord fields ->
        (match fields with
         | [] -> ELit (LitInt 0, dummy_span)
         | fields ->
           (* Combine field hashes: fold over fields, mixing with prime *)
           let hash_field fld =
             (* Use the polymorphic hash for each field's value.
                Note: field values may be any type — hash is safe here since
                it's called on field values, not on x: Color. *)
             EApp (EVar (mk_name "hash"),
                   [EField (EVar (mk_name "x"), fld.fld_name, dummy_span)],
                   dummy_span)
           in
           (match fields with
            | [] -> ELit (LitInt 0, dummy_span)
            | [f] -> hash_field f
            | f :: rest ->
              List.fold_left (fun acc fld ->
                  EApp (EVar (mk_name "+"),
                        [EApp (EVar (mk_name "*"), [acc; ELit (LitInt 31, dummy_span)], dummy_span);
                         hash_field fld],
                        dummy_span)
                ) (hash_field f) rest))
      | TDAlias _ ->
        EApp (EVar (mk_name "hash"), [EVar (mk_name "x")], dummy_span)
    in
    Some (impl_one "hash" ["x"] body)

  | "Ord" ->
    (* derive Ord: compare constructors by their declaration index.
       For records: compare field by field lexicographically. *)
    let body = match td with
      | TDVariant variants ->
        (* fn compare(a, b) -> compare(ctor_index(a), ctor_index(b)) *)
        let index_of_branches var_name_for arg_count =
          List.mapi (fun i (v : variant) ->
              let n = List.length v.var_args in
              let pats = List.init n (fun _ -> PatWild dummy_span) in
              { branch_pat  = PatCon (v.var_name, pats);
                branch_guard = None;
                branch_body  = ELit (LitInt i, dummy_span) }
            ) variants
          |> (fun branches ->
               EMatch (EVar (mk_name var_name_for), branches, dummy_span))
          |> (fun e -> ignore arg_count; e)
        in
        let ai = index_of_branches "a" (List.length variants) in
        let bi = index_of_branches "b" (List.length variants) in
        (* let _ai = ...; let _bi = ...; compare(_ai, _bi) *)
        EBlock ([
          ELet ({ bind_pat = PatVar (mk_name "_oi_a"); bind_ty = None;
                  bind_lin = Unrestricted; bind_expr = ai }, dummy_span);
          ELet ({ bind_pat = PatVar (mk_name "_oi_b"); bind_ty = None;
                  bind_lin = Unrestricted; bind_expr = bi }, dummy_span);
          EApp (EVar (mk_name "-"),
                [EVar (mk_name "_oi_a"); EVar (mk_name "_oi_b")],
                dummy_span);
        ], dummy_span)
      | TDRecord fields ->
        (* Compare field by field; return first non-zero *)
        (match fields with
         | [] -> ELit (LitInt 0, dummy_span)
         | [f] ->
           EApp (EVar (mk_name "compare"),
                 [EField (EVar (mk_name "a"), f.fld_name, dummy_span);
                  EField (EVar (mk_name "b"), f.fld_name, dummy_span)],
                 dummy_span)
         | fields ->
           let stmts = List.mapi (fun i f ->
               let cmp_e =
                 EApp (EVar (mk_name "compare"),
                       [EField (EVar (mk_name "a"), f.fld_name, dummy_span);
                        EField (EVar (mk_name "b"), f.fld_name, dummy_span)],
                       dummy_span)
               in
               let name = Printf.sprintf "_cmp%d" i in
               ELet ({ bind_pat = PatVar (mk_name name); bind_ty = None;
                       bind_lin = Unrestricted; bind_expr = cmp_e }, dummy_span)
             ) fields
           in
           let final_cmp name i =
             if i = List.length fields - 1 then EVar (mk_name name)
             else
               EIf (EApp (EVar (mk_name "!="),
                          [EVar (mk_name name); ELit (LitInt 0, dummy_span)],
                          dummy_span),
                    EVar (mk_name name),
                    EVar (mk_name (Printf.sprintf "_cmp%d" (i + 1))),
                    dummy_span)
           in
           let last_name = Printf.sprintf "_cmp%d" (List.length fields - 1) in
           let result =
             List.fold_right (fun (i, f) acc ->
                 ignore f;
                 let cname = Printf.sprintf "_cmp%d" i in
                 if i = List.length fields - 1 then EVar (mk_name last_name)
                 else
                   EIf (EApp (EVar (mk_name "!="),
                              [EVar (mk_name cname); ELit (LitInt 0, dummy_span)],
                              dummy_span),
                        EVar (mk_name cname),
                        acc,
                        dummy_span)
               ) (List.mapi (fun i f -> (i, f)) fields |> List.rev |> List.tl |> List.rev)
               (EVar (mk_name last_name))
           in
           ignore result;
           ignore final_cmp;
           EBlock (stmts @ [
             List.fold_right (fun (i, _f) acc ->
                 let cname = Printf.sprintf "_cmp%d" i in
                 if i = List.length fields - 1 then EVar (mk_name cname)
                 else EIf (EApp (EVar (mk_name "!="),
                                 [EVar (mk_name cname); ELit (LitInt 0, dummy_span)],
                                 dummy_span),
                           EVar (mk_name cname), acc, dummy_span)
               ) (List.mapi (fun i f -> (i, f)) fields |> List.rev) (ELit (LitInt 0, dummy_span))
           ], dummy_span))
      | TDAlias _ ->
        EApp (EVar (mk_name "compare"), [EVar (mk_name "a"); EVar (mk_name "b")], dummy_span)
    in
    Some (impl_one "compare" ["a"; "b"] body)

  | _ -> None  (* Unknown interface — silently skip *)

(** Expand a [DDeriving] into zero or more [DImpl] blocks.
    If the type is not found or an interface is unknown, silently skips. *)
let expand_derive
    (type_defs : (string * (name list * type_def)) list)
    (type_name : name)
    (ifaces : name list)
    (sp : span)
  : decl list =
  match List.assoc_opt type_name.txt type_defs with
  | None -> []   (* type not found — silently skip *)
  | Some (tparams, td) ->
    List.filter_map (fun iface_name ->
        derive_impl type_name sp iface_name.txt tparams td
      ) ifaces

(** Check mutual exclusivity of [main] and [app] declarations.
    Returns an error message if both are present. *)
let check_app_main_exclusivity (decls : decl list) : unit =
  let has_main = List.exists (function
      | DFn (def, _) when def.fn_name.txt = "main" -> true
      | _ -> false
    ) decls in
  let has_app = List.exists (function
      | DApp _ -> true
      | _ -> false
    ) decls in
  if has_main && has_app then
    failwith "A module cannot define both main() and an app declaration"

(** Desugar an entire module.  Returns a new [module_] with all multi-head
    fns and pipe expressions lowered to their core forms.
    Also injects default interface method bodies into impls that omit them.
    [DDeriving] nodes are expanded into [DImpl] blocks here. *)
let desugar_module (m : module_) : module_ =
  check_app_main_exclusivity m.mod_decls;
  (* Collect type definitions so derive expansion can reference them. *)
  let type_defs = collect_type_defs m.mod_decls in
  (* Expand DDeriving nodes and desugar everything else. *)
  let expanded = List.concat_map (fun d ->
      match d with
      | DDeriving (type_name, ifaces, sp) ->
        expand_derive type_defs type_name ifaces sp
      | _ -> [d]
    ) m.mod_decls in
  let interfaces = collect_interfaces expanded in
  let decls = List.map (fun d ->
      inject_defaults interfaces (desugar_decl d)
    ) expanded in
  { m with mod_decls = decls }
