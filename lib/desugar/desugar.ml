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

(* ---- HTML IOList generation for ~H sigil ---- *)

(** Decompose a [++] chain into a flat list of parts.

    The parser builds interpolations as:
      "prefix" ++ to_string(e1) ++ "mid" ++ to_string(e2) ++ "suffix"
    represented as nested [EApp(EVar "++", [left; right], sp)].

    We recursively flatten both sides of [++] into a list. *)
let rec decompose_concat (e : expr) : expr list =
  match e with
  | EApp (EVar { txt = "++"; _ }, [left; right], _sp) ->
    decompose_concat left @ decompose_concat right
  | _ -> [e]

(* ── Island tag parsing in ~H ──────────────────────────────────────────── *)

(** Try to extract the value of an attribute (name='value' or name="value")
    from a raw HTML-like string.  Returns [Some value] or [None]. *)
let extract_attr (attr_name : string) (s : string) : string option =
  let pat_sq = attr_name ^ "='" in
  let pat_dq = attr_name ^ "=\"" in
  let try_quote pat close_char =
    match String.split_on_char pat.[0] s with
    | _ ->
      (* Simple substring search *)
      let plen = String.length pat in
      let slen = String.length s in
      let rec scan i =
        if i + plen > slen then None
        else if String.sub s i plen = pat then begin
          let start = i + plen in
          let rec find_end j =
            if j >= slen then None
            else if s.[j] = close_char then
              Some (String.sub s start (j - start))
            else find_end (j + 1)
          in
          find_end start
        end
        else scan (i + 1)
      in
      scan 0
  in
  match try_quote pat_sq '\'' with
  | Some _ as r -> r
  | None -> try_quote pat_dq '"'

(** Check if a string literal starts an island tag: [<island ...].
    Returns the module name if found, and whether the tag is self-closing
    within this literal (i.e. contains [/>]). *)
let detect_island_start (s : string) : string option =
  let trimmed = String.trim s in
  if String.length trimmed >= 7 &&
     String.sub trimmed 0 7 = "<island" then
    extract_attr "name" trimmed
  else
    None

(** Check if a string contains the self-closing end of an island tag [/>]. *)
let has_island_close (s : string) : bool =
  let len = String.length s in
  let rec scan i =
    if i + 1 >= len then false
    else if s.[i] = '/' && s.[i+1] = '>' then true
    else scan (i + 1)
  in
  scan 0

(** Process a list of parts from an ~H sigil, replacing <island> tags with
    calls to [IslandView.island_ssr].

    Recognises:
      ~H"<island name='Counter' />                  — no props
      ~H"<island name='Counter' props=${expr} />     — with props

    Desugars to:
      IslandView.island_ssr(name, Json.to_string(to_json(Mod.init(props))),
                            IOList.to_string(Mod.render(Mod.init(props))))

    When no props are given, uses the record literal [{}] as a dummy.
    The props expression comes from the next interpolated part after the
    opening string that contains [props=]. *)
let process_island_tags (parts : expr list) (sp : span) : expr list =
  let v s = EVar { txt = s; span = sp } in
  let app f args = EApp (v f, args, sp) in
  let rec go acc = function
    | [] -> List.rev acc
    (* String literal that contains an island tag *)
    | ELit (LitString s, lsp) :: rest when detect_island_start s <> None ->
      let module_name = match detect_island_start s with
        | Some n -> n | None -> assert false in
      (* Determine if props= appears in the string.  If so, the next
         interpolated part is the props expression. *)
      let has_props =
        let len = String.length s in
        let rec scan i =
          if i + 6 > len then false
          else if String.sub s i 6 = "props=" then true
          else scan (i + 1)
        in
        scan 0
      in
      if has_props then begin
        (* Expect: EApp(to_string, [props_expr]) :: ELit(" />") :: rest' *)
        match rest with
        | EApp (EVar { txt = "to_string"; _ }, [props_expr], _) :: tail ->
          (* Skip the closing " />" literal if present *)
          let rest' = match tail with
            | ELit (LitString closing, _) :: r when has_island_close closing -> r
            | _ -> tail
          in
          let init_call = app (module_name ^ ".create") [props_expr] in
          let state_json = app "Json.to_string" [app "to_json" [init_call]] in
          let render_call = app "IOList.to_string" [
            app (module_name ^ ".render") [
              app (module_name ^ ".create") [props_expr]
            ]
          ] in
          let island_expr =
            app "IslandView.island_ssr" [
              ELit (LitString module_name, sp);
              state_json;
              render_call
            ]
          in
          go (island_expr :: acc) rest'
        | _ ->
          (* Malformed — treat as a no-props island *)
          let island_expr = app "IslandView.island" [
            ELit (LitString module_name, sp);
            ELit (LitString "{}", lsp)
          ] in
          go (island_expr :: acc) rest
      end
      else begin
        (* No props — skip to closing /> *)
        let rest' = if has_island_close s then rest
          else match rest with
            | ELit (LitString closing, _) :: r when has_island_close closing -> r
            | _ -> rest
        in
        let island_expr = app "IslandView.island" [
          ELit (LitString module_name, sp);
          ELit (LitString "{}", lsp)
        ] in
        go (island_expr :: acc) rest'
      end
    | part :: rest ->
      go (part :: acc) rest
  in
  go [] parts

(** Build an IOList directly from the parts of an ~H sigil interpolation.

    Static string literals are kept as-is.  Dynamic parts (to_string calls)
    are wrapped in Html.escape for auto-escaping.

    Island tags ([<island name='Mod' props=${expr} />]) are recognised and
    replaced with [IslandView.island_ssr(...)] calls that perform SSR.

    The result is:
      IOList.from_strings(["static1", Html.escape(to_string(e1)), "static2", ...])
    which produces a multi-segment IOList without building an intermediate
    concatenated string. *)
let html_interp_to_iolist (content : expr) (sp : span) : expr =
  let parts = decompose_concat content in
  (* First pass: replace <island> tags with IslandView calls *)
  let parts = process_island_tags parts sp in
  (* Second pass: escape dynamic interpolations.
     Use html_auto_escape(x) instead of Html.escape(to_string(x)) so that:
     - Html.Safe values are inserted verbatim (no double-escaping)
     - IOList values (partials) are flattened as-is (already HTML)
     - Plain strings and other values are HTML-escaped normally *)
  let parts = List.map (fun part ->
    match part with
    | EApp (EVar { txt = "to_string"; _ }, [inner_expr], psp) ->
      (* Dynamic part: use html_auto_escape(x) — handles Safe/IOList/String *)
      EApp (EVar { txt = "html_auto_escape"; span = psp }, [inner_expr], psp)
    | EApp (EVar { txt = "to_string"; _ }, args, psp) ->
      (* Fallback for unusual arity — shouldn't happen in practice *)
      let inner = EApp (EVar { txt = "to_string"; span = psp }, args, psp) in
      EApp (EVar { txt = "html_auto_escape"; span = psp }, [inner], psp)
    | _ -> part  (* String literals and island_ssr calls — leave as-is *)
  ) parts in
  let list_expr = List.fold_right (fun e acc ->
    ECon ({ txt = "Cons"; span = sp }, [e; acc], sp)
  ) parts (ECon ({ txt = "Nil"; span = sp }, [], sp)) in
  EApp (EVar { txt = "IOList.from_strings"; span = sp }, [list_expr], sp)

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
     | ECond (arms, cond_sp) ->
       (* x |> match do Pat -> body end  ⟶  match x do Pat -> body end
          Convert cond-arm exprs to patterns for the LHS scrutinee. *)
       let rec expr_to_pat e = match e with
         | ECon (name, args, _) -> PatCon (name, List.map expr_to_pat args)
         | EVar name -> PatVar name
         | ELit (lit, litsp) -> PatLit (lit, litsp)
         | EAtom (a, args, epsp) -> PatAtom (a, List.map expr_to_pat args, epsp)
         | ETuple (es, epsp) -> PatTuple (List.map expr_to_pat es, epsp)
         | _ -> failwith ("pipe-to-match: cannot convert to pattern: " ^ show_expr e)
       in
       let branches = List.map (fun (cond_e, body) ->
           { branch_pat = expr_to_pat cond_e
           ; branch_guard = None
           ; branch_body = body }) arms in
       EMatch (l', branches, cond_sp)
     | EMatch (_, branches, match_sp) ->
       (* x |> match scrutinee do ... end where scrutinee may be a hole;
          but more importantly: x |> match do ... end with pattern branches *)
       EMatch (l', branches, match_sp)
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

  | ECond (arms, sp) ->
    ECond (List.map (fun (cond_e, body) -> (desugar_expr cond_e, desugar_expr body)) arms, sp)

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

  | ESigil (c, content, sp) ->
    let content' = desugar_expr content in
    if c = 'H' then
      (* Desugar ~H"..." → IOList.from_strings([parts...])
         Decompose the ++ chain into segments, wrap dynamic parts in
         Html.escape, and build a multi-segment IOList directly. *)
      html_interp_to_iolist content' sp
    else begin
      (* Other sigils: ~R"..." → Sigil.r(content), etc. *)
      let fn_name = Printf.sprintf "Sigil.%c" (Char.lowercase_ascii c) in
      EApp (EVar { txt = fn_name; span = sp }, [content'], sp)
    end

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
      fn_attrs   = [];
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
                 fn_attrs = [];
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
    fn_attrs   = [];
    fn_ret_ty  = None;
    fn_clauses = [{
      fc_params = List.map (fun p ->
        FPNamed { param_name = mk_name p; param_ty = None; param_lin = Unrestricted }
      ) params;
      fc_guard  = None;
      fc_body   = body;
      fc_span   = dummy_span;
    }] }

(** Build derived declarations for one interface on [type_name].
    Returns a list of [decl] — usually one [DImpl], but [Json] produces
    two standalone [DFn] declarations (to_json / from_json). *)
let derive_impl (type_name : name) (sp : span)
    (iface : string) (tparams : name list) (td : type_def) : decl list =
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
    [impl_one "eq" ["a"; "b"] body]

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
    [impl_one "show" ["x"] body]

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
    [impl_one "hash" ["x"] body]

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
    [impl_one "compare" ["a"; "b"] body]

  | "Json" ->
    (* derive Json: generate standalone to_json and from_json functions.
       to_json(x : T) : JsonValue   — structural encoding to JSON
       from_json(v : JsonValue) : Result(T, String) — decoding from JSON *)
    let sp = dummy_span in
    (* Helper: encode a field value based on its type annotation *)
    let encoder_for_ty (ty : ty) (value_expr : expr) : expr =
      match ty with
      | TyCon ({txt = "String"; _}, []) ->
        EApp (EVar (mk_name "Json.encode_string"), [value_expr], sp)
      | TyCon ({txt = "Int"; _}, []) ->
        EApp (EVar (mk_name "Json.encode_int"), [value_expr], sp)
      | TyCon ({txt = "Float"; _}, []) ->
        EApp (EVar (mk_name "Json.encode_number"), [value_expr], sp)
      | TyCon ({txt = "Bool"; _}, []) ->
        EApp (EVar (mk_name "Json.encode_bool"), [value_expr], sp)
      | _ ->
        (* Assume nested type also derives Json — call to_json recursively *)
        EApp (EVar (mk_name "to_json"), [value_expr], sp)
    in
    (* Helper: build a decoder pattern + extraction for a given type.
       Returns (pattern_for_Some_wrapper, expression_to_convert) *)
    let decoder_pat_for_ty (ty : ty) (var_name : string) : pattern * expr =
      match ty with
      | TyCon ({txt = "String"; _}, []) ->
        (PatCon (mk_name "Some", [PatCon (mk_name "Str", [PatVar (mk_name var_name)])]),
         EVar (mk_name var_name))
      | TyCon ({txt = "Int"; _}, []) ->
        (PatCon (mk_name "Some", [PatCon (mk_name "Number", [PatVar (mk_name var_name)])]),
         EApp (EVar (mk_name "float_to_int"), [EVar (mk_name var_name)], sp))
      | TyCon ({txt = "Float"; _}, []) ->
        (PatCon (mk_name "Some", [PatCon (mk_name "Number", [PatVar (mk_name var_name)])]),
         EVar (mk_name var_name))
      | TyCon ({txt = "Bool"; _}, []) ->
        (PatCon (mk_name "Some", [PatCon (mk_name "Bool", [PatVar (mk_name var_name)])]),
         EVar (mk_name var_name))
      | _ ->
        (* For other types, extract raw JsonValue and call from_json *)
        let raw_var = var_name ^ "_raw" in
        (PatCon (mk_name "Some", [PatVar (mk_name raw_var)]),
         (* We'll need a match on from_json result — but for simplicity in the
            pattern approach, just store the raw value and handle in the body *)
         EVar (mk_name raw_var))
    in
    (* ── to_json ────────────────────────────────────────────── *)
    let to_json_body = match td with
      | TDRecord fields ->
        (* Json.encode_object([("f1", encode(x.f1)), ("f2", encode(x.f2)), ...]) *)
        let pair_exprs = List.map (fun (f : field) ->
            let field_access = EField (EVar (mk_name "x"), f.fld_name, sp) in
            let encoded = encoder_for_ty f.fld_ty field_access in
            ETuple ([ELit (LitString f.fld_name.txt, sp); encoded], sp)
          ) fields
        in
        let pairs_list = List.fold_right (fun e acc ->
            ECon (mk_name "Cons", [e; acc], sp)
          ) pair_exprs (ECon (mk_name "Nil", [], sp))
        in
        EApp (EVar (mk_name "Json.encode_object"), [pairs_list], sp)
      | TDVariant variants ->
        (* match x with
           | Ctor0 -> encode_object([("tag", encode_string("Ctor0"))])
           | Ctor1(v0) -> encode_object([("tag", ...), ("0", encode(v0))]) *)
        let branches = List.map (fun (v : variant) ->
            let n = List.length v.var_args in
            let arg_names = List.init n (fun i -> Printf.sprintf "_jv%d" i) in
            let pats = List.map (fun s -> PatVar (mk_name s)) arg_names in
            let tag_pair = ETuple ([
                ELit (LitString "tag", sp);
                EApp (EVar (mk_name "Json.encode_string"),
                      [ELit (LitString v.var_name.txt, sp)], sp)
              ], sp) in
            let arg_pairs = List.mapi (fun i arg_name ->
                let ty = List.nth v.var_args i in
                ETuple ([
                    ELit (LitString (string_of_int i), sp);
                    encoder_for_ty ty (EVar (mk_name arg_name))
                  ], sp)
              ) arg_names
            in
            let all_pairs = tag_pair :: arg_pairs in
            let pairs_list = List.fold_right (fun e acc ->
                ECon (mk_name "Cons", [e; acc], sp)
              ) all_pairs (ECon (mk_name "Nil", [], sp))
            in
            { branch_pat = PatCon (v.var_name, pats);
              branch_guard = None;
              branch_body = EApp (EVar (mk_name "Json.encode_object"), [pairs_list], sp) }
          ) variants
        in
        EMatch (EVar (mk_name "x"), branches, sp)
      | TDAlias _ ->
        EApp (EVar (mk_name "to_json"), [EVar (mk_name "x")], sp)
    in
    (* ── from_json ──────────────────────────────────────────── *)
    let from_json_body = match td with
      | TDRecord fields ->
        (* match (Json.get(v,"f1"), Json.get(v,"f2"), ...) with
           | (Some(Str(f1)), Some(Number(f2)), ...) -> Ok({f1=f1, f2=float_to_int(f2), ...})
           | _ -> Err("invalid JSON for TypeName") *)
        let get_exprs = List.map (fun (f : field) ->
            EApp (EVar (mk_name "Json.get"),
                  [EVar (mk_name "v"); ELit (LitString f.fld_name.txt, sp)], sp)
          ) fields
        in
        let scrutinee = ETuple (get_exprs, sp) in
        let pats_and_convs = List.mapi (fun _i (f : field) ->
            let var_name = Printf.sprintf "_jf%d" _i in
            decoder_pat_for_ty f.fld_ty var_name
          ) fields
        in
        let ok_pats = List.map fst pats_and_convs in
        (* Build the record expression *)
        let record_fields = List.mapi (fun i (f : field) ->
            let (_pat, conv_expr) = List.nth pats_and_convs i in
            (* For non-primitive types we need to call from_json and handle Result *)
            let value_expr = match f.fld_ty with
              | TyCon ({txt = "String"; _}, [])
              | TyCon ({txt = "Int"; _}, [])
              | TyCon ({txt = "Float"; _}, [])
              | TyCon ({txt = "Bool"; _}, []) -> conv_expr
              | _ ->
                (* For complex types, conv_expr is the raw JsonValue var.
                   We need: match from_json(raw) with Ok(v) -> v | Err(e) -> panic(e) *)
                let from_result = EApp (EVar (mk_name "from_json"), [conv_expr], sp) in
                EMatch (from_result, [
                  { branch_pat = PatCon (mk_name "Ok", [PatVar (mk_name (Printf.sprintf "_jfok%d" i))]);
                    branch_guard = None;
                    branch_body = EVar (mk_name (Printf.sprintf "_jfok%d" i)) };
                  { branch_pat = PatCon (mk_name "Err", [PatVar (mk_name "_jfe")]);
                    branch_guard = None;
                    branch_body = EApp (EVar (mk_name "panic"), [EVar (mk_name "_jfe")], sp) };
                ], sp)
            in
            (f.fld_name, value_expr)
          ) fields
        in
        let ok_record = ECon (mk_name "Ok", [ERecord (record_fields, sp)], sp) in
        let err_msg = Printf.sprintf "invalid JSON for %s" type_name.txt in
        let err_branch = {
          branch_pat = PatWild sp;
          branch_guard = None;
          branch_body = ECon (mk_name "Err", [ELit (LitString err_msg, sp)], sp);
        } in
        let ok_branch = {
          branch_pat = PatTuple (ok_pats, sp);
          branch_guard = None;
          branch_body = ok_record;
        } in
        EMatch (scrutinee, [ok_branch; err_branch], sp)
      | TDVariant variants ->
        (* match Json.get(v, "tag") with
           | Some(Str("Ctor0")) -> Ok(Ctor0)
           | Some(Str("Ctor1")) -> match Json.get(v, "0") with ...
           | _ -> Err("invalid JSON for TypeName") *)
        let tag_expr = EApp (EVar (mk_name "Json.get"),
                             [EVar (mk_name "v"); ELit (LitString "tag", sp)], sp)
        in
        let branches = List.map (fun (v : variant) ->
            let n = List.length v.var_args in
            if n = 0 then
              { branch_pat = PatCon (mk_name "Some",
                  [PatCon (mk_name "Str",
                    [PatLit (LitString v.var_name.txt, sp)])]);
                branch_guard = None;
                branch_body = ECon (mk_name "Ok", [ECon (v.var_name, [], sp)], sp) }
            else begin
              (* For variants with args, extract each arg from "0", "1", etc. *)
              let arg_gets = List.init n (fun i ->
                  EApp (EVar (mk_name "Json.get"),
                        [EVar (mk_name "v"); ELit (LitString (string_of_int i), sp)], sp)
                ) in
              let scrutinee2 = if n = 1 then List.hd arg_gets
                               else ETuple (arg_gets, sp) in
              let arg_pats_convs = List.mapi (fun i ty ->
                  let var_name = Printf.sprintf "_ja%d" i in
                  decoder_pat_for_ty ty var_name
                ) v.var_args
              in
              let inner_pats = if n = 1 then [fst (List.hd arg_pats_convs)]
                               else [PatTuple (List.map fst arg_pats_convs, sp)] in
              let ctor_args = List.mapi (fun i ty ->
                  let (_pat, conv_expr) = List.nth arg_pats_convs i in
                  match ty with
                  | TyCon ({txt = "String"; _}, [])
                  | TyCon ({txt = "Int"; _}, [])
                  | TyCon ({txt = "Float"; _}, [])
                  | TyCon ({txt = "Bool"; _}, []) -> conv_expr
                  | _ ->
                    let from_result = EApp (EVar (mk_name "from_json"), [conv_expr], sp) in
                    EMatch (from_result, [
                      { branch_pat = PatCon (mk_name "Ok", [PatVar (mk_name (Printf.sprintf "_jaok%d" i))]);
                        branch_guard = None;
                        branch_body = EVar (mk_name (Printf.sprintf "_jaok%d" i)) };
                      { branch_pat = PatCon (mk_name "Err", [PatVar (mk_name "_jae")]);
                        branch_guard = None;
                        branch_body = EApp (EVar (mk_name "panic"), [EVar (mk_name "_jae")], sp) };
                    ], sp)
                ) v.var_args
              in
              let ok_ctor = ECon (mk_name "Ok", [ECon (v.var_name, ctor_args, sp)], sp) in
              let err_msg2 = Printf.sprintf "invalid JSON for %s.%s" type_name.txt v.var_name.txt in
              let inner_branches =
                [{ branch_pat = List.hd inner_pats; branch_guard = None; branch_body = ok_ctor };
                 { branch_pat = PatWild sp; branch_guard = None;
                   branch_body = ECon (mk_name "Err", [ELit (LitString err_msg2, sp)], sp) }]
              in
              { branch_pat = PatCon (mk_name "Some",
                  [PatCon (mk_name "Str",
                    [PatLit (LitString v.var_name.txt, sp)])]);
                branch_guard = None;
                branch_body = EMatch (scrutinee2, inner_branches, sp) }
            end
          ) variants
        in
        let err_msg = Printf.sprintf "invalid JSON for %s" type_name.txt in
        let wild_branch = {
          branch_pat = PatWild sp;
          branch_guard = None;
          branch_body = ECon (mk_name "Err", [ELit (LitString err_msg, sp)], sp);
        } in
        EMatch (tag_expr, branches @ [wild_branch], sp)
      | TDAlias _ ->
        EApp (EVar (mk_name "from_json"), [EVar (mk_name "v")], sp)
    in
    (* Generate two DImpl blocks with pseudo-interfaces "JsonTo" and "JsonFrom".
       This allows impl_tbl dispatch for variant types, while also binding
       to_json/from_json in the local env for record types. *)
    let to_json_fn = mk_fn_def "to_json" ["x"] to_json_body in
    let from_json_fn = mk_fn_def "from_json" ["v"] from_json_body in
    let mk_json_impl iface_name meth_name fn_body =
      let idef : impl_def = {
        impl_iface       = mk_name iface_name;
        impl_ty          = self_ty;
        impl_constraints = [];
        impl_assoc_types = [];
        impl_methods     = [(mk_name meth_name, fn_body)];
      } in
      DImpl (idef, sp)
    in
    [mk_json_impl "JsonTo" "to_json" to_json_fn;
     mk_json_impl "JsonFrom" "from_json" from_json_fn]

  | _ -> []  (* Unknown interface — silently skip *)

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
    List.concat_map (fun iface_name ->
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

(* ── Island bridge auto-generation ─────────────────────────────────────── *)

(** Check if the original declarations include [DDeriving(type_name, ...Json...)]
    for a given type name. *)
let has_json_derive (type_name_str : string) (decls : decl list) : bool =
  List.exists (function
    | DDeriving (tn, ifaces, _) ->
      tn.txt = type_name_str &&
      List.exists (fun (i : name) -> i.txt = "Json") ifaces
    | _ -> false
  ) decls

(** Check if a DFn with the given name exists in the declaration list. *)
let has_fn_named (fn_name_str : string) (decls : decl list) : bool =
  List.exists (function
    | DFn (def, _) -> def.fn_name.txt = fn_name_str
    | _ -> false
  ) decls

(** Generate [update_json] and [render_json] bridge functions for an island
    module that has State and Msg types with [derive Json], plus [update]
    and [render] functions.

    The generated code uses the polymorphic [from_json]/[to_json] builtins
    which dispatch via impl_tbl at runtime.  Because the generated call sites
    feed their results into [update(state, msg)], the typechecker infers the
    correct concrete types for each [from_json] call. *)
let gen_island_bridges (sp : span) : decl list =
  let v s = EVar { txt = s; span = sp } in
  let app f args = EApp (v f, args, sp) in
  let pat_var s = PatVar (mk_name s) in
  let pat_con c args = PatCon (mk_name c, args) in
  let wild = PatWild sp in
  let br pat body = { branch_pat = pat; branch_guard = None; branch_body = body } in
  let mk_pub_fn name params body : fn_def =
    { fn_name   = mk_name name;
      fn_vis    = Public;
      fn_doc    = None;
      fn_attrs  = [];
      fn_ret_ty = None;
      fn_clauses = [{
        fc_params = List.map (fun p ->
          FPNamed { param_name = mk_name p; param_ty = None; param_lin = Unrestricted }
        ) params;
        fc_guard  = None;
        fc_body   = body;
        fc_span   = sp;
      }] }
  in
  (* update_json(state_json, msg_json) : String
       match (Json.parse(state_json), Json.parse(msg_json)) do
       (Ok(sjv), Ok(mjv)) ->
         match (from_json(sjv), from_json(mjv)) do
         (Ok(state), Ok(msg)) ->
           Json.to_string(to_json(update(state, msg)))
         _ -> state_json
         end
       _ -> state_json
       end *)
  let update_body =
    let outer_scrut = ETuple ([
      app "Json.parse" [v "state_json"];
      app "Json.parse" [v "msg_json"]
    ], sp) in
    let inner_scrut = ETuple ([
      app "from_json" [v "sjv"];
      app "from_json" [v "mjv"]
    ], sp) in
    let success =
      app "Json.to_string" [
        app "to_json" [
          app "update" [v "state"; v "msg"]
        ]
      ]
    in
    let inner_match = EMatch (inner_scrut, [
      br (PatTuple ([pat_con "Ok" [pat_var "state"];
                     pat_con "Ok" [pat_var "msg"]], sp)) success;
      br wild (v "state_json")
    ], sp) in
    EMatch (outer_scrut, [
      br (PatTuple ([pat_con "Ok" [pat_var "sjv"];
                     pat_con "Ok" [pat_var "mjv"]], sp)) inner_match;
      br wild (v "state_json")
    ], sp)
  in
  (* render_json(state_json) : String
       match Json.parse(state_json) do
       Ok(sjv) ->
         match from_json(sjv) do
         Ok(state) -> IOList.to_string(render(state))
         _ -> ""
         end
       _ -> ""
       end *)
  let render_body =
    let inner_match = EMatch (app "from_json" [v "sjv"], [
      br (pat_con "Ok" [pat_var "state"])
        (app "IOList.to_string" [app "render" [v "state"]]);
      br wild (ELit (LitString "", sp))
    ], sp) in
    EMatch (app "Json.parse" [v "state_json"], [
      br (pat_con "Ok" [pat_var "sjv"]) inner_match;
      br wild (ELit (LitString "", sp))
    ], sp)
  in
  let uf = mk_pub_fn "update_json" ["state_json"; "msg_json"] update_body in
  let rf = mk_pub_fn "render_json" ["state_json"] render_body in
  [DFn (uf, sp); DFn (rf, sp)]

(** If this module looks like an island (has State + Msg with derive Json,
    and update + render functions), inject auto-generated bridge functions
    so the user doesn't need to write them manually. *)
let maybe_inject_island_bridges
    (orig_decls : decl list) (expanded : decl list) : decl list =
  let is_island =
    has_json_derive "State" orig_decls &&
    has_json_derive "Msg" orig_decls &&
    has_fn_named "update" expanded &&
    has_fn_named "render" expanded
  in
  if is_island then begin
    (* Only inject if the user hasn't already written their own *)
    let already_has_update_json = has_fn_named "update_json" expanded in
    let already_has_render_json = has_fn_named "render_json" expanded in
    if already_has_update_json || already_has_render_json then expanded
    else
      let sp = match expanded with
        | DFn (_, sp) :: _ -> sp
        | _ -> dummy_span
      in
      expanded @ gen_island_bridges sp
  end
  else expanded

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
  (* Auto-generate island bridge functions if this is an island module. *)
  let expanded = maybe_inject_island_bridges m.mod_decls expanded in
  let interfaces = collect_interfaces expanded in
  let decls = List.map (fun d ->
      inject_defaults interfaces (desugar_decl d)
    ) expanded in
  { m with mod_decls = decls }
