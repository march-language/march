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
    EApp (desugar_expr f, List.map desugar_expr args, sp)

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
       flatten it into a single qualified EVar. *)
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
       EVar { txt = prefix ^ "." ^ name.txt; span = sp }
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

    (* Build the merged body: match (arg0, …, argN) with … end *)
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

  | DLet (b, sp) ->
    DLet ({ b with bind_expr = desugar_expr b.bind_expr }, sp)

  | DType _ ->
    (* Type declarations have no expressions to desugar. *)
    d

  | DActor (name, actor, sp) ->
    let init'     = desugar_expr actor.actor_init in
    let handlers' = List.map (fun h ->
        { h with ah_body = desugar_expr h.ah_body }) actor.actor_handlers in
    DActor (name, { actor with actor_init = init'; actor_handlers = handlers' }, sp)

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
    let result_expr = ERecord (
      [ ({ txt = "spec";     span = sp }, body')
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
    Also injects default interface method bodies into impls that omit them. *)
let desugar_module (m : module_) : module_ =
  check_app_main_exclusivity m.mod_decls;
  let interfaces = collect_interfaces m.mod_decls in
  let decls = List.map (fun d ->
      inject_defaults interfaces (desugar_decl d)
    ) m.mod_decls in
  { m with mod_decls = decls }
