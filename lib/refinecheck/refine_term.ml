(** Termination analysis (specs/2026-10-26-termination-checking-design.md).

    {1 What this pass is, and is not}

    March's tail pass ([Typecheck_tailcall]) checks STACK SAFETY: a recursive
    call in tail position is never examined, and a non-tail one passes if one
    argument is "structurally smaller" by a syntactic heuristic that accepts
    [n - 0] and [n - (0 - 1)] (design F1, F2).  This pass is the separate
    TERMINATION analysis of §3.  It shares nothing with the tail pass's
    [smaller] set or [is_structurally_smaller]: those are never termination
    evidence (§3.1, decision 2).

    Phase 0 is inert measurement:
    - the §3.2 call graph over every unit (a top-level [fn], a local [fn], an
      actor handler), with three edge kinds: a DIRECT call, a call inside a
      lambda or a [let*] continuation (a LAMBDA edge), and a function name
      used as a value (a REFERENCE edge, no arguments);
    - Tarjan SCCs over it;
    - the COUNT classifier of §0.5 (classes A-I, the ones with no syntactic
      metric by heuristic, marked [?]).

    Phase 1 adds, per SCC, a STRUCTURAL CERTIFICATE ([certify], §3.3) and
    strict positivity of data types ([nonpositive_types], §3.6).  Both are
    report-only (decision D2), except that the [@[measure]] gate
    ([Refine_check], via [uncertified]) rejects a measure whose SCC is not
    certified: a diverging measure is an inconsistent axiom.  Nothing feeds
    the induction hypothesis yet (phase 3).

    {1 Name resolution}

    Desugaring rewrites call sites into a different namespace than
    declarations live in ([typecheck_tailcall.ml]'s long comment on
    [enforce_tail_calls_in_decls]), so a name is resolved as follows:
    - a declaration at module path [p] (["" ], ["Inner."], …) of a file
      declaring [file_mod] is registered as [p ^ name] (the entry-file
      convention) and as [file_mod ^ "." ^ p ^ name] (the dependency-file
      convention);
    - a name used in a body at module path [p] is looked up LEXICALLY:
      [p ^ name], then each outer module's prefix, out to the top level.
      The prepended stdlib keeps bare intra-module calls inside its [DMod]s,
      so a top-level-first lookup ties [List.fold_left]'s own recursion to
      an entry file's unrelated top-level [fold_left];
    - a LOCAL binder shadows a global: a function parameter, a [let] / arm /
      lambda / [let?] / [let*] binder, and a local [fn] (which binds its own
      name for the rest of its block and inside its own body).  Without the
      scope, prelude's [length]'s local [go] forges an edge to a user's
      top-level [go].

    Unlike the tail pass, the graph is GLOBAL across nesting levels, so a
    cycle through a nested module is one SCC. *)

module A = March_ast.Ast
module SM = Map.Make (String)
module SS = Set.Make (String)

(* ── The graph ─────────────────────────────────────────────────────────── *)

type unit_kind = Top | Local | Handler

type edge_kind = Direct | Lambda | Reference

(** One clause a call sits in: its parameter names by position ([None] for a
    destructuring parameter) and its body.  The structural certificate reads
    [structural_subvars] over exactly this body. *)
type owner = { o_params : string option list; o_body : A.expr }

type edge = {
  e_src : int;
  e_dst : int;
  e_kind : edge_kind;
  e_args : A.expr list;  (** [] for a [Reference] edge *)
  e_span : A.span;
  e_owner : owner;
  e_shadowed : string list;
      (** the owner clause's parameters REBOUND by an inner binder at this
          call (a `let`, arm, lambda or local `fn` binder of the same name).
          A metric over such a name would read the inner value, not the
          entry value, so the edge cannot be obliged (phase 2). *)
  e_dispatch : bool;
      (** an interface dispatch PICKED BY A VALUE: the callee is one of the
          [impl]s the argument's type can reach, and that type is not known
          here (a type variable, or no type at all), so the [impl] is chosen
          by a dictionary at run time.  A dispatch on a fully known static
          type is resolved where it is written, and is an ordinary edge with
          this [false] (final review, termination phase 5). *)
}

type unit_ = {
  u_id : int;
  u_name : string;  (** display name: [Inner.boom], [h/go3], [Actor.Msg] *)
  u_span : A.span;  (** the declaring name's span: the key across passes *)
  u_kind : unit_kind;
  u_params : string option list;  (** first clause's parameters, by position *)
  u_param_tys : A.ty option list;
  u_param_spans : A.span option list;  (** where the typechecker recorded each parameter's type *)
  u_clauses : owner list;
  u_attrs : string list;
  u_decreases : A.expr list option;  (** the [@[decreases(e, ...)]] payload, if written *)
  u_top : int;  (** the enclosing top-level unit (itself for a top-level unit or a handler) *)
  u_ret : A.ty option;  (** the declared return type (phase 3 reads it for IH demand) *)
}

(** What one callee name, or one function name used as a value, resolved to:
    the [sites] of [graph].  The reflection report ([Refine_reflect]) reads
    them; nothing in the termination analysis does. *)
type site_target =
  | S_unit of int  (** a unit of the graph *)
  | S_impls of int list  (** an interface dispatch to these [impl] / default units *)
  | S_value  (** a local value: a call through a function value *)
  | S_builtin  (** a builtin of the typechecker's table *)
  | S_extern  (** an [extern] *)
  | S_unresolved  (** nothing the pass can name *)

type site = {
  s_src : int;  (** the unit the site sits in *)
  s_name : string;  (** the callee name as written ([""] for a non-name callee) *)
  s_span : A.span;  (** the call expression's span, or the name's for a reference *)
  s_call : bool;  (** a call ([true]) or a function name used as a value *)
  s_args : A.expr list;
  s_target : site_target;
}

type graph = {
  units : unit_ array;
  edges : edge list;  (** every edge, in walk order *)
  out : edge list array;  (** edges by source *)
  scc_of : int array;  (** unit id -> SCC index *)
  sccs : int list array;  (** SCC index -> member ids *)
  trusted : (int * string) list;
      (** (unit, callee name) of every call to a builtin of the typechecker's
          table (with no interface constraint) or an [extern]: trusted to
          terminate (§3.6, decision 10) and counted by the report. *)
  unresolved : (int * string) list;
      (** (unit, name) of every callee or referenced name the pass cannot
          resolve to a unit, a local value, an interface dispatch, a builtin
          or an [extern].  It may diverge: its unit's SCC is not certified
          ([Unproved "unresolved"]) and no SCC reaching it gets the induction
          hypothesis ([calls_unresolved]).  Fail closed (review fixes). *)
  fv_calls : (int * A.expr) list;
      (** (unit, callee expression) of every call through a FUNCTION VALUE: a
          callee bound by a parameter, [let], arm or lambda binder, or any
          callee that is not a name at all.  Positivity (§3.6) reads these. *)
  sites : site list;
      (** every call and every function name used as a value, with what it
          resolved to, in walk order.  Read only by [Refine_reflect]. *)
  pred_sites : (A.span * site_target) list;
      (** every call inside a refinement PREDICATE of a function's signature
          (its parameter and return types, a local [fn]'s too), resolved in the
          scope where the predicate is written: the function's module, its
          parameters and the predicate's binder shadowing.  No edges: a
          predicate is not a call.  Read by reflection (phase 1a review C-1,
          C-2), so a predicate's callee is resolved exactly as program code
          there would be. *)
  ambiguous : (A.span, unit) Hashtbl.t;
      (** call sites (program code and predicates) whose name more than one
          declaration could denote: a key two modules registered (an entry
          module's nested `mod List` and the stdlib's `List`, a library `X`
          and a nested `M.X`), or a lexical name that an [alias] or a [use]
          in scope also supplies.  The walk above still picks one (its
          long-standing behaviour); reflection treats such a site as
          unresolved and never unfolds it (phase 1a review C-A, C-B), since
          the interpreter and the compiled build need not agree with that
          pick. *)
}

let rec pat_vars (p : A.pattern) : string list =
  match p with
  | A.PatVar n -> [ n.A.txt ]
  | A.PatAs (p, n, _) -> n.A.txt :: pat_vars p
  | A.PatCon (_, ps) | A.PatAtom (_, ps, _) | A.PatTuple (ps, _) | A.PatOr (ps, _) ->
    List.concat_map pat_vars ps
  | A.PatRecord (fs, _) -> List.concat_map (fun (_, p) -> pat_vars p) fs
  | A.PatWild _ | A.PatLit _ -> []

(* [Param]: a parameter of the unit whose body is being walked.  It resolves
   like [Var]; it differs only in telling the edge which of the owner's
   parameters still hold their ENTRY value ([e_shadowed]). *)
type binding = Fn of int | Var | Param

let bind_vars env names = List.fold_left (fun env n -> SM.add n Var env) env names

let bind_params env names = List.fold_left (fun env n -> SM.add n Param env) env names

let clause_params (c : A.fn_clause) : string option list * A.ty option list =
  List.split
    (List.map
       (function
         | A.FPNamed p | A.FPDefault (p, _) -> (Some p.A.param_name.A.txt, p.A.param_ty)
         | A.FPPat (A.PatVar n) -> (Some n.A.txt, None)
         | A.FPPat _ -> (None, None))
       c.A.fc_params)

let clause_param_spans (c : A.fn_clause) : A.span option list =
  List.map
    (function
      | A.FPNamed p | A.FPDefault (p, _) -> Some p.A.param_name.A.span
      | A.FPPat (A.PatVar n) -> Some n.A.span
      | A.FPPat _ -> None)
    c.A.fc_params

let clause_binders (c : A.fn_clause) : string list =
  List.concat_map
    (function
      | A.FPNamed p | A.FPDefault (p, _) -> [ p.A.param_name.A.txt ]
      | A.FPPat p -> pat_vars p)
    c.A.fc_params

(* ── Type helpers (shared by the graph's dispatch and §3.6 positivity) ── *)

(* The last dotted segment: types are compared by their bare name, since a
   declaration says `Fix` and a use may say `M.Fix`.  Merging two same-named
   types only ever makes MORE types non-positive, the safe direction. *)
let bare (n : string) : string =
  match String.rindex_opt n '.' with
  | Some i -> String.sub n (i + 1) (String.length n - i - 1)
  | None -> n

type tdecl = { t_params : string list; t_fields : A.ty list }

let collect_types (decls : A.decl list) : (string, tdecl) Hashtbl.t =
  let tbl = Hashtbl.create 64 in
  let add name params (td : A.type_def) =
    let fields =
      match td with
      | A.TDVariant vs -> List.concat_map (fun (v : A.variant) -> v.A.var_args) vs
      | A.TDRecord fs -> List.map (fun (f : A.field) -> f.A.fld_ty) fs
      | A.TDAlias t -> [ t ]
    in
    let prev = match Hashtbl.find_opt tbl name with Some p -> p.t_fields | None -> [] in
    Hashtbl.replace tbl name
      { t_params = List.map (fun (n : A.name) -> n.A.txt) params; t_fields = prev @ fields }
  in
  let rec go decls =
    List.iter
      (function
        | A.DType (_, n, ps, td, _) | A.DAlwaysLinearType (_, n, ps, td, _) -> add n.A.txt ps td
        | A.DMod (_, _, inner, _) -> go inner
        | _ -> ())
      decls
  in
  go decls;
  tbl

let rec ty_cons (t : A.ty) : string list =
  match t with
  | A.TyCon (n, args) -> bare n.A.txt :: List.concat_map ty_cons args
  | A.TyArrow (a, b) -> ty_cons a @ ty_cons b
  | A.TyTuple ts -> List.concat_map ty_cons ts
  | A.TyRecord fs -> List.concat_map (fun (_, t) -> ty_cons t) fs
  | A.TyLinear (_, t) | A.TyRefine (t, _, _) -> ty_cons t
  | A.TyVar _ | A.TyNat _ | A.TyNatOp _ | A.TyChan _ -> []

(** [reaches c t]: type [c]'s definition mentions [t], directly or through
    the definitions of the types it mentions (or [c = t]). *)
let reach_fn (tbl : (string, tdecl) Hashtbl.t) : string -> string -> bool =
  let reach = Hashtbl.create 64 in
  Hashtbl.iter
    (fun n d -> Hashtbl.replace reach n (SS.of_list (List.concat_map ty_cons d.t_fields)))
    tbl;
  (* Transitive closure, to a fixpoint. *)
  let changed = ref true in
  while !changed do
    changed := false;
    Hashtbl.iter
      (fun n s ->
        let s' =
          SS.fold
            (fun m acc -> match Hashtbl.find_opt reach m with Some r -> SS.union acc r | None -> acc)
            s s
        in
        if not (SS.equal s s') then (Hashtbl.replace reach n s'; changed := true))
      (Hashtbl.copy reach)
  done;
  fun c t -> c = t || (match Hashtbl.find_opt reach c with Some r -> SS.mem t r | None -> false)

(* ── Callee resolution: builtins, externs, interface dispatch ───────────── *)

module TT = March_typecheck.Typecheck_types
module TB = March_typecheck.Typecheck_builtins

(** Where a dispatching builtin reads the [impl] it runs from: the static
    type of one argument (by position), or none of them ([from_json] picks
    its decoder by its RESULT type, so every [impl] of the interface is
    reachable). *)
type dispatch_on = Arg of int | Any_impl

(** Builtins that run a user [impl] at run time although their typechecker
    scheme carries NO interface constraint, so [builtin_table] cannot see
    it in the scheme.  Without this table each was trusted, so a diverging
    [impl] it runs was invisible to the graph and the induction hypothesis
    was granted over it (final review, termination phase 5).  The builtins
    whose scheme does carry the constraint (`==`, `!=`, `<`, `<=`, `>`,
    `>=`, [eq], [compare], [show], [hash] and their qualified forms) are
    read from the scheme and are not repeated here.

    The one list, with where each entry comes from:
    - [to_string] -> Show: the interpreter's `to_string` builtin is
      [show_dispatch] (lib/eval/eval_builtins.ml), and the compiled call is
      routed to `Show$T.show` (lib/tir/lower_expr.ml, the `dispatch_name`
      rewrite; lib/tir/mono.ml and lib/tir/cap_passing.ml repeat it).
      String interpolation `"${e}"` is parsed as `to_string(e)`
      (lib/parser/parser.mly [desugar_interp]), so this covers it too.
    - [println] -> Show: the interpreter's `println` is [show_dispatch], and
      the compiled one is `Prelude.println`, `print_line(show(x))`
      (stdlib/prelude.march), which shadows the Mono builtin.
    - [to_json] -> JsonTo, [from_json] -> JsonFrom, [from_json_events] ->
      JsonFromEvents: the `impl_tbl` lookups of lib/eval/eval_builtins.ml
      and the [json_iface_of] dispatch of lib/eval/eval.ml; the compiled
      call is redirected to the derived impl (lib/tir/lower_expr.ml).
    - [own] -> Drop, on its SECOND argument: lib/eval/eval_builtins.ml's
      `own`, lowered to a `Drop$T.drop` closure (lib/tir/lower_expr.ml).
      The drop runs later, when the actor dies, not inside the caller; it
      is counted anyway, as a lambda's body is.

    Not dispatching (checked when this list was written): [print] and
    [html_escape_ctx] render with the structural repr ([value_display],
    `march_value_to_string_repr`), never a Show impl; the prelude's [str],
    [debug] and [inspect] are ordinary functions whose bodies call
    [to_string], so they are covered through it.  A builtin that calls a
    function VALUE it is passed (a sort's comparator) is a function-value
    call, which the graph already treats as such.

    test/test_refine_term.ml's "dispatching builtins" case calls every
    interpreter builtin of the typechecker's table on a value whose type
    has an [impl] of each interface, and fails if one runs an [impl] it is
    not listed (here or by its scheme) as reaching. *)
let runtime_dispatch : (string * (string list * dispatch_on)) list =
  [ ("to_string", ([ "Show" ], Arg 0));
    ("println", ([ "Show" ], Arg 0));
    ("to_json", ([ "JsonTo" ], Arg 0));
    ("from_json", ([ "JsonFrom" ], Any_impl));
    ("from_json_events", ([ "JsonFromEvents" ], Any_impl));
    ("own", ([ "Drop" ], Arg 1)) ]

(** The typechecker's builtin table, each name with the interfaces its
    scheme constrains (`==` -> [Eq], `show` -> [Show], `<` -> [Ord]), plus
    [runtime_dispatch]'s.  A builtin with no interface is trusted to
    terminate (§3.6, decision 10); one with an interface dispatches to an
    [impl] the program may declare, which is code like any other. *)
let builtin_table : (string, string list) Hashtbl.t Lazy.t =
  lazy
    (let tbl = Hashtbl.create 512 in
     List.iter
       (fun (n, (s : TT.scheme)) ->
         let ifs =
           match s with
           | TT.Poly (_, cs, _) ->
             List.filter_map (function TT.CInterface (i, _) -> Some (bare i) | _ -> None) cs
           | TT.Mono _ -> []
         in
         let prev = Option.value ~default:[] (Hashtbl.find_opt tbl n) in
         Hashtbl.replace tbl n (List.sort_uniq compare (prev @ ifs)))
       (TB.builtin_bindings @ TB.builtin_interface_bindings);
     List.iter
       (fun (n, _, _, _) -> if not (Hashtbl.mem tbl n) then Hashtbl.replace tbl n [])
       TB.variadic_builtins;
     List.iter
       (fun (n, (ifs, _)) ->
         let prev = Option.value ~default:[] (Hashtbl.find_opt tbl n) in
         Hashtbl.replace tbl n (List.sort_uniq compare (prev @ ifs)))
       runtime_dispatch;
     tbl)

(** The interfaces builtin [n] may run an [impl] of, by its scheme or by
    [runtime_dispatch]; [None] for a name that is not a builtin. *)
let builtin_dispatch (n : string) : string list option = Hashtbl.find_opt (Lazy.force builtin_table) n

let dotted (path : A.name list) : string = String.concat "." (List.map (fun n -> n.A.txt) path)

(* The scope a body is resolved in: its module path ("A.B."), and the
   [alias] / [use] / [import] declarations visible there (an inner module
   inherits its enclosing ones), with the module path that owns each [use]
   ([Refine_resolve.rctx]'s discipline, so both passes resolve alike). *)
type scope = {
  sc_path : string;
  sc_aliases : (string * string) list;  (** short name -> original dotted path *)
  sc_uses : (string * A.use_selector * string) list;  (** module, selector, owning path *)
}

(* What a callee name denotes. *)
type target =
  | T_unit of int  (** a unit of the graph *)
  | T_value  (** a local value: a call through a function value *)
  | T_impls of int list * bool
      (** an interface dispatch: these [impl] / default units, and whether a
          value picks among them ([e_dispatch]) *)
  | T_trusted  (** a builtin or an [extern] *)
  | T_unresolved  (** nothing the pass can name: may diverge (fail closed) *)

(* The dispatch key of an [impl]'s type: its head constructor, a tuple by
   arity, or ["*"] (a type variable or anything else: every type). *)
let impl_key (t : A.ty) : string =
  let rec go (t : A.ty) =
    match t with
    | A.TyCon (n, _) -> bare n.A.txt
    | A.TyTuple ts -> Printf.sprintf "$Tuple%d" (List.length ts)
    | A.TyRefine (t, _, _) | A.TyLinear (_, t) -> go t
    | _ -> "*"
  in
  go t

(* The dispatch keys a value of static type [t] may reach: every head
   constructor in it, closed under the type definitions ([reaches]: a
   derived or structural impl of a record shows its fields), and ["*"] for a
   type variable, whose instantiation is unknown here. *)
let ty_keys ~(reaches_any : string -> string list) (t : March_typecheck.Typecheck.ty) : SS.t =
  let module T = March_typecheck.Typecheck in
  let acc = ref SS.empty in
  let add k = acc := SS.add k !acc in
  let rec go (t : T.ty) =
    match T.repr t with
    | T.TCon (n, args) ->
      add (bare n);
      List.iter add (reaches_any (bare n));
      List.iter go args
    | T.TTuple ts ->
      add (Printf.sprintf "$Tuple%d" (List.length ts));
      List.iter go ts
    | T.TArrow (a, b) -> go a; go b
    | T.TRecord fs -> List.iter (fun (_, t) -> go t) fs
    | T.TLin (_, t) -> go t
    | T.TVar _ -> add "*"
    | _ -> ()
  in
  go t;
  !acc

(** Build the graph over [decls].  [file_mod] is the name the file declares
    (the module's [mod_name]); see the module comment for why both naming
    conventions are registered.

    Every callee name is resolved, never guessed (review fixes, phase 3): a
    unit of the graph (a [fn], an actor handler, a local [fn], an [impl]
    method, an interface's default method, a top-level [let]), reached
    lexically or through [alias] / [use] / [import]; an interface dispatch
    (an interface method, or a builtin whose scheme an interface constrains,
    such as [==]) to every [impl] of that interface the argument's static
    type can reach ([type_map]; all of them without one); a builtin of the
    typechecker's table or an [extern], trusted; and otherwise UNRESOLVED,
    which certifies nothing and withholds the hypothesis ([unresolved]). *)
let build_graph ?type_map ~(file_mod : string) (decls : A.decl list) : graph =
  let units = ref [] in
  let n_units = ref 0 in
  let edges = ref [] in
  let fv_calls = ref [] in
  let trusted = ref [] in
  let unresolved = ref [] in
  let sites = ref [] in
  let pred_sites = ref [] in
  let ambiguous = Hashtbl.create 16 in
  (* Set by [lookup] when the name it resolved could denote more than one
     declaration (see [graph.ambiguous]); read and cleared at each site. *)
  let ambig = ref false in
  let site ~src ~name ~span ~call ~args target =
    if !ambig then Hashtbl.replace ambiguous span ();
    sites := { s_src = src; s_name = name; s_span = span; s_call = call; s_args = args; s_target = target }
             :: !sites
  in
  let top_of : (int, int) Hashtbl.t = Hashtbl.create 64 in
  let new_unit ?decreases ?top ?ret ~name ~span ~kind ~params ~tys ~pspans ~clauses ~attrs () =
    let id = !n_units in
    incr n_units;
    let top = match top with Some t -> t | None -> id in
    Hashtbl.replace top_of id top;
    units :=
      { u_id = id; u_name = name; u_span = span; u_kind = kind; u_params = params;
        u_param_tys = tys; u_param_spans = pspans; u_clauses = clauses; u_attrs = attrs;
        u_decreases = decreases; u_top = top; u_ret = ret }
      :: !units;
    id
  in
  let globals : (string, int) Hashtbl.t = Hashtbl.create 256 in
  (* Every declaration a key was registered for, by source position (file
     basename, line, column): two positions under one key is an ambiguity
     ([graph.ambiguous]).  [globals] keeps its last-wins entry. *)
  let reg_pos : (string, (string * int * int) list) Hashtbl.t = Hashtbl.create 256 in
  let register_key key (sp : A.span) id =
    Hashtbl.replace globals key id;
    let pos = (Filename.basename sp.A.file, sp.A.start_line, sp.A.start_col) in
    let old = Option.value ~default:[] (Hashtbl.find_opt reg_pos key) in
    if not (List.mem pos old) then Hashtbl.replace reg_pos key (pos :: old)
  in
  (* Every module path registered ("A.B."), so an [alias] name that is also a
     module name in scope is seen. *)
  let mod_paths : (string, unit) Hashtbl.t = Hashtbl.create 64 in
  let externs_tbl : (string, unit) Hashtbl.t = Hashtbl.create 64 in
  (* (interface, dispatch key, unit) of every [impl] method and every
     interface default method (key ["*"]). *)
  let impls = ref [] in
  (* Method name (bare, and qualified [I.m]) -> the user interfaces declaring it. *)
  let iface_methods : (string, string) Hashtbl.t = Hashtbl.create 16 in
  (* Pass 1: register every top-level fn (any depth of [mod]) so forward and
     cross-module references resolve.  Bodies are walked in pass 2. *)
  let pending = ref [] in
  let rec register (scope : scope) mod_path (decls : A.decl list) =
    let scope =
      List.fold_left
        (fun sc d ->
          match d with
          | A.DAlias (ad, _) ->
            { sc with sc_aliases = (ad.A.alias_name.A.txt, dotted ad.A.alias_path) :: sc.sc_aliases }
          | A.DUse (ud, _) ->
            { sc with sc_uses = (dotted ud.A.use_path, ud.A.use_sel, mod_path) :: sc.sc_uses }
          | _ -> sc)
        { scope with sc_path = mod_path } decls
    in
    let externs =
      List.fold_left
        (fun acc d ->
          match d with
          | A.DExtern (ext, _) ->
            List.fold_left (fun acc ef -> SS.add ef.A.ef_name.A.txt acc) acc ext.A.ext_fns
          | _ -> acc)
        SS.empty decls
    in
    let prefixes = [ mod_path; file_mod ^ "." ^ mod_path ] in
    SS.iter (fun n -> List.iter (fun p -> Hashtbl.replace externs_tbl (p ^ n) ()) prefixes) externs;
    let fn_unit ~name (def : A.fn_def) =
      let params, tys =
        match def.A.fn_clauses with c :: _ -> clause_params c | [] -> ([], [])
      in
      let clauses =
        List.map
          (fun (c : A.fn_clause) -> { o_params = fst (clause_params c); o_body = c.A.fc_body })
          def.A.fn_clauses
      in
      let id =
        new_unit ~name ~span:def.A.fn_name.A.span ~kind:Top ~params ~tys
          ~pspans:(match def.A.fn_clauses with c :: _ -> clause_param_spans c | [] -> [])
          ~clauses ~attrs:def.A.fn_attrs ?ret:def.A.fn_ret_ty
          ?decreases:(List.assoc_opt "decreases" def.A.fn_attr_args) ()
      in
      pending := `Fn (id, def, scope) :: !pending;
      id
    in
    (* A bare expression as a unit: a lambda's parameters and body, or
       (any other expression) no parameters and the expression itself. *)
    let expr_unit ~name ~span (e : A.expr) =
      let params, tys, pspans, body =
        match e with
        | A.ELam (ps, body, _) ->
          ( List.map (fun (p : A.param) -> Some p.A.param_name.A.txt) ps,
            List.map (fun (p : A.param) -> p.A.param_ty) ps,
            List.map (fun (p : A.param) -> Some p.A.param_name.A.span) ps,
            body )
        | e -> ([], [], [], e)
      in
      let owner = { o_params = params; o_body = body } in
      let id =
        new_unit ~name ~span ~kind:Top ~params ~tys ~pspans ~clauses:[ owner ] ~attrs:[] ()
      in
      pending := `Expr (id, owner, scope) :: !pending;
      id
    in
    List.iter
      (fun d ->
        match d with
        | A.DFn (def, _) when not (SS.mem def.A.fn_name.A.txt externs) ->
          let id = fn_unit ~name:(mod_path ^ def.A.fn_name.A.txt) def in
          List.iter (fun p -> register_key (p ^ def.A.fn_name.A.txt) def.A.fn_name.A.span id) prefixes
        | A.DActor (_, name, actor, _) ->
          List.iter
            (fun (h : A.actor_handler) ->
              let params = List.map (fun (p : A.param) -> Some p.A.param_name.A.txt) h.A.ah_params in
              let tys = List.map (fun (p : A.param) -> p.A.param_ty) h.A.ah_params in
              let id =
                new_unit
                  ~name:(mod_path ^ name.A.txt ^ "." ^ h.A.ah_msg.A.txt)
                  ~span:h.A.ah_msg.A.span ~kind:Handler ~params ~tys
                  ~pspans:(List.map (fun (p : A.param) -> Some p.A.param_name.A.span) h.A.ah_params)
                  ~clauses:[ { o_params = params; o_body = h.A.ah_body } ]
                  ~attrs:[] ()
              in
              pending := `Handler (id, h, scope) :: !pending)
            (A.actor_body_handlers actor)
        | A.DImpl (idf, _) ->
          (* An [impl] method is reached only by dispatch (never by bare
             name), so it is a unit with no [globals] entry. *)
          let iface = bare idf.A.impl_iface.A.txt in
          let key = impl_key idf.A.impl_ty in
          List.iter
            (fun ((mn : A.name), (fd : A.fn_def)) ->
              let id = fn_unit ~name:(Printf.sprintf "%simpl %s.%s" mod_path iface mn.A.txt) fd in
              impls := (iface, key, id) :: !impls)
            idf.A.impl_methods
        | A.DInterface (idf, _) ->
          let iface = bare idf.A.iface_name.A.txt in
          List.iter
            (fun (md : A.method_decl) ->
              let m = md.A.md_name.A.txt in
              Hashtbl.add iface_methods m iface;
              Hashtbl.add iface_methods (iface ^ "." ^ m) iface;
              match md.A.md_default with
              | Some e ->
                let id =
                  expr_unit ~name:(Printf.sprintf "%sdefault %s.%s" mod_path iface m)
                    ~span:md.A.md_name.A.span e
                in
                impls := (iface, "*", id) :: !impls
              | None -> ())
            idf.A.iface_methods
        | A.DLet (_, b, _) ->
          (* A top-level [let]: a value (a lambda's body runs at each call). *)
          let rec names (p : A.pattern) : A.name list =
            match p with
            | A.PatVar n -> [ n ]
            | A.PatAs (p, n, _) -> n :: names p
            | A.PatCon (_, ps) | A.PatAtom (_, ps, _) | A.PatTuple (ps, _) | A.PatOr (ps, _) ->
              List.concat_map names ps
            | A.PatRecord (fs, _) -> List.concat_map (fun (_, p) -> names p) fs
            | A.PatWild _ | A.PatLit _ -> []
          in
          List.iter
            (fun (n : A.name) ->
              let id = expr_unit ~name:(mod_path ^ n.A.txt) ~span:n.A.span b.A.bind_expr in
              List.iter (fun p -> register_key (p ^ n.A.txt) n.A.span id) prefixes)
            (names b.A.bind_pat)
        | A.DMod (name, _, inner, _) ->
          List.iter (fun p -> Hashtbl.replace mod_paths (p ^ name.A.txt ^ ".") ()) prefixes;
          register scope (mod_path ^ name.A.txt ^ ".") inner
        | _ -> ())
      decls
  in
  register { sc_path = ""; sc_aliases = []; sc_uses = [] } "" decls;
  let impls = List.rev !impls in
  let unit_name = Hashtbl.create 64 in
  (* Pass 2: walk bodies. *)
  let add_edge ?(dispatch = false) ~env ~src ~dst ~kind ~args ~span ~owner () =
    let shadowed =
      List.filter
        (fun p -> SM.find_opt p env <> Some Param)
        (List.filter_map Fun.id owner.o_params)
    in
    edges :=
      { e_src = src; e_dst = dst; e_kind = kind; e_args = args; e_span = span; e_owner = owner;
        e_shadowed = shadowed; e_dispatch = dispatch }
      :: !edges
  in
  (* The scope of the body being walked.  A name is resolved LEXICALLY: a
     local binder first, then the enclosing module's own declarations and
     its own [use]s, then each outer module's, out to the top level; then an
     [alias]-qualified name.  The stdlib that the driver prepends keeps bare
     intra-module calls inside its [DMod]s (List's own `fold_left(t, ..)`),
     so resolving a bare name at the top level first would tie
     `List.fold_left` to an entry file's unrelated top-level `fold_left`
     (measured: `Deque.fold_left` came out as a two-member SCC with it). *)
  let cur = ref { sc_path = ""; sc_aliases = []; sc_uses = [] } in
  let candidates path =
    (* "A.B." -> ["A.B."; "A."; ""] *)
    let segs = String.split_on_char '.' path |> List.filter (( <> ) "") in
    let rec prefixes = function
      | [] -> [ "" ]
      | segs -> (String.concat "." segs ^ ".") :: prefixes (List.rev (List.tl (List.rev segs)))
    in
    prefixes segs
  in
  (* A dotted or bare name looked up in [tbl] relative to each enclosing module. *)
  let lexical_abs tbl q =
    List.find_map (fun p -> Hashtbl.find_opt tbl (p ^ q)) (candidates !cur.sc_path)
  in
  let imported sel n =
    match sel with
    | A.UseAll -> true
    | A.UseNames ns -> List.exists (fun (m : A.name) -> m.A.txt = n) ns
    | A.UseExcept ns -> not (List.exists (fun (m : A.name) -> m.A.txt = n) ns)
    | A.UseSingle -> false
  in
  let lookup ?(track = false) tbl n =
    if track then begin
      (* An alias whose name is also a module visible here: which one a
         dotted name means is the typechecker's call, not ours. *)
      (match String.index_opt n '.' with
       | Some i ->
         let head = String.sub n 0 i in
         if List.mem_assoc head !cur.sc_aliases
            && List.exists (fun p -> Hashtbl.mem mod_paths (p ^ head ^ ".")) (candidates !cur.sc_path)
         then ambig := true
       | None -> ())
    end;
    let use_at p =
      if String.contains n '.' then None
      else
        List.find_map
          (fun (m, sel, owner) ->
            if owner = p && imported sel n then lexical_abs tbl (m ^ "." ^ n) else None)
          !cur.sc_uses
    in
    match
      List.find_map
        (fun p ->
          match Hashtbl.find_opt tbl (p ^ n) with
          | Some r ->
            if track then begin
              (* Two declarations under this key, or a [use] at the same
                 level that also supplies the name. *)
              (match Hashtbl.find_opt reg_pos (p ^ n) with Some (_ :: _ :: _) -> ambig := true | _ -> ());
              (match use_at p with Some r' when r' <> r -> ambig := true | _ -> ())
            end;
            Some r
          | None -> use_at p)
        (candidates !cur.sc_path)
    with
    | Some r -> Some r
    | None -> (
      match String.index_opt n '.' with
      | Some i -> (
        let head = String.sub n 0 i and rest = String.sub n (i + 1) (String.length n - i - 1) in
        match List.assoc_opt head !cur.sc_aliases with
        | Some orig -> lexical_abs tbl (orig ^ "." ^ rest)
        | None -> None)
      | None -> None)
  in
  let module T = March_typecheck.Typecheck in
  let type_tbl = collect_types decls in
  let reaches = reach_fn type_tbl in
  let reach_memo = Hashtbl.create 32 in
  let reaches_any c =
    match Hashtbl.find_opt reach_memo c with
    | Some r -> r
    | None ->
      let r = Hashtbl.fold (fun t _ acc -> if t <> c && reaches c t then t :: acc else acc) type_tbl [] in
      Hashtbl.replace reach_memo c r;
      r
  in
  (* The [impl] units an interface dispatch over [ifs] reaches, given the
     dispatching argument [arg] (the first one, if any), and whether the
     [impl] is picked by a value: the argument's static type is unknown or
     holds a type variable. *)
  let dispatch ifs (arg : A.expr option) : int list * bool =
    let keys =
      match (type_map, arg) with
      | Some tm, Some a -> (
        match Hashtbl.find_opt tm (T.span_of_expr a) with
        | Some ty -> Some (ty_keys ~reaches_any ty)
        | None -> None)
      | _ -> None
    in
    ( List.filter_map
        (fun (i, k, id) ->
          if List.mem i ifs
             && (k = "*" || match keys with None -> true | Some ks -> SS.mem "*" ks || SS.mem k ks)
          then Some id
          else None)
        impls,
      match keys with None -> true | Some ks -> SS.mem "*" ks )
  in
  (* Inside a set-valued [@[measure]] body the typechecker binds the set
     vocabulary ([union], [singleton], ...: [Typecheck]'s [body_env] for such
     a measure), total logical operations with no runtime body. *)
  let set_measure = ref false in
  let set_measure_vocab = [ "union"; "inter"; "diff"; "singleton"; "member"; "subset"; "empty" ] in
  let is_set_measure (def : A.fn_def) =
    let rec is_set (t : A.ty) =
      match t with
      | A.TyRefine (b, _, _) | A.TyLinear (_, b) -> is_set b
      | A.TyCon ({ A.txt = "Set"; _ }, [ _ ]) -> true
      | _ -> false
    in
    List.mem "measure" def.A.fn_attrs && (match def.A.fn_ret_ty with Some t -> is_set t | None -> false)
  in
  let resolve ?(arity = -1) ?(args : A.expr list option) env n : target =
    match SM.find_opt n env with
    | Some (Fn id) -> T_unit id
    | Some (Var | Param) -> T_value
    | None -> (
      let found =
        match lookup ~track:true globals n with
        | Some id -> Some id
        | None when arity >= 0 -> lookup ~track:true globals (Printf.sprintf "%s$%d" n arity)
        | None -> None
      in
      match found with
      | Some id -> T_unit id
      | None ->
        if lookup externs_tbl n <> None then T_trusted
        else if !set_measure && List.mem n set_measure_vocab then T_trusted
        else begin
          let user_ifs = Hashtbl.find_all iface_methods n in
          let builtin = Hashtbl.find_opt (Lazy.force builtin_table) n in
          let ifs = List.sort_uniq compare (user_ifs @ Option.value ~default:[] builtin) in
          (* The argument whose static type picks the impl: the first, or
             the one [runtime_dispatch] names, or none (every impl). *)
          let arg =
            match args with
            | None -> None
            | Some args -> (
              match (user_ifs, List.assoc_opt n runtime_dispatch) with
              | [], Some (_, Any_impl) -> None
              | [], Some (_, Arg i) -> List.nth_opt args i
              | _ -> List.nth_opt args 0)
          in
          if ifs <> [] then (let ds, by_value = dispatch ifs arg in T_impls (ds, by_value))
          else if builtin <> None then T_trusted
          else T_unresolved
        end)
  in
  (* An identifier, not an operator: `+` and `==` are builtins too, but
     counting them would drown the report's trusted count. *)
  let is_ident n = n <> "" && (match n.[0] with 'a' .. 'z' | 'A' .. 'Z' | '_' -> true | _ -> false) in
  (* [walk ~src ~owner ~lam env e]: edges out of unit [src] found in [e].
     [lam]: [e] sits inside a lambda or a [let*] continuation of [src]. *)
  (* The calls in a type's refinement predicates (see [pred_sites]). *)
  let site_of_target n = function
    | T_unit dst -> S_unit dst
    | T_impls (ds, _) -> S_impls ds
    | T_value -> S_value
    | T_trusted -> if lookup externs_tbl n <> None then S_extern else S_builtin
    | T_unresolved -> S_unresolved
  in
  let rec pred_ty env (t : A.ty) : unit =
    match t with
    | A.TyRefine (b, binder, pred) ->
      pred_ty env b;
      let env' = bind_vars env [ (match binder with Some n -> n.A.txt | None -> "_") ] in
      pred_expr env' pred
    | A.TyCon (_, args) -> List.iter (pred_ty env) args
    | A.TyArrow (a, b) -> pred_ty env a; pred_ty env b
    | A.TyTuple ts -> List.iter (pred_ty env) ts
    | A.TyRecord fs -> List.iter (fun (_, t) -> pred_ty env t) fs
    | A.TyLinear (_, t) -> pred_ty env t
    | _ -> ()
  and pred_expr env (e : A.expr) : unit =
    match e with
    | A.EApp (A.EVar n, args, sp) ->
      ambig := false;
      let t = resolve ~arity:(List.length args) ~args env n.A.txt in
      if !ambig then Hashtbl.replace ambiguous sp ();
      pred_sites := (sp, site_of_target n.A.txt t) :: !pred_sites;
      List.iter (pred_expr env) args
    | e -> List.iter (pred_expr env) (Refine_encode.children e)
  in
  let pred_sig env (tys : A.ty option list) (ret : A.ty option) =
    List.iter (Option.iter (pred_ty env)) tys;
    Option.iter (pred_ty env) ret
  in
  let rec walk ~src ~owner ~lam env (e : A.expr) : unit =
    let w = walk ~src ~owner ~lam env in
    let call head args span =
      match head with
      | A.EVar n ->
        let kind = if lam then Lambda else Direct in
        ambig := false;
        let resolved = resolve ~arity:(List.length args) ~args env n.A.txt in
        let site = site ~src ~name:n.A.txt ~span ~call:true ~args in
        (match resolved with
         | T_unit dst ->
           site (S_unit dst);
           add_edge ~env ~src ~dst ~kind ~args ~span ~owner ()
         | T_impls (ds, by_value) ->
           site (S_impls ds);
           List.iter (fun dst -> add_edge ~dispatch:by_value ~env ~src ~dst ~kind ~args ~span ~owner ()) ds
         | T_value ->
           site S_value;
           fv_calls := (src, head) :: !fv_calls
         | T_trusted ->
           site (if lookup externs_tbl n.A.txt <> None then S_extern else S_builtin);
           if is_ident n.A.txt then trusted := (src, n.A.txt) :: !trusted
         | T_unresolved ->
           site S_unresolved;
           unresolved := (src, n.A.txt) :: !unresolved);
        List.iter w args
      | f ->
        site ~src ~name:"" ~span ~call:true ~args S_value;
        fv_calls := (src, f) :: !fv_calls;
        w f;
        List.iter w args
    in
    match e with
    | A.EApp (f, args, sp) -> call f args sp
    | A.EPipe (l, A.EVar n, sp) -> call (A.EVar n) [ l ] sp
    | A.EPipe (l, A.EApp (f, args, _), sp) -> call f (l :: args) sp
    | A.EVar n -> (
      let ref_edge ?dispatch dst =
        add_edge ?dispatch ~env ~src ~dst ~kind:Reference ~args:[] ~span:n.A.span ~owner ()
      in
      let site = site ~src ~name:n.A.txt ~span:n.A.span ~call:false ~args:[] in
      match resolve env n.A.txt with
      | T_unit dst -> site (S_unit dst); ref_edge dst
      | T_impls (ds, by_value) -> site (S_impls ds); List.iter (ref_edge ~dispatch:by_value) ds
      | T_value -> ()
      | T_trusted ->
        (* A builtin or extern named as a value; never a local (that is
           [T_value]), never an operator. *)
        if is_ident n.A.txt then
          site (if lookup externs_tbl n.A.txt <> None then S_extern else S_builtin)
      | T_unresolved -> site S_unresolved; unresolved := (src, n.A.txt) :: !unresolved)
    | A.EBlock (es, _) -> ignore (List.fold_left (fun env ex -> block_item ~src ~owner ~lam env ex) env es)
    | A.ELet (b, _) -> w b.A.bind_expr
    | A.ELetFn _ -> ignore (block_item ~src ~owner ~lam env e)
    | A.EMatch (s, brs, _) ->
      w s;
      List.iter
        (fun (br : A.branch) ->
          let env' = bind_vars env (pat_vars br.A.branch_pat) in
          Option.iter (walk ~src ~owner ~lam env') br.A.branch_guard;
          walk ~src ~owner ~lam env' br.A.branch_body)
        brs
    | A.ELam (ps, body, _) ->
      let env' = bind_vars env (List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps) in
      walk ~src ~owner ~lam:true env' body
    | A.ELetQ (p, r, c, _) ->
      w r;
      walk ~src ~owner ~lam (bind_vars env (pat_vars p)) c
    | A.ELetStar (p, r, c, _) ->
      (* `let*` puts its continuation inside a callback lambda (TIR lowering). *)
      w r;
      walk ~src ~owner ~lam:true (bind_vars env (pat_vars p)) c
    | _ -> List.iter w (Refine_encode.children e)
  (* One block element; returns the environment the REST of the block sees. *)
  and block_item ~src ~owner ~lam env (e : A.expr) =
    match e with
    | A.ELet (b, _) ->
      walk ~src ~owner ~lam env b.A.bind_expr;
      bind_vars env (pat_vars b.A.bind_pat)
    | A.ELetFn (n, ps, ret, body, _) ->
      let params = List.map (fun (p : A.param) -> Some p.A.param_name.A.txt) ps in
      let tys = List.map (fun (p : A.param) -> p.A.param_ty) ps in
      let lowner = { o_params = params; o_body = body } in
      let parent = try Hashtbl.find unit_name src with Not_found -> "?" in
      let id =
        new_unit ~name:(parent ^ "/" ^ n.A.txt) ~span:n.A.span ~kind:Local ~params ~tys
          ~top:(Option.value ~default:src (Hashtbl.find_opt top_of src)) ?ret
          ~pspans:(List.map (fun (p : A.param) -> Some p.A.param_name.A.span) ps)
          ~clauses:[ lowner ] ~attrs:[] ()
      in
      Hashtbl.replace unit_name id (parent ^ "/" ^ n.A.txt);
      let env = SM.add n.A.txt (Fn id) env in
      let inner = bind_params env (List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps) in
      pred_sig inner tys ret;
      walk ~src:id ~owner:lowner ~lam:false inner body;
      env
    | _ ->
      walk ~src ~owner ~lam env e;
      env
  in
  List.iter
    (fun (u : unit_) -> Hashtbl.replace unit_name u.u_id u.u_name)
    !units;
  List.iter
    (function
      | `Fn (id, (def : A.fn_def), scope) ->
        cur := scope;
        set_measure := is_set_measure def;
        List.iter
          (fun (c : A.fn_clause) ->
            let owner = { o_params = fst (clause_params c); o_body = c.A.fc_body } in
            let env =
              bind_params (bind_vars SM.empty (clause_binders c)) (List.filter_map Fun.id owner.o_params)
            in
            pred_sig env (snd (clause_params c)) def.A.fn_ret_ty;
            Option.iter (walk ~src:id ~owner ~lam:false env) c.A.fc_guard;
            walk ~src:id ~owner ~lam:false env c.A.fc_body)
          def.A.fn_clauses
      | `Handler (id, (h : A.actor_handler), scope) ->
        cur := scope;
        set_measure := false;
        let params = List.map (fun (p : A.param) -> p.A.param_name.A.txt) h.A.ah_params in
        let owner = { o_params = List.map Option.some params; o_body = h.A.ah_body } in
        (* A handler body also sees the actor's [state] (the typechecker's
           [handler_env]): a local value, never a callee to resolve. *)
        walk ~src:id ~owner ~lam:false (bind_params (bind_vars SM.empty [ "state" ]) params) h.A.ah_body
      | `Expr (id, (owner : owner), scope) ->
        cur := scope;
        set_measure := false;
        walk ~src:id ~owner ~lam:false
          (bind_params SM.empty (List.filter_map Fun.id owner.o_params))
          owner.o_body)
    (List.rev !pending);
  let units = Array.of_list (List.rev !units) in
  let n = Array.length units in
  let edges = List.rev !edges in
  let out = Array.make n [] in
  List.iter (fun e -> out.(e.e_src) <- e :: out.(e.e_src)) (List.rev edges);
  (* Tarjan, iterative over an explicit stack would be safer for huge graphs;
     the recursion depth is bounded by the longest call chain, which is small. *)
  let index = Array.make n (-1) and low = Array.make n 0 and on = Array.make n false in
  let stack = ref [] and counter = ref 0 and sccs = ref [] in
  let rec strong v =
    index.(v) <- !counter;
    low.(v) <- !counter;
    incr counter;
    stack := v :: !stack;
    on.(v) <- true;
    List.iter
      (fun e ->
        let w = e.e_dst in
        if index.(w) < 0 then begin
          strong w;
          low.(v) <- min low.(v) low.(w)
        end
        else if on.(w) then low.(v) <- min low.(v) index.(w))
      out.(v);
    if low.(v) = index.(v) then begin
      let rec pop acc =
        match !stack with
        | w :: rest ->
          stack := rest;
          on.(w) <- false;
          if w = v then w :: acc else pop (w :: acc)
        | [] -> acc
      in
      sccs := pop [] :: !sccs
    end
  in
  for v = 0 to n - 1 do
    if index.(v) < 0 then strong v
  done;
  let sccs = Array.of_list (List.rev !sccs) in
  let scc_of = Array.make n 0 in
  Array.iteri (fun i ms -> List.iter (fun v -> scc_of.(v) <- i) ms) sccs;
  { units; edges; out; scc_of; sccs; trusted = List.rev !trusted;
    unresolved = List.rev !unresolved; fv_calls = List.rev !fv_calls; sites = List.rev !sites;
    pred_sites = List.rev !pred_sites; ambiguous }

(** Intra-SCC edges out of [u]. *)
let intra g (u : int) : edge list =
  List.filter (fun e -> g.scc_of.(e.e_dst) = g.scc_of.(u)) g.out.(u)

(** A unit is recursive if its SCC has two members or it has an edge to
    itself (§0.5's "unit"). *)
let is_recursive g (u : int) : bool =
  List.length g.sccs.(g.scc_of.(u)) > 1 || List.exists (fun e -> e.e_dst = u) g.out.(u)

(* ── The COUNT classifier (§0.5), phase 0 ──────────────────────────────── *)

(* Pattern sub-components of a parameter, syntactically: names bound under a
   constructor of a [match] whose scrutinee is a parameter or an
   already-found component, including a tuple scrutinee (a merged multi-head
   function matches [(__arg0, __arg1)]).  A MEASUREMENT only: no shadowing
   discipline.  The certificate (phase 1) uses [structural_subvars]. *)
let syntactic_subcomponents (params : string list) (body : A.expr) : SS.t =
  let set = ref SS.empty in
  let is_src v = List.mem v params || SS.mem v !set in
  let comps (p : A.pattern) =
    match p with
    | A.PatCon (_, ps) | A.PatAtom (_, ps, _) -> List.concat_map pat_vars ps
    | A.PatAs (A.PatCon (_, ps), _, _) -> List.concat_map pat_vars ps
    | _ -> []
  in
  let changed = ref true in
  while !changed do
    changed := false;
    let add v = if not (SS.mem v !set) then (set := SS.add v !set; changed := true) in
    Refine_encode.iter_all
      (fun e ->
        match e with
        | A.EMatch (A.EVar s, brs, _) when is_src s.A.txt ->
          List.iter (fun (br : A.branch) -> List.iter add (comps br.A.branch_pat)) brs
        | A.EMatch (A.ETuple (es, _), brs, _) ->
          List.iter
            (fun (br : A.branch) ->
              match br.A.branch_pat with
              | A.PatTuple (ps, _) when List.length ps = List.length es ->
                List.iter2
                  (fun ex p ->
                    match ex with
                    | A.EVar s when is_src s.A.txt -> List.iter add (comps p)
                    | _ -> ())
                  es ps
              | _ -> ())
            brs
        | _ -> ())
      body
  done;
  !set

type arg_shape = Struct | Dec | Asc | Same | Other

let pos_lit (e : A.expr) : int option =
  match e with A.ELit (A.LitInt k, _) when k > 0 -> Some k | _ -> None

(* The shape of argument [a] passed at position [i], against the caller's
   parameter [p] at the same position and the caller's components [sub]. *)
let arg_shape ~(p : string option) ~(sub : SS.t) (a : A.expr) : arg_shape =
  let is_p v = match p with Some p -> v = p | None -> false in
  match a with
  | A.EVar v when SS.mem v.A.txt sub -> Struct
  | A.EVar v when is_p v.A.txt -> Same
  | A.EApp (A.EVar { A.txt = "-"; _ }, [ A.EVar v; k ], _) when is_p v.A.txt && pos_lit k <> None ->
    Dec
  | A.EApp (A.EVar { A.txt = "/"; _ }, [ A.EVar v; k ], _)
    when is_p v.A.txt && (match pos_lit k with Some k -> k >= 2 | None -> false) ->
    Dec
  | A.EApp (A.EVar { A.txt = "+"; _ }, [ A.EVar v; k ], _) when is_p v.A.txt && pos_lit k <> None ->
    Asc
  | A.EApp (A.EVar { A.txt = "+"; _ }, [ k; A.EVar v ], _) when is_p v.A.txt && pos_lit k <> None ->
    Asc
  | _ -> Other

let rec mentions (v : string) (e : A.expr) : bool =
  match e with
  | A.EVar n -> n.A.txt = v
  | _ -> List.exists (mentions v) (Refine_encode.children e)

(* "Bounded" (§0.5): the parameter appears in an ordering comparison in the
   body, or carries a refinement in its declared type.  A regex-grade test,
   as the design says: ±10%. *)
let bounded ~(body : A.expr) ~(p : string) ~(ty : A.ty option) : bool =
  let refined = match ty with Some t -> Refine_encode.ty_has_refinement t | None -> false in
  refined
  ||
  let found = ref false in
  Refine_encode.iter_all
    (fun e ->
      match e with
      | A.EApp (A.EVar { A.txt = "<" | "<=" | ">" | ">="; _ }, [ a; b ], _)
        when mentions p a || mentions p b ->
        found := true
      | _ -> ())
    body;
  !found

(* Phase 4: the builtins whose result depends on an EXTERNAL EVENT rather
   than on the program's own data: a message, a connection, bytes from a
   socket, file or process, the clock, or state another task writes (a
   [Vault]).  A recursion with no syntactic metric that reaches one of these
   is an external-event loop (class E, §0.5): it ends when the event says so.
   Replaces phase 0's name heuristic ([loop], [serve], [recv], …), which
   flagged terminating loops (a BFS over a queue, a merge sort's passes) and
   missed event loops named otherwise. *)
let event_builtins =
  [ "receive"; "sleep_ms"; "actor_call"; "task_await"; "task_await_unwrap"; "is_alive";
    "tcp_accept"; "tcp_accept_timeout"; "tcp_recv_all"; "tcp_recv_chunk"; "tcp_recv_chunk_timeout";
    "tcp_recv_chunked_frame"; "tcp_recv_exact"; "tcp_recv_http"; "tcp_recv_http_headers";
    "tcp_recv_timeout"; "tls_accept"; "tls_read"; "tls_read_timeout"; "ws_recv"; "ws_select";
    "file_read"; "file_read_line"; "file_read_chunk"; "csv_next_row"; "io_read_byte"; "io_read_line";
    "process_read_line"; "process_wait_proc"; "http_server_wait"; "unix_time"; "unix_time_ms";
    "sys_uptime_ms"; "vault_get"; "vault_ns_get"; "vault_put_new"; "mailbox_size"; "mailbox_backlog" ]

(** Is [u] marked [@[diverges]] (§2.2, phase 4)? *)
let is_diverges (u : unit_) : bool = List.mem "diverges" u.u_attrs

(** Units that reach an event builtin ([event_builtins]) through any chain of
    edges, themselves included. *)
let event_reach (g : graph) : bool array =
  let n = Array.length g.units in
  let ev = Array.make n false in
  List.iter (fun (u, name) -> if List.mem name event_builtins then ev.(u) <- true) g.trusted;
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter
      (fun e ->
        if ev.(e.e_dst) && not ev.(e.e_src) then begin
          ev.(e.e_src) <- true;
          changed := true
        end)
      g.edges
  done;
  ev

type row = {
  r_name : string;
  r_span : A.span;
  r_kind : string;
  r_shape : string;  (** structural | int-dec | int-asc | lex | ref | lambda | none *)
  r_mutual : bool;
  r_class : string;
      (** A B C D F; [E] for a [@[diverges]] unit; [E?] for an unannotated
          external-event loop (no metric, reaches an [event_builtins] call);
          or [?] *)
  r_scc : int;  (** SCC size *)
  r_recursive : bool;
      (** false only for a non-recursive unit listed because it calls a
          function value of a non-positive type (§3.6) *)
  r_cert : string;  (** [structural], or [unproved:<reason>] (phase 1) *)
}

let classify ?(event : int -> bool = fun _ -> false) g (u : unit_) : row =
  let es = intra g u.u_id in
  let mutual = List.length g.sccs.(g.scc_of.(u.u_id)) > 1 in
  let kind = match u.u_kind with Top -> "top" | Local -> "local" | Handler -> "handler" in
  let mk shape cls =
    { r_name = u.u_name; r_span = u.u_span; r_kind = kind; r_shape = shape; r_mutual = mutual;
      r_class = cls; r_scc = List.length g.sccs.(g.scc_of.(u.u_id)); r_recursive = true;
      r_cert = "" }
  in
  (* Covered by [@[diverges]]: the unit, a member of its cycle (one mark
     declares the whole cycle), or the top-level function enclosing a local
     (a local [fn] cannot carry an attribute). *)
  if List.exists (fun v -> is_diverges g.units.(v)) (u.u_top :: g.sccs.(g.scc_of.(u.u_id))) then
    mk "diverges" "E"
  else if List.exists (fun e -> e.e_kind = Reference) es then mk "ref" "F"
  else if List.exists (fun e -> e.e_kind = Lambda) es then mk "lambda" "F"
  else begin
    let shapes =
      List.map
        (fun e ->
          let params = List.filter_map Fun.id e.e_owner.o_params in
          let sub = syntactic_subcomponents params e.e_owner.o_body in
          List.mapi
            (fun i a ->
              let p = match List.nth_opt e.e_owner.o_params i with Some p -> p | None -> None in
              arg_shape ~p ~sub a)
            e.e_args)
        es
    in
    let arity = List.fold_left (fun acc s -> max acc (List.length s)) 0 shapes in
    let at i s = match List.nth_opt s i with Some x -> x | None -> Other in
    let every i k = shapes <> [] && List.for_all (fun s -> at i s = k) shapes in
    let first_pos k = List.find_opt (fun i -> every i k) (List.init arity Fun.id) in
    let body = match u.u_clauses with c :: _ -> c.o_body | [] -> A.ELit (A.LitInt 0, A.dummy_span) in
    let int_class i =
      match List.nth_opt u.u_params i with
      | Some (Some p) ->
        let ty = match List.nth_opt u.u_param_tys i with Some t -> t | None -> None in
        if bounded ~body ~p ~ty then "B" else "C"
      | _ -> "C"
    in
    (* Lexicographic: at every call, some position falls (structurally or by a
       literal) with every earlier position passed unchanged. *)
    let lex =
      arity >= 2
      && List.for_all
           (fun s ->
             let rec go i =
               i < arity
               && (match at i s with Struct | Dec -> true | Same -> go (i + 1) | _ -> false)
             in
             go 0)
           shapes
    in
    match first_pos Struct with
    | Some _ -> mk "structural" "A"
    | None -> (
      match first_pos Dec with
      | Some i -> mk "int-dec" (int_class i)
      | None -> (
        match first_pos Asc with
        | Some i -> mk "int-asc" (int_class i)
        | None ->
          if lex then mk "lex" "D"
          else if List.exists event g.sccs.(g.scc_of.(u.u_id)) then mk "none" "E?"
          else mk "none" "?"))
  end

(* ── Strict positivity (§3.6), phase 1 ─────────────────────────────────── *)

(** The declared types that are not strictly positive: [T] is non-positive
    if some type [X] mutually reachable with [T] (or [T] itself) has a field
    in which, to the LEFT of an arrow, there is a type that reaches [T].  A
    generic type's parameter that occurs on the left of an arrow (or is passed
    on to such a parameter) is itself a left position, so
    [type Box(a) = Box(a -> Int)] makes [type F = F(Box(F))] non-positive. *)
let nonpositive_types (decls : A.decl list) : SS.t =
  let tbl = collect_types decls in
  let reaches = reach_fn tbl in
  (* Negative parameter positions of each generic type, to a fixpoint. *)
  let neg : (string, int list) Hashtbl.t = Hashtbl.create 16 in
  let is_neg c j = match Hashtbl.find_opt neg c with Some l -> List.mem j l | None -> false in
  let rec walk ~(on_con : left:bool -> string -> unit) ~(on_var : left:bool -> string -> unit) ~left
      (t : A.ty) =
    let w = walk ~on_con ~on_var in
    match t with
    | A.TyArrow (a, b) -> w ~left:true a; w ~left b
    | A.TyCon (n, args) ->
      let c = bare n.A.txt in
      on_con ~left c;
      List.iteri (fun j a -> w ~left:(left || is_neg c j) a) args
    | A.TyVar v -> on_var ~left v.A.txt
    | A.TyTuple ts -> List.iter (w ~left) ts
    | A.TyRecord fs -> List.iter (fun (_, t) -> w ~left t) fs
    | A.TyLinear (_, t) | A.TyRefine (t, _, _) -> w ~left t
    | A.TyNat _ | A.TyNatOp _ | A.TyChan _ -> ()
  in
  let changed = ref true in
  while !changed do
    changed := false;
    Hashtbl.iter
      (fun n d ->
        List.iteri
          (fun j p ->
            if not (is_neg n j) then begin
              let hit = ref false in
              List.iter
                (walk ~on_con:(fun ~left:_ _ -> ()) ~on_var:(fun ~left v -> if left && v = p then hit := true)
                   ~left:false)
                d.t_fields;
              if !hit then begin
                Hashtbl.replace neg n (j :: Option.value ~default:[] (Hashtbl.find_opt neg n));
                changed := true
              end
            end)
          d.t_params)
      tbl
  done;
  Hashtbl.fold
    (fun t _ acc ->
      let bad = ref false in
      Hashtbl.iter
        (fun x dx ->
          if (x = t || (reaches t x && reaches x t)) && not !bad then
            List.iter
              (walk ~on_con:(fun ~left c -> if left && reaches c t then bad := true)
                 ~on_var:(fun ~left:_ _ -> ()) ~left:false)
              dx.t_fields)
        tbl;
      if !bad then SS.add t acc else acc)
    tbl SS.empty

(* ── The structural certificate (§3.3), phase 1 ────────────────────────── *)

(* [Diverges] (phase 4): a member is marked [@[diverges]]; no obligation is
   filed and no hypothesis given, and the report lists it as [diverges]. *)
type cert = Structural | Unproved of string | Diverges

let cert_name = function
  | Structural -> "structural"
  | Unproved r -> "unproved:" ^ r
  | Diverges -> "diverges"

(* The ADT a parameter position holds: its declared head constructor, else
   the typechecker's (a merged multi-head function's [__arg0] is unannotated). *)
let param_head ?type_map (u : unit_) (i : int) : string option =
  let rec head (t : A.ty) =
    match t with
    | A.TyCon (n, _) -> Some (bare n.A.txt)
    | A.TyRefine (t, _, _) | A.TyLinear (_, t) -> head t
    | _ -> None
  in
  match List.nth_opt u.u_param_tys i with
  | Some (Some t) -> head t
  | _ -> (
    match (type_map, List.nth_opt u.u_param_spans i) with
    | Some tm, Some (Some sp) -> (
      match Hashtbl.find_opt tm sp with
      | Some t -> (
        match March_typecheck.Typecheck.repr t with
        | March_typecheck.Typecheck.TCon (n, _) -> Some (bare n)
        | _ -> None)
      | None -> None)
    | _ -> None)

(* The SCC certificate.  [nonpos_call u]: unit [u] calls a function value
   whose static type mentions a non-positive type (or, with no type recorded,
   any non-positive type exists at all). *)
let certify ?type_map g ~(nonpos_call : int -> bool) ~(same_family : string -> string -> bool)
    (scc : int list) : cert =
  let members = scc in
  let es = List.concat_map (intra g) members in
  if List.exists (fun u -> is_diverges g.units.(u)) members then Diverges
  else if List.exists (fun e -> e.e_kind = Reference) es then Unproved "reference"
  else if List.exists nonpos_call members then Unproved "non-positive"
  else if List.exists (fun u -> List.mem_assoc u g.unresolved) members then Unproved "unresolved"
  else begin
    (* [structural_subvars] per (clause, parameter), memoised: the shared
       structural certificate (F6), with its by-name fixpoint. *)
    let memo = ref [] in
    let sub (o : owner) (i : int) : (string, unit) Hashtbl.t option =
      match List.nth_opt o.o_params i with
      | Some (Some p) -> (
        let key = (o.o_body, i) in
        match List.find_opt (fun (k, _) -> fst k == o.o_body && snd k = i) !memo with
        | Some (_, s) -> Some s
        | None ->
          let s =
            Refine_encode.structural_subvars ~params:(List.filter_map Fun.id o.o_params) p o.o_body
          in
          memo := (key, s) :: !memo;
          Some s)
      | _ -> None
    in
    (* An assignment [pos : unit -> position] certifies the SCC iff every
       intra-SCC edge f -> g passes, at g's position, a variable in
       [structural_subvars] of f's own position.  Bare variables only: no
       arithmetic, no nullary constructor, no [List.nth] (§3.3). *)
    let edge_ok pos e =
      match List.nth_opt e.e_args (pos e.e_dst) with
      | Some (A.EVar v) -> (
        match sub e.e_owner (pos e.e_src) with
        | Some set -> Hashtbl.mem set v.A.txt
        | None -> false)
      | _ -> false
    in
    let arity u = List.length g.units.(u).u_params in
    match members with
    | [ u ] ->
      if List.exists (fun i -> List.for_all (edge_ok (fun _ -> i)) es) (List.init (arity u) Fun.id)
      then Structural
      else Unproved "no-structural-arg"
    | _ ->
      (* Mutual: every member matches on a parameter of ONE TYPE FAMILY: the
         same ADT, or ADTs defined in terms of each other (`RTree`/`RForest`).
         §3.3 says "the same ADT"; that rejects the mutual measures over
         mutually-recursive datatypes the measure feature has always accepted
         (test group `mutual-mc`), and a strict component shrinks a value's
         constructor depth whichever type of the family it has, so the
         family is the sound reading (phase-1 progress note, ruling).
         Candidate types come from the first member's positions; the search
         is capped, and running out of budget is "unproved", never "proved". *)
      let head u i = param_head ?type_map g.units.(u) i in
      let first = List.hd members in
      let adts =
        List.sort_uniq compare (List.filter_map (head first) (List.init (arity first) Fun.id))
      in
      let positions adt u =
        List.filter
          (fun i -> match head u i with Some h -> same_family adt h | None -> false)
          (List.init (arity u) Fun.id)
      in
      let budget = ref 4096 in
      let rec search assigned = function
        | [] ->
          let pos u = List.assoc u assigned in
          List.for_all (edge_ok pos) es
        | (u, cands) :: rest ->
          List.exists
            (fun i ->
              decr budget;
              !budget > 0 && search ((u, i) :: assigned) rest)
            cands
      in
      let same_adt = ref false in
      let ok =
        List.exists
          (fun adt ->
            let cands = List.map (fun u -> (u, positions adt u)) members in
            if List.exists (fun (_, c) -> c = []) cands then false
            else begin
              same_adt := true;
              search [] cands
            end)
          adts
      in
      if ok then Structural
      else if !same_adt then Unproved "no-structural-arg"
      else Unproved "not-same-family"
  end

(* ── Metrics and SMT obligations (§3.3-§3.5), phase 2 ──────────────────── *)

(* What a parameter position holds, for the metric fragment (§2.1): an Int,
   a Float, another type (by name), or unknown (no declaration and no type
   recorded).  An unknown is treated as an Int by the fragment check and
   left to the solver, which declares it `Int`. *)
type pkind = PInt | PFloat | POther of string | PUnknown

let param_kind ?type_map (u : unit_) (i : int) : pkind =
  let of_name n = match bare n with "Int" -> PInt | "Float" -> PFloat | n -> POther n in
  let rec of_ty (t : A.ty) =
    match t with
    | A.TyCon (n, _) -> of_name n.A.txt
    | A.TyRefine (t, _, _) | A.TyLinear (_, t) -> of_ty t
    | A.TyArrow _ -> POther "function"
    | A.TyTuple _ -> POther "tuple"
    | A.TyRecord _ -> POther "record"
    | _ -> PUnknown
  in
  match List.nth_opt u.u_param_tys i with
  | Some (Some t) -> of_ty t
  | _ -> (
    match (type_map, List.nth_opt u.u_param_spans i) with
    | Some tm, Some (Some sp) -> (
      match Hashtbl.find_opt tm sp with
      | Some t -> (
        match March_typecheck.Typecheck.repr t with
        | March_typecheck.Typecheck.TCon (n, _) -> of_name n
        | _ -> PUnknown)
      | None -> PUnknown)
    | _ -> PUnknown)

let rec free_names (e : A.expr) : string list =
  match e with
  | A.EVar n -> [ n.A.txt ]
  (* An application's head names a function, operator or measure. *)
  | A.EApp (A.EVar _, args, _) -> List.concat_map free_names args
  | _ -> List.concat_map free_names (Refine_encode.children e)

(** Check one written metric against the fragment of §2.1: Int expressions
    over the unit's parameters, Int literals, [+ - *], [/] by a positive
    literal, and measures (the built-in [len] and every [@[measure]]) applied
    to parameters.  A bare non-Int parameter is not a metric (a structural
    component is written as a measure).  Returns one message per offence,
    each with the span to report it at. *)
let metric_errors ?type_map ~(is_measure : string -> bool) (u : unit_) (es : A.expr list) :
    (A.span * string) list =
  let errs = ref [] in
  let err sp msg = errs := (sp, msg) :: !errs in
  let pos name = List.find_index (fun p -> p = Some name) u.u_params in
  let span_of (e : A.expr) =
    match e with
    | A.EVar n -> n.A.span
    | A.ELit (_, sp) | A.EApp (_, _, sp) -> sp
    | _ -> u.u_span
  in
  let rec go (e : A.expr) =
    match e with
    | A.ELit (A.LitInt _, _) -> ()
    | A.ELit (_, sp) -> err sp "a metric component is an Int expression; this literal is not an Int"
    | A.EVar n -> (
      match pos n.A.txt with
      | None ->
        err n.A.span
          (Printf.sprintf
             "`%s` is not a parameter of `%s`: a metric may name only the function's own parameters"
             n.A.txt u.u_name)
      | Some i -> (
        match param_kind ?type_map u i with
        | PInt | PUnknown -> ()
        | PFloat ->
          err n.A.span
            (Printf.sprintf "`%s` is a Float: a metric component must be an Int expression" n.A.txt)
        | POther t ->
          err n.A.span
            (Printf.sprintf
               "`%s` is a `%s`, not an Int: a metric component must be an Int expression. To \
                measure a data structure, apply a measure to it, such as `len(%s)` or a \
                `@[measure]` like `size(%s)`"
               n.A.txt t n.A.txt n.A.txt)))
    | A.EApp (A.EVar { A.txt = "+" | "-" | "*"; _ }, [ a; b ], _) -> go a; go b
    | A.EApp (A.EVar { A.txt = "-" | "neg"; _ }, [ a ], _) -> go a
    | A.EApp (A.EVar { A.txt = "/"; _ }, [ a; b ], sp) -> (
      go a;
      match b with
      | A.ELit (A.LitInt k, _) when k > 0 -> ()
      | _ -> err sp "a metric may divide only by a positive Int literal")
    | A.EApp (A.EVar m, args, sp) when is_measure m.A.txt ->
      List.iter
        (fun a ->
          match a with
          | A.EVar n when pos n.A.txt <> None -> ()
          | _ ->
            err sp
              (Printf.sprintf "the measure `%s` must be applied to a parameter of `%s`" m.A.txt
                 u.u_name))
        args
    | _ ->
      err (span_of e)
        "this is outside the metric fragment: a metric is built from parameters, Int literals, \
         `+ - *`, `/` by a positive literal, and measures such as `len`"
  in
  List.iter go es;
  List.rev !errs

(** The DEFAULT metric (§3.5, step 3): the first Int parameter, as a
    1-tuple.  [None] when the unit has no parameter known to be an Int. *)
let default_metric ?type_map (u : unit_) : A.expr list option =
  let rec find i = function
    | [] -> None
    | Some p :: rest ->
      if param_kind ?type_map u i = PInt then Some [ A.EVar { A.txt = p; A.span = u.u_span } ]
      else find (i + 1) rest
    | None :: rest -> find (i + 1) rest
  in
  find 0 u.u_params

(** One termination obligation: the intra-SCC call [ms_edge], phrased as a
    call to a synthetic signature (§3.4).  [Refine_check.visit] discharges
    it through [check_call] when it reaches the call's span, with the path
    and scope facts that reach the call. *)
type metric_site = {
  ms_edge : edge;
  ms_sig : Refine_encode.fn_sig;
  ms_args : A.expr list;
  ms_rp : Refine_encode.rparam;
  ms_caller_metric : A.expr list;  (** over the caller's parameters, for messages *)
}

(** What phase 2 decided before the walk, per SCC. *)
type status =
  | St_structural  (** the phase-1 certificate; no query *)
  | St_pending  (** metric obligations filed; decided after the walk *)
  | St_unproved of string  (** no metric can be checked; the reason *)
  | St_diverges  (** a member is [@[diverges]]: nothing filed (phase 4) *)
  | St_undemanded  (** not demanded (§9): no annotation, not reported *)

type plan = {
  pl_status : status array;  (** by SCC *)
  pl_metric : A.expr list option array;  (** by unit: the metric checked *)
  pl_sites : (A.span, metric_site) Hashtbl.t;  (** by call span *)
  pl_invalid : (A.span * string) list;  (** [invalid_decreases] *)
  pl_no_effect : int list;  (** annotated units that are not recursive *)
}

let mk_name txt span : A.name = { A.txt; A.span }

(** The lexicographic decrease of §3.3 over component lists of one length:
    [(x1, …) <lex (y1, …) := (0 <= x1 && x1 < y1) || (x1 == y1 && (x2, …) <lex (y2, …))]. *)
let lex_formula ~(span : A.span) (xs : A.expr list) (ys : A.expr list) : A.expr =
  let op o a b = A.EApp (A.EVar (mk_name o span), [ a; b ], span) in
  let zero = A.ELit (A.LitInt 0, span) in
  let step x y = op "&&" (op "<=" zero x) (op "<" x y) in
  let rec go xs ys =
    match (xs, ys) with
    | [ x ], [ y ] -> step x y
    | x :: xr, y :: yr -> op "||" (step x y) (op "&&" (op "==" x y) (go xr yr))
    | _ -> A.ELit (A.LitBool false, span)
  in
  go xs ys

(* The synthetic signature `$decreases_g` for the edge [e] (§3.4).  Its one
   refined parameter is a dummy subject `$t` (actual `0`); the predicate is
   the lex formula of the callee's metric at the call's arguments against
   the caller's metric at entry.  Fixed names, no counter, so the VC cache
   keys on the metric alone (§6).  Names in the predicate:
   - `$c_x`: a CALLER-scope name `x` (a parameter the caller's metric reads,
     or a variable of an inlined argument), whose actual is `x` itself;
   - `$g_p`: the callee's parameter `p`, whose actual is the call's argument,
     for an argument that is a bare name (it keeps the callee's declared
     type, so a String's `len` is its byte length) or anything else not
     inlined;
   - an argument of plain Int arithmetic (`n - 1`, `n / 2`) is INLINED into
     the callee's metric over `$c_` names, because the predicate encoder
     reads `/` and `%` by a literal and an actual's reflection does not.
   [None] when an argument a metric reads is missing (an arity mismatch). *)
let decreases_site ?(is_rec_call : A.span -> bool = fun _ -> false) g
    ~(caller_metric : A.expr list) ~(callee_metric : A.expr list) (e : edge) : metric_site option =
  let span = e.e_span in
  let caller = g.units.(e.e_src) and callee = g.units.(e.e_dst) in
  let is_str ty =
    let rec go (t : A.ty) =
      match t with
      | A.TyCon (n, _) -> bare n.A.txt = "String"
      | A.TyRefine (t, _, _) | A.TyLinear (_, t) -> go t
      | _ -> false
    in
    match ty with Some t -> go t | None -> false
  in
  let var n = A.EVar (mk_name n span) in
  (* An argument that itself holds a recursive call of this SCC
     (`ack(m - 1, ack(m, n - 1))`) has no contract to reflect it by before
     phase 3, and an unreflectable actual would leave the whole obligation
     unchecked.  It is passed as a fresh name no binder holds, which the
     checker reads as an arbitrary value: an over-approximation, so a proof
     still holds of the real argument. *)
  let rec has_rec_call (a : A.expr) =
    (match a with A.EApp (_, _, sp) -> is_rec_call sp | _ -> false)
    || List.exists has_rec_call (Refine_encode.children a)
  in
  let rec arith (a : A.expr) =
    match a with
    | A.EVar _ | A.ELit (A.LitInt _, _) -> true
    | A.EApp (A.EVar { A.txt = "+" | "-" | "*" | "/" | "%"; _ }, [ x; y ], _) -> arith x && arith y
    | A.EApp (A.EVar { A.txt = "-" | "neg"; _ }, [ x ], _) -> arith x
    | _ -> false
  in
  (* Caller-scope names, by first use: (name, formal, declared type). *)
  let cnames = ref [] in
  let cformal ?ty x =
    (if not (List.exists (fun (n, _, _) -> n = x) !cnames) then
       let ty =
         match ty with
         | Some t -> t
         | None -> (
           match List.find_index (fun p -> p = Some x) e.e_owner.o_params with
           | Some i -> Option.join (List.nth_opt caller.u_param_tys i)
           | None -> None)
       in
       cnames := !cnames @ [ (x, "$c_" ^ x, ty) ]);
    var ("$c_" ^ x)
  in
  let rename_caller (a : A.expr) =
    Refine_encode.subst_params (List.map (fun x -> (x, cformal x)) (List.sort_uniq compare (free_names a))) a
  in
  let used = List.concat_map free_names callee_metric in
  let gformals = ref [] and genv = ref [] and missing = ref false in
  List.iteri
    (fun i p ->
      match p with
      | Some p when List.mem p used -> (
        let ty = Option.join (List.nth_opt callee.u_param_tys i) in
        match List.nth_opt e.e_args i with
        | None -> missing := true
        | Some a when has_rec_call a ->
          gformals := !gformals @ [ ("$g_" ^ p, var ("$opq_" ^ p), ty) ];
          genv := (p, var ("$g_" ^ p)) :: !genv
        | Some (A.EVar _ as a) ->
          gformals := !gformals @ [ ("$g_" ^ p, a, ty) ];
          genv := (p, var ("$g_" ^ p)) :: !genv
        | Some a when arith a -> genv := (p, rename_caller a) :: !genv
        | Some a ->
          gformals := !gformals @ [ ("$g_" ^ p, a, ty) ];
          genv := (p, var ("$g_" ^ p)) :: !genv)
      | _ -> ())
    callee.u_params;
  if !missing then None
  else begin
    let xs = List.map (Refine_encode.subst_params !genv) callee_metric in
    let ys = List.map rename_caller caller_metric in
    let pred = lex_formula ~span xs ys in
    let formals =
      List.map (fun (f, a, ty) -> (f, a, ty)) !gformals
      @ List.map (fun (x, f, ty) -> (f, var x, ty)) !cnames
    in
    let sg : Refine_encode.fn_sig =
      { Refine_encode.param_names = "$t" :: List.map (fun (f, _, _) -> f) formals;
        param_str = false :: List.map (fun (_, _, ty) -> is_str ty) formals;
        param_scalar = March_refine.Smt.SInt :: List.map (fun _ -> March_refine.Smt.SInt) formals;
        param_tys = None :: List.map (fun (_, _, ty) -> ty) formals;
        refined = [ { Refine_encode.idx = 0; binder = "$t"; pred; sort = None } ];
        ret = None; ret_sort = None; ret_ty = None }
    in
    let args = A.ELit (A.LitInt 0, span) :: List.map (fun (_, a, _) -> a) formals in
    Some
      { ms_edge = e; ms_sig = sg; ms_args = args; ms_rp = List.hd sg.Refine_encode.refined;
        ms_caller_metric = caller_metric }
  end

(* ── Entry points ─────────────────────────────────────────────────────── *)

type t = {
  graph : graph;
  rows : row list;
  certs : cert array;  (** by SCC index *)
}

let analyze ?(type_map : (A.span, March_typecheck.Typecheck.ty) Hashtbl.t option)
    ~(file_mod : string) (decls : A.decl list) : t =
  let graph = build_graph ?type_map ~file_mod decls in
  let nonpos = nonpositive_types decls in
  (* Type names whose mention means "may hold a non-positive type": the
     non-positive ones and every type that reaches one. *)
  let tainted =
    if SS.is_empty nonpos then SS.empty
    else begin
      let tbl = collect_types decls in
      let rec reaches seen t =
        SS.mem t nonpos
        || (not (SS.mem t seen))
           && (match Hashtbl.find_opt tbl t with
               | Some d -> List.exists (reaches (SS.add t seen)) (List.concat_map ty_cons d.t_fields)
               | None -> false)
      in
      Hashtbl.fold (fun t _ acc -> if reaches SS.empty t then SS.add t acc else acc) tbl nonpos
    end
  in
  let module T = March_typecheck.Typecheck in
  let rec ty_tainted (t : T.ty) =
    match T.repr t with
    | T.TCon (n, args) -> SS.mem (bare n) tainted || List.exists ty_tainted args
    | T.TArrow (a, b) -> ty_tainted a || ty_tainted b
    | T.TTuple ts -> List.exists ty_tainted ts
    | T.TRecord fs -> List.exists (fun (_, t) -> ty_tainted t) fs
    | T.TLin (_, t) -> ty_tainted t
    | _ -> false
  in
  let nonpos_units = Hashtbl.create 8 in
  if not (SS.is_empty nonpos) then
    List.iter
      (fun (u, head) ->
        let known =
          match type_map with
          | Some tm -> (
            match Hashtbl.find_opt tm (T.span_of_expr head) with
            | Some ty -> Some (ty_tainted ty)
            | None -> None)
          | None -> None
        in
        (* No recorded type while a non-positive type exists: assume the worst. *)
        if Option.value known ~default:true then Hashtbl.replace nonpos_units u ())
      graph.fv_calls;
  let nonpos_call u = Hashtbl.mem nonpos_units u in
  let reaches = reach_fn (collect_types decls) in
  let same_family a b = a = b || (reaches a b && reaches b a) in
  let certs =
    Array.map (fun scc -> certify ?type_map graph ~nonpos_call ~same_family scc) graph.sccs
  in
  let cert_of u = cert_name certs.(graph.scc_of.(u)) in
  let kind_name u = match u.u_kind with Top -> "top" | Local -> "local" | Handler -> "handler" in
  let ev = event_reach graph in
  let event u = ev.(u) in
  let rows =
    Array.to_list graph.units
    |> List.filter_map (fun u ->
           if is_recursive graph u.u_id then
             Some { (classify ~event graph u) with r_cert = cert_of u.u_id }
           else if is_diverges u then
             (* Listed though not recursive (§2.2): "not claimed to terminate"
                is about its callees, a callback, or a loop the graph does
                not see. *)
             Some
               { r_name = u.u_name; r_span = u.u_span; r_kind = kind_name u; r_shape = "diverges";
                 r_mutual = false; r_class = "E"; r_scc = 1; r_recursive = false;
                 r_cert = cert_name Diverges }
           else if nonpos_call u.u_id then
             Some
               { r_name = u.u_name; r_span = u.u_span; r_kind = kind_name u; r_shape = "value";
                 r_mutual = false; r_class = "F"; r_scc = 1; r_recursive = false;
                 r_cert = cert_name (Unproved "non-positive") }
           else None)
  in
  { graph; rows; certs }

let rows (t : t) = t.rows

(** Phase 2's plan (§3.5), decided before the refinement walk.  An SCC is
    planned when it is DEMANDED (§9): a member carries [@[decreases]], or
    [demanded] accepts a member (the driver passes "user code, under
    [--termination-report]").  A planned SCC is, in order:
    - [St_structural] when the phase-1 certificate holds (no query);
    - [St_unproved] when no metric can be checked (a reference edge, a call
      of a non-positive function value, an invalid or missing metric, an
      edge whose caller metric names a shadowed parameter);
    - otherwise [St_pending], with one obligation per intra-SCC call over
      the written metrics (only those, when any member has one) or else the
      first Int parameter of each member.
    Every written metric is checked against the fragment whether or not its
    unit is recursive; one written on a non-recursive unit is listed in
    [pl_no_effect].

    [override] (phase 5's inference, §3.5): for an SCC it answers, the
    metrics to check instead of the written or default ones, one per member
    (a member it leaves out makes the SCC [St_unproved "arity"]).  Such an
    SCC is planned whether or not it is demanded, and is obliged exactly as a
    written metric is: one obligation per intra-SCC direct or lambda edge. *)
let plan_metrics ?type_map ?(override : int -> (int * A.expr list) list option = fun _ -> None)
    ~(is_measure : string -> bool) ~(demanded : unit_ -> bool) (t : t) : plan =
  let g = t.graph in
  let status = Array.make (Array.length g.sccs) St_undemanded in
  let metric = Array.make (Array.length g.units) None in
  let sites = Hashtbl.create 16 in
  let invalid = ref [] and no_effect = ref [] in
  let bad = Hashtbl.create 4 in
  Array.iter
    (fun u ->
      match u.u_decreases with
      | Some _ when is_diverges u -> ()  (* [diverges_conflict], not a metric error *)
      | Some es ->
        let errs = metric_errors ?type_map ~is_measure u es in
        if errs <> [] then Hashtbl.replace bad u.u_id ();
        invalid := !invalid @ errs;
        if not (is_recursive g u.u_id) then no_effect := u.u_id :: !no_effect
      | None -> ())
    g.units;
  (* File one obligation per intra-SCC direct or lambda edge of [members]
     over the metrics [chosen] gives each member (or the first reason one
     has none). *)
  let file_metrics members chosen =
    match List.find_map (function _, Error r -> Some r | _ -> None) chosen with
    | Some r -> St_unproved r
    | None ->
      List.iter (function u, Ok m -> metric.(u) <- Some m | _ -> ()) chosen;
      let es =
        List.filter (fun e -> e.e_kind <> Reference) (List.concat_map (intra g) members)
      in
      let fail = ref None in
      List.iter
        (fun e ->
          if !fail = None then begin
            let mf = Option.get metric.(e.e_src) and mg = Option.get metric.(e.e_dst) in
            let fresh n =
              (not (List.mem n e.e_shadowed)) && List.mem (Some n) e.e_owner.o_params
            in
            if not (List.for_all fresh (List.concat_map free_names mf)) then
              fail := Some "shadowed"
            else
              match
                decreases_site
                  ~is_rec_call:(fun sp -> List.exists (fun e' -> e'.e_span = sp) es)
                  g ~caller_metric:mf ~callee_metric:mg e
              with
              | Some site -> Hashtbl.replace sites e.e_span site
              | None -> fail := Some "arity"
          end)
        es;
      (match !fail with Some r -> St_unproved r | None -> St_pending)
  in
  Array.iteri
    (fun si members ->
      let annotated = List.filter (fun u -> g.units.(u).u_decreases <> None) members in
      let ov = override si in
      if List.exists (is_recursive g) members
         && (ov <> None || annotated <> [] || List.exists (fun u -> demanded g.units.(u)) members)
      then
        status.(si) <-
          (match t.certs.(si) with
           | Structural -> St_structural
           | Diverges -> St_diverges
           | Unproved (("reference" | "non-positive" | "unresolved") as r) -> St_unproved r
           | Unproved _ when ov <> None ->
             let ms = Option.get ov in
             file_metrics members
               (List.map
                  (fun u -> match List.assoc_opt u ms with Some m -> (u, Ok m) | None -> (u, Error "arity"))
                  members)
           | Unproved _ -> (
             if List.exists (Hashtbl.mem bad) annotated then St_unproved "invalid-decreases"
             else
               let lens =
                 List.sort_uniq compare
                   (List.filter_map (fun u -> Option.map List.length g.units.(u).u_decreases) annotated)
               in
               match lens with
               | _ :: _ :: _ ->
                 (* One tuple length per SCC (§3.3); Dafny pads instead (§10). *)
                 let names =
                   String.concat ", "
                     (List.map
                        (fun u ->
                          Printf.sprintf "`%s` has %d" g.units.(u).u_name
                            (List.length (Option.get g.units.(u).u_decreases)))
                        annotated)
                 in
                 List.iter
                   (fun u ->
                     invalid :=
                       !invalid
                       @ [ ( g.units.(u).u_span,
                             Printf.sprintf
                               "the functions of one recursive cycle need metrics with the same \
                                number of components: %s"
                               names ) ])
                   annotated;
                 St_unproved "invalid-decreases"
               | _ -> (
                 let k = match lens with [ k ] -> k | _ -> 1 in
                 let chosen =
                   List.map
                     (fun u ->
                       let un = g.units.(u) in
                       match un.u_decreases with
                       | Some es -> (u, Ok es)
                       | None -> (
                         match default_metric ?type_map un with
                         | Some m when k = 1 -> (u, Ok m)
                         | Some _ -> (u, Error ("unannotated:" ^ un.u_name))
                         | None -> (u, Error "no-int-parameter")))
                     members
                 in
                 file_metrics members chosen))))
    g.sccs;
  { pl_status = status; pl_metric = metric; pl_sites = sites; pl_invalid = !invalid;
    pl_no_effect = List.rev !no_effect }

(** After the walk: the certificate of every planned SCC, from the verdicts
    the walk recorded at each obligation's call span.  An SCC is [metric]
    when every one of its obligations was reached and proved, [trusted] when
    each was proved or trusted (an [@[assume]] / [@[trusted]] function) and
    one was trusted, else [unproved:not-decreasing].  A site the walk never
    reached counts as unproved: absence of a proof is not a proof.  The
    second array holds, for an unproved pending SCC, its first failing site
    and the weakest verdict recorded there ([None]: never reached). *)
let finish (t : t) (pl : plan) ~(verdicts : A.span -> Obligation.verdict list) :
    string array * (metric_site * Obligation.verdict option) option array =
  let g = t.graph in
  let n = Array.length g.sccs in
  let certs = Array.make n "" and fails = Array.make n None in
  for si = 0 to n - 1 do
    match pl.pl_status.(si) with
    | St_undemanded -> ()
    | St_structural -> certs.(si) <- "structural"
    | St_diverges -> certs.(si) <- "diverges"
    | St_unproved r -> certs.(si) <- "unproved:" ^ r
    | St_pending ->
      let ss =
        Hashtbl.fold
          (fun _ site acc -> if g.scc_of.(site.ms_edge.e_src) = si then site :: acc else acc)
          pl.pl_sites []
        |> List.sort (fun a b -> compare a.ms_edge.e_span b.ms_edge.e_span)
      in
      let weakest site =
        let rank = function
          | Obligation.Violated -> 0 | Obligation.Skipped _ -> 1 | Obligation.Trusted -> 2
          | Obligation.Proved -> 3
        in
        List.fold_left
          (fun acc v -> match acc with Some a when rank a <= rank v -> acc | _ -> Some v)
          None (verdicts site.ms_edge.e_span)
      in
      let judged = List.map (fun s -> (s, weakest s)) ss in
      let ok = function Some (Obligation.Proved | Obligation.Trusted) -> true | _ -> false in
      (match List.find_opt (fun (_, v) -> not (ok v)) judged with
       | Some (s, v) ->
         certs.(si) <- "unproved:not-decreasing";
         fails.(si) <- Some (s, v)
       | None ->
         certs.(si) <-
           (if List.exists (fun (_, v) -> v = Some Obligation.Trusted) judged then "trusted"
            else "metric"))
  done;
  (certs, fails)

(** Phase 3 (§3.7, §4.2): every SCC reachable from SCC [si] through any
    edge of any of its members, [si] itself excluded.  The induction
    hypothesis is granted to [si] only when each reachable recursive SCC is
    certified too ("may diverge" is inferred upward through callers). *)
let reachable_sccs (g : graph) (si : int) : int list =
  let seen = Hashtbl.create 16 in
  let rec visit s =
    List.iter
      (fun u ->
        List.iter
          (fun e ->
            let d = g.scc_of.(e.e_dst) in
            if d <> si && not (Hashtbl.mem seen d) then begin
              Hashtbl.replace seen d ();
              visit d
            end)
          g.out.(u))
      g.sccs.(s)
  in
  visit si;
  List.sort compare (Hashtbl.fold (fun d () acc -> d :: acc) seen [])

(** Does a member of SCC [si] call or name something the graph could not
    resolve ([graph.unresolved])?  Such an SCC may diverge whatever its own
    certificate says, so the induction hypothesis is withheld from every SCC
    that reaches it (review fixes, phase 3). *)
let calls_unresolved (g : graph) (si : int) : bool =
  List.exists (fun u -> List.mem_assoc u g.unresolved) g.sccs.(si)

(** Is any member of SCC [si] marked [@[diverges]]? *)
let scc_diverges (g : graph) (si : int) : bool =
  List.exists (fun u -> is_diverges g.units.(u)) g.sccs.(si)

(** Why a unit may not terminate (phase 4, §2.2, §3.7, D4): the unit the
    divergence comes from, which may be the unit itself.
    - [Marked u]: [u] is marked [@[diverges]];
    - [Uncertified (u, cert)]: [u]'s recursion is not certified;
    - [Unresolved_call (u, name)]: [u] calls a name the graph cannot resolve. *)
type culprit = Marked of int | Uncertified of int * string | Unresolved_call of int * string

let culprit_unit = function Marked u | Uncertified (u, _) | Unresolved_call (u, _) -> u

(** "May diverge", inferred UPWARD through the call graph, by SCC.  An SCC
    may diverge when one of its members is marked [@[diverges]], when it is
    recursive and [cert_of si] is not a certificate ([structural], [metric]
    or [trusted]), when it calls an unresolved name, or when it reaches an
    SCC that may diverge.  An interface dispatch picked by a value
    ([e_dispatch]: `show(x)` with [x] of a type variable) does not carry
    it: the [impl] is chosen by a dictionary, so the caller terminates
    modulo it, as modulo any function value (§3.6), and each [impl] is a
    unit judged on its own.  A dispatch on a known type (`"${Box(1)}"`,
    `show(Box(1))`) names its [impl] where it is written, so it carries it
    like any call.  (The induction hypothesis keeps
    phase 3's stricter rule, which follows every edge.)  Nothing is required of a caller (D4): this feeds
    the report and [cap total] only.  Tarjan numbers SCCs callees first, so
    one pass in index order sees every callee before its callers. *)
let divergence (g : graph) ~(cert_of : int -> string) : culprit option array =
  let n = Array.length g.sccs in
  let res = Array.make n None in
  let certified si = List.mem (cert_of si) [ "structural"; "metric"; "trusted" ] in
  for si = 0 to n - 1 do
    let members = g.sccs.(si) in
    let own =
      match List.find_opt (fun u -> is_diverges g.units.(u)) members with
      | Some u -> Some (Marked u)
      | None ->
        let recursive = match members with u :: _ -> is_recursive g u | [] -> false in
        if recursive && not (certified si) then Some (Uncertified (List.hd members, cert_of si))
        else
          match List.find_opt (fun (u, _) -> List.mem u members) g.unresolved with
          | Some (u, name) -> Some (Unresolved_call (u, name))
          | None -> None
    in
    res.(si) <-
      (match own with
       | Some c -> Some c
       | None -> (
         (* A [@[diverges]] culprit is preferred, so the report can say
            "through `@[diverges]`" whenever that is one of the reasons. *)
         let cs =
           List.concat_map
             (fun u ->
               List.filter_map
                 (fun e ->
                   let d = g.scc_of.(e.e_dst) in
                   if d <> si && not e.e_dispatch then res.(d) else None)
                 g.out.(u))
             members
         in
         match List.find_opt (function Marked _ -> true | _ -> false) cs with
         | Some c -> Some c
         | None -> ( match cs with c :: _ -> Some c | [] -> None)))
  done;
  res

type divergence_note = {
  dv_text : string;  (** [culprit_text] *)
  dv_through_marked : bool;  (** the culprit is ANOTHER SCC's [@[diverges]] member *)
}

(** The last module's "may diverge" verdicts for the report, by declaring
    span: the reason, worded.  Filled by [Refine_check.check_module] when it
    decided certificates; reset per module. *)
let last_divergence : (A.span, divergence_note) Hashtbl.t = Hashtbl.create 16

(** [c] worded for unit [u] ("it reaches `serve`, which is marked …"). *)
let culprit_text (g : graph) (u : int) (c : culprit) : string =
  let cu = culprit_unit c in
  let own = g.scc_of.(cu) = g.scc_of.(u) in
  let name = g.units.(cu).u_name in
  match c with
  | Marked _ when own -> "it is marked `@[diverges]`"
  | Marked _ -> Printf.sprintf "it reaches `%s`, which is marked `@[diverges]`" name
  | Uncertified (_, cert) ->
    let why = if cert = "" then "" else Printf.sprintf " (%s)" cert in
    if own then Printf.sprintf "its recursion is not shown to terminate%s" why
    else Printf.sprintf "it reaches `%s`, whose recursion is not shown to terminate%s" name why
  | Unresolved_call (_, callee) ->
    Printf.sprintf "%s `%s`, which the termination checker cannot resolve"
      (if own then "it calls" else Printf.sprintf "it reaches `%s`, which calls" name)
      callee

(** The unit declared at [span] (a declaring name's span), if any. *)
let unit_at (g : graph) (span : A.span) : unit_ option =
  Array.find_opt (fun u -> u.u_span = span) g.units

(* ── Inference (§3.5), phase 5 ────────────────────────────────────────── *)

(** At most this many candidate metrics are checked per SCC (§3.5). *)
let max_candidates = 8

(* A candidate component, over parameter POSITIONS so one shape serves every
   member of a mutual SCC:
   - [SInt i]: the Int parameter at position [i];
   - [SGuard (i, b, one)]: [b - p_i] (plus 1 when [one]), for an Int
     parameter passed as [p_i + k] and compared with [b]; [b] names
     positions as [$pos<k>];
   - [SLen i]: [len(p_i)] for a [List] parameter. *)
type shape = SInt of int | SGuard of int * A.expr * bool | SLen of int

let shape_pos = function SInt i | SGuard (i, _, _) | SLen i -> i

(* A printed form, for deduplication and comparison with what phase 2
   tried: spans play no part. *)
let rec expr_key (e : A.expr) : string =
  match e with
  | A.EVar n -> n.A.txt
  | A.ELit (A.LitInt k, _) -> string_of_int k
  | A.EApp (A.EVar f, args, _) -> f.A.txt ^ "(" ^ String.concat "," (List.map expr_key args) ^ ")"
  | _ -> "?"

let metric_key (m : A.expr list) = String.concat ";" (List.map expr_key m)

let pos_var k = "$pos" ^ string_of_int k

(** One candidate: a metric for every member of the SCC. *)
type candidate = (int * A.expr list) list

(** The candidates of §3.5 for SCC [si], in order, each fully instantiated
    for every member and inside the metric fragment of §2.1:
    1. each Int parameter, in parameter order;
    2. [b - i] (or [b - i + 1]) for an Int parameter [i] passed as [i + k]
       (k a positive literal) at some intra-SCC call, and a comparison of [i]
       with [b] in the body, where [b] is a literal or built from parameters
       passed UNCHANGED (as themselves, at their own position) by every
       intra-SCC call: [i < b] / [i >= b] give [b - i], [i <= b] / [i > b]
       give [b - i + 1]; and [len(x) - i] for such an [i] and a [List] or
       [String] parameter [x] passed unchanged, with or without a comparison
       (a scanner whose exit tests a byte, not [i]);
    3. [len(x)] for a [List] parameter [x] (a helper's proved post, such as
       [split_at]'s, is what makes it fall);
    4. 2-tuples of the above, in parameter order (the first component's
       position before the second's).
    A candidate equal to the metric phase 2 already checked ([tried]) is
    dropped.  Shapes come from the first member and are instantiated by
    position; a member lacking a position of the right kind drops the
    candidate.  Returns at most [max_candidates] and how many there were in
    all.  Nothing here is trusted: each one is checked by the caller exactly
    as a written [@[decreases]] would be. *)
let candidates ?type_map ~(is_measure : string -> bool) ~(tried : int -> A.expr list option) (t : t)
    (si : int) : candidate list * int =
  let g = t.graph in
  let members = List.sort compare g.sccs.(si) in
  match members with
  | [] -> ([], 0)
  | h :: _ ->
    let hu = g.units.(h) in
    let edges = List.filter (fun e -> e.e_kind <> Reference) (List.concat_map (intra g) members) in
    let positions = List.mapi (fun i p -> (i, p)) hu.u_params in
    let ints = List.filter_map (fun (i, p) -> match p with Some _ when param_kind ?type_map hu i = PInt -> Some i | _ -> None) positions in
    let lists =
      List.filter_map
        (fun (i, p) -> match p with Some _ when param_kind ?type_map hu i = POther "List" -> Some i | _ -> None)
        positions
    in
    (* Positions every intra-SCC call passes unchanged. *)
    let unchanged k =
      List.for_all
        (fun e ->
          match (List.nth_opt e.e_args k, List.nth_opt g.units.(e.e_src).u_params k) with
          | Some (A.EVar n), Some (Some p) -> n.A.txt = p
          | _ -> false)
        edges
    in
    let incremented i =
      List.exists
        (fun e ->
          e.e_src = h
          &&
          match (List.nth_opt e.e_args i, List.nth_opt hu.u_params i) with
          | Some (A.EApp (A.EVar { A.txt = "+"; _ }, [ A.EVar x; A.ELit (A.LitInt k, _) ], _)), Some (Some p)
          | Some (A.EApp (A.EVar { A.txt = "+"; _ }, [ A.ELit (A.LitInt k, _); A.EVar x ], _)), Some (Some p) ->
            x.A.txt = p && k > 0
          | _ -> false)
        edges
    in
    (* [b] over positions: literals, unchanged parameters, [+ - *], [/] by a
       positive literal and measures of unchanged parameters. *)
    let rec bound ~(pos_of : string -> int option) ~(avoid : int) (e : A.expr) : A.expr option =
      match e with
      | A.ELit (A.LitInt _, _) -> Some e
      | A.EVar n -> (
        match pos_of n.A.txt with
        | Some k when k <> avoid && unchanged k -> Some (A.EVar { n with A.txt = pos_var k })
        | _ -> None)
      | A.EApp ((A.EVar { A.txt = "+" | "-" | "*"; _ } as f), [ a; b ], sp) -> (
        match (bound ~pos_of ~avoid a, bound ~pos_of ~avoid b) with
        | Some a, Some b -> Some (A.EApp (f, [ a; b ], sp))
        | _ -> None)
      | A.EApp ((A.EVar { A.txt = "/"; _ } as f), [ a; (A.ELit (A.LitInt k, _) as b) ], sp) when k > 0 ->
        Option.map (fun a -> A.EApp (f, [ a; b ], sp)) (bound ~pos_of ~avoid a)
      | A.EApp ((A.EVar m as f), [ A.EVar x ], sp) when is_measure m.A.txt -> (
        match pos_of x.A.txt with
        | Some k when k <> avoid && unchanged k -> Some (A.EApp (f, [ A.EVar { x with A.txt = pos_var k } ], sp))
        | _ -> None)
      | _ -> None
    in
    let guards =
      List.concat_map
        (fun (o : owner) ->
          let pos_of n = List.find_index (fun p -> p = Some n) o.o_params in
          let found = ref [] in
          let rec walk (e : A.expr) =
            (match e with
             | A.EApp (A.EVar { A.txt = ("<" | "<=" | ">" | ">=") as op; _ }, [ a; b ], _) ->
               let try_side (i_side : A.expr) (other : A.expr) (op : string) =
                 match i_side with
                 | A.EVar x -> (
                   match pos_of x.A.txt with
                   | Some i when List.mem i ints && incremented i -> (
                     match bound ~pos_of ~avoid:i other with
                     | Some b -> found := SGuard (i, b, op = "<=" || op = ">") :: !found
                     | None -> ())
                   | _ -> ())
                 | _ -> ()
               in
               let flip = function "<" -> ">" | "<=" -> ">=" | ">" -> "<" | _ -> "<=" in
               try_side a b op;
               try_side b a (flip op)
             | _ -> ());
            List.iter walk (Refine_encode.children e)
          in
          walk o.o_body;
          List.rev !found)
        hu.u_clauses
    in
    (* A scanner (§8 phase 5, `scanner`): an index climbing through a list or
       string passed unchanged is bounded by its length even when the exit
       tests something else (a byte), so `len(x) - i` is a candidate too. *)
    let scans =
      List.concat_map
        (fun i ->
          if not (incremented i) then []
          else
            List.filter_map
              (fun (k, p) ->
                match p with
                | Some _ when k <> i && unchanged k
                              && (match param_kind ?type_map hu k with
                                  | POther ("List" | "String") -> true
                                  | _ -> false) ->
                  let sp = hu.u_span in
                  Some
                    (SGuard
                       (i, A.EApp (A.EVar { A.txt = "len"; A.span = sp }, [ A.EVar { A.txt = pos_var k; A.span = sp } ], sp), false))
                | _ -> None)
              positions)
        ints
    in
    let singles =
      List.map (fun i -> SInt i) ints
      @ List.fold_left
          (fun acc s ->
            let k = function SGuard (i, b, one) -> (i, expr_key b, one) | _ -> (-1, "", false) in
            if List.exists (fun s' -> k s' = k s) acc then acc else acc @ [ s ])
          [] (guards @ scans)
      @ List.map (fun i -> SLen i) lists
    in
    let pairs =
      List.concat_map
        (fun a -> List.filter_map (fun b -> if shape_pos a < shape_pos b then Some [ a; b ] else None) singles)
        singles
    in
    let shapes = List.map (fun s -> [ s ]) singles @ pairs in
    (* Instantiate a component for member [u], by position. *)
    let inst (u : unit_) (s : shape) : A.expr option =
      let sp = u.u_span in
      let var k = match List.nth_opt u.u_params k with Some (Some p) -> Some (A.EVar { A.txt = p; A.span = sp }) | _ -> None in
      let op o a b = A.EApp (A.EVar { A.txt = o; A.span = sp }, [ a; b ], sp) in
      match s with
      | SInt i -> if param_kind ?type_map u i = PInt then var i else None
      | SLen i ->
        if param_kind ?type_map u i = POther "List" then
          Option.map (fun x -> A.EApp (A.EVar { A.txt = "len"; A.span = sp }, [ x ], sp)) (var i)
        else None
      | SGuard (i, b, one) -> (
        if param_kind ?type_map u i <> PInt then None
        else
          let ok = ref true in
          let rec rn (e : A.expr) =
            match e with
            | A.EVar n when String.length n.A.txt > 4 && String.sub n.A.txt 0 4 = "$pos" -> (
              match var (int_of_string (String.sub n.A.txt 4 (String.length n.A.txt - 4))) with
              | Some v -> v
              | None -> ok := false; e)
            | A.EApp (f, args, _) -> A.EApp (f, List.map rn args, sp)
            | e -> e
          in
          let b = rn b in
          match var i with
          | Some x when !ok ->
            let d = op "-" b x in
            Some (if one then op "+" d (A.ELit (A.LitInt 1, sp)) else d)
          | _ -> None)
    in
    let seen = Hashtbl.create 16 in
    let cands =
      List.filter_map
        (fun comps ->
          let per =
            List.map
              (fun u ->
                let un = g.units.(u) in
                let es = List.map (inst un) comps in
                if List.for_all Option.is_some es then
                  let es = List.map Option.get es in
                  if metric_errors ?type_map ~is_measure un es = [] then Some (u, es) else None
                else None)
              members
          in
          if not (List.for_all Option.is_some per) then None
          else
            let c = List.map Option.get per in
            let key = String.concat "|" (List.map (fun (u, es) -> string_of_int u ^ ":" ^ metric_key es) c) in
            let same_as_tried =
              List.for_all
                (fun (u, es) -> match tried u with Some m -> metric_key m = metric_key es | None -> false)
                c
            in
            if same_as_tried || Hashtbl.mem seen key then None
            else begin
              Hashtbl.replace seen key ();
              Some c
            end)
        shapes
    in
    (List.filteri (fun i _ -> i < max_candidates) cands, List.length cands)

(** What inference found for one SCC (phase 5): the candidate that proved,
    if any, as text per member ([pred_str] is [Refine_check]'s), how many
    candidates were checked, and how many there were. *)
type inferred = {
  inf_metric : string list option;  (** this member's components, if a candidate proved *)
  inf_checked : int;
  inf_total : int;
}

(** Set by the driver under [--refine-infer] and [--termination-report]: an
    SCC the plan leaves uncertified is searched for a metric (§3.5) after
    the walk.  Off by default, so a plain [--check] never infers. *)
let infer = ref false

(** The last module's inference results, by each member's declaring span.
    Filled by [Refine_check.check_module] when [infer] is set; reset per
    module. *)
let last_inferred : (A.span, inferred) Hashtbl.t = Hashtbl.create 16

(** The same, as expressions: a member's components when a candidate
    proved. *)
let last_inferred_exprs : (A.span, A.expr list) Hashtbl.t = Hashtbl.create 16

(** Set by [Refine_infer] (`--refine-infer`): demand, and infer for, every
    SCC with a member whose span it accepts, as [--termination-report] does
    for user code.  [None] otherwise. *)
let infer_demand : (A.span -> bool) option ref = ref None

(** The inferred metric for SCC [si], for the [termination_unproved] note
    ("note: try `@[decreases(e)]`.") that the LSP turns into the "add
    `@[decreases(e)]`" action.  Only for an SCC of ONE top-level function:
    the note names one attribute, and a local `fn` takes none. *)
let suggest_metric : (t -> int -> A.expr list option) ref =
  ref (fun t si ->
      match t.graph.sccs.(si) with
      | [ u ] when t.graph.units.(u).u_kind = Top ->
        Hashtbl.find_opt last_inferred_exprs t.graph.units.(u).u_span
      | _ -> None)

(** Set by the driver under [--termination-report]: every SCC of user code is
    demanded (§9), not only an annotated one.  Off by default (decision D2). *)
let check_all = ref false

(** The last module's phase-2 certificates, by declaring span, for the
    report: what [Refine_check.check_module] decided.  Reset per module. *)
let last_certs : (A.span, string) Hashtbl.t = Hashtbl.create 16

(** Callees trusted to terminate (builtins and externs, §3.6), distinct,
    over the units [is_user] accepts. *)
let trusted_callees ?(is_user : A.span -> bool = fun _ -> true) (t : t) : string list =
  List.sort_uniq compare
    (List.filter_map
       (fun (u, name) -> if is_user t.graph.units.(u).u_span then Some name else None)
       t.graph.trusted)

(** Names the graph could not resolve ([graph.unresolved]), distinct, over
    the units [is_user] accepts. *)
let unresolved_callees ?(is_user : A.span -> bool = fun _ -> true) (t : t) : string list =
  List.sort_uniq compare
    (List.filter_map
       (fun (u, name) -> if is_user t.graph.units.(u).u_span then Some name else None)
       t.graph.unresolved)

(** Is the declaration named at [span] a recursive unit whose SCC is NOT
    certified structural, or a unit that calls a non-positive function
    value?  [false] for a unit not in the graph and for a plain
    non-recursive one.  The [@[measure]] gate's SCC rule (§6). *)
let uncertified (t : t) (span : A.span) : bool =
  List.exists (fun r -> r.r_span = span && r.r_cert <> "structural") t.rows

let nonpositive_types (decls : A.decl list) : string list = SS.elements (nonpositive_types decls)

let span_str (s : A.span) = Printf.sprintf "%s:%d:%d" s.A.file s.A.start_line s.A.start_col

(** The [--termination-report] block: one line per recursive unit whose span
    [is_user] accepts (default: all), deduplicated by declaration site, plus
    each non-recursive unit that calls a function value of a non-positive
    type; then a per-class count and the certificate count.  Lines are
    tab-separated so they sort and group with ordinary shell tools, like
    [--refine-report-sites]. *)
let report_lines ?(is_user : A.span -> bool = fun _ -> true) (t : t) : string list =
  let seen = Hashtbl.create 64 in
  let rows =
    List.filter
      (fun r ->
        is_user r.r_span
        &&
        let k = span_str r.r_span in
        if Hashtbl.mem seen k then false
        else begin
          Hashtbl.replace seen k ();
          true
        end)
      t.rows
  in
  let classes = Hashtbl.create 8 in
  List.iter
    (fun r ->
      Hashtbl.replace classes r.r_class
        (1 + Option.value ~default:0 (Hashtbl.find_opt classes r.r_class)))
    rows;
  let recursive = List.filter (fun r -> r.r_recursive) rows in
  let marked_only = List.filter (fun r -> (not r.r_recursive) && r.r_shape = "diverges") rows in
  let header =
    Printf.sprintf "termination report: %d recursive units" (List.length recursive)
    ^ (match List.length rows - List.length recursive - List.length marked_only with
       | 0 -> ""
       | k -> Printf.sprintf ", %d calling a non-positive function value" k)
    ^
    match List.length marked_only with
    | 0 -> ""
    | k -> Printf.sprintf ", %d more marked @[diverges]" k
  in
  (* A phase-2 certificate, when the refinement walk decided one. *)
  let rows =
    List.map
      (fun r ->
        match Hashtbl.find_opt last_certs r.r_span with
        | Some c -> { r with r_cert = c }
        | None -> r)
      rows
  in
  let line r =
    Printf.sprintf "term\t%s\t%s%s\t%s\t%s\t%s\tscc=%d\tcert=%s" r.r_class r.r_shape
      (if r.r_mutual then " mutual" else "")
      (span_str r.r_span) r.r_name r.r_kind r.r_scc r.r_cert
  in
  let summary =
    "  by class: "
    ^ String.concat " "
        (List.map
           (fun (c, n) -> Printf.sprintf "%s=%d" c n)
           (List.sort compare (Hashtbl.fold (fun c n acc -> (c, n) :: acc) classes [])))
  in
  let count c = List.length (List.filter (fun r -> r.r_cert = c) rows) in
  let structural = count "structural" and metric = count "metric" and trusted_c = count "trusted" in
  let diverges = count "diverges" in
  let cert_line =
    Printf.sprintf "  certificate: %d structural, %d metric, %d trusted, %d unproved%s" structural
      metric trusted_c
      (List.length rows - structural - metric - trusted_c - diverges)
      (if diverges = 0 then "" else Printf.sprintf ", %d diverges" diverges)
  in
  (* Phase 4: an actor handler terminates per message (§3.7); one that may
     not, and the callers that may diverge only through a [@[diverges]]
     function (D4: nothing is required of them). *)
  let g = t.graph in
  let user_units =
    let seen_u = Hashtbl.create 16 in
    List.filter
      (fun u ->
        is_user u.u_span
        &&
        let k = span_str u.u_span in
        if Hashtbl.mem seen_u k then false
        else begin
          Hashtbl.replace seen_u k ();
          true
        end)
      (Array.to_list g.units)
  in
  let handler_lines =
    List.filter_map
      (fun u ->
        match (u.u_kind, Hashtbl.find_opt last_divergence u.u_span) with
        | Handler, Some dv ->
          Some
            (Printf.sprintf "handler\t%s\t%s\tmay not return: %s" (span_str u.u_span) u.u_name
               dv.dv_text)
        | _ -> None)
      user_units
  in
  let through =
    List.sort_uniq compare
      (List.filter_map
         (fun u ->
           if u.u_kind = Handler || is_diverges u then None
           else
             match Hashtbl.find_opt last_divergence u.u_span with
             | Some { dv_through_marked = true; _ } -> Some u.u_name
             | _ -> None)
         user_units)
  in
  let through_line =
    if through = [] then []
    else
      [ Printf.sprintf "  may diverge through @[diverges]: %d unit%s: %s" (List.length through)
          (if List.length through = 1 then "" else "s")
          (String.concat ", " through) ]
  in
  (* Builtins and externs are trusted to terminate (§3.6, decision 10). *)
  let callees = trusted_callees ~is_user t in
  let trusted_line =
    Printf.sprintf "  trusted: %d builtin or extern callee%s%s" (List.length callees)
      (if List.length callees = 1 then "" else "s")
      (if callees = [] then "" else ": " ^ String.concat ", " callees)
  in
  let unres = unresolved_callees ~is_user t in
  let unresolved_line =
    Printf.sprintf "  unresolved: %d callee%s%s" (List.length unres)
      (if List.length unres = 1 then "" else "s")
      (if unres = [] then "" else ": " ^ String.concat ", " unres)
  in
  (* Phase 5 (§3.5): what inference found for each uncertified unit, when
     the walk searched (under the report, or `--refine-infer`). *)
  let infer_rows =
    List.filter_map (fun r -> Option.map (fun i -> (r, i)) (Hashtbl.find_opt last_inferred r.r_span)) rows
  in
  let infer_lines =
    List.map
      (fun (r, i) ->
        let tried =
          Printf.sprintf "%d of %d candidate%s checked%s" i.inf_checked i.inf_total
            (if i.inf_total = 1 then "" else "s")
            (if i.inf_total > max_candidates then
               Printf.sprintf "; the cap of %d was reached" max_candidates
             else "")
        in
        Printf.sprintf "infer	%s	%s	%s	%s" (span_str r.r_span) r.r_name
          (match i.inf_metric with
           | Some es -> Printf.sprintf "@[decreases(%s)]" (String.concat ", " es)
           | None -> "none")
          tried)
      infer_rows
  in
  let infer_line =
    if infer_rows = [] then []
    else
      let n = List.length (List.filter (fun (_, i) -> i.inf_metric <> None) infer_rows) in
      [ Printf.sprintf "  inferred: %d of %d uncertified unit%s" n (List.length infer_rows)
          (if List.length infer_rows = 1 then "" else "s") ]
  in
  (header :: List.map line rows)
  @ infer_lines
  @ handler_lines
  @ [ summary; cert_line ]
  @ infer_line
  @ through_line
  @ [ trusted_line; unresolved_line ]
