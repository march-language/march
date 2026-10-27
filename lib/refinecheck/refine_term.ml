(** Termination analysis (specs/2026-10-26-termination-checking-design.md).

    {1 What this pass is, and is not}

    March's tail pass ([Typecheck_tailcall]) checks STACK SAFETY: a recursive
    call in tail position is never examined, and a non-tail one passes if one
    argument is "structurally smaller" by a syntactic heuristic that accepts
    [n - 0] and [n - (0 - 1)] (design F1, F2).  This pass is the separate
    TERMINATION analysis of §3.  It shares nothing with the tail pass's
    [smaller] set or [is_structurally_smaller]: those are never termination
    evidence (§3.1, decision 2).

    Phase 0 (this file's first cut) is inert measurement:
    - the §3.2 call graph over every unit (a top-level [fn], a local [fn], an
      actor handler), with three edge kinds: a DIRECT call, a call inside a
      lambda or a [let*] continuation (a LAMBDA edge), and a function name
      used as a value (a REFERENCE edge, no arguments);
    - Tarjan SCCs over it;
    - the COUNT classifier of §0.5 (classes A-I, the ones with no syntactic
      metric by heuristic, marked [?]).

    Only [--termination-report] reads the result.

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
}

type unit_ = {
  u_id : int;
  u_name : string;  (** display name: [Inner.boom], [h/go3], [Actor.Msg] *)
  u_span : A.span;  (** the declaring name's span: the key across passes *)
  u_kind : unit_kind;
  u_params : string option list;  (** first clause's parameters, by position *)
  u_param_tys : A.ty option list;
  u_clauses : owner list;
  u_attrs : string list;
}

type graph = {
  units : unit_ array;
  edges : edge list;  (** every edge, in walk order *)
  out : edge list array;  (** edges by source *)
  scc_of : int array;  (** unit id -> SCC index *)
  sccs : int list array;  (** SCC index -> member ids *)
}

let rec pat_vars (p : A.pattern) : string list =
  match p with
  | A.PatVar n -> [ n.A.txt ]
  | A.PatAs (p, n, _) -> n.A.txt :: pat_vars p
  | A.PatCon (_, ps) | A.PatAtom (_, ps, _) | A.PatTuple (ps, _) | A.PatOr (ps, _) ->
    List.concat_map pat_vars ps
  | A.PatRecord (fs, _) -> List.concat_map (fun (_, p) -> pat_vars p) fs
  | A.PatWild _ | A.PatLit _ -> []

type binding = Fn of int | Var

let bind_vars env names = List.fold_left (fun env n -> SM.add n Var env) env names

let clause_params (c : A.fn_clause) : string option list * A.ty option list =
  List.split
    (List.map
       (function
         | A.FPNamed p | A.FPDefault (p, _) -> (Some p.A.param_name.A.txt, p.A.param_ty)
         | A.FPPat (A.PatVar n) -> (Some n.A.txt, None)
         | A.FPPat _ -> (None, None))
       c.A.fc_params)

let clause_binders (c : A.fn_clause) : string list =
  List.concat_map
    (function
      | A.FPNamed p | A.FPDefault (p, _) -> [ p.A.param_name.A.txt ]
      | A.FPPat p -> pat_vars p)
    c.A.fc_params

(** Build the graph over [decls].  [file_mod] is the name the file declares
    (the module's [mod_name]); see the module comment for why both naming
    conventions are registered. *)
let build_graph ~(file_mod : string) (decls : A.decl list) : graph =
  let units = ref [] in
  let n_units = ref 0 in
  let edges = ref [] in
  let new_unit ~name ~span ~kind ~params ~tys ~clauses ~attrs =
    let id = !n_units in
    incr n_units;
    units :=
      { u_id = id; u_name = name; u_span = span; u_kind = kind; u_params = params;
        u_param_tys = tys; u_clauses = clauses; u_attrs = attrs }
      :: !units;
    id
  in
  let globals : (string, int) Hashtbl.t = Hashtbl.create 256 in
  (* Pass 1: register every top-level fn (any depth of [mod]) so forward and
     cross-module references resolve.  Bodies are walked in pass 2. *)
  let pending = ref [] in
  let rec register mod_path (decls : A.decl list) =
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
    List.iter
      (fun d ->
        match d with
        | A.DFn (def, _) when not (SS.mem def.A.fn_name.A.txt externs) ->
          let params, tys =
            match def.A.fn_clauses with c :: _ -> clause_params c | [] -> ([], [])
          in
          let clauses =
            List.map
              (fun (c : A.fn_clause) -> { o_params = fst (clause_params c); o_body = c.A.fc_body })
              def.A.fn_clauses
          in
          let id =
            new_unit ~name:(mod_path ^ def.A.fn_name.A.txt) ~span:def.A.fn_name.A.span ~kind:Top
              ~params ~tys ~clauses ~attrs:def.A.fn_attrs
          in
          List.iter (fun p -> Hashtbl.replace globals (p ^ def.A.fn_name.A.txt) id) prefixes;
          pending := `Fn (id, def, mod_path) :: !pending
        | A.DActor (_, name, actor, _) ->
          List.iter
            (fun (h : A.actor_handler) ->
              let params = List.map (fun (p : A.param) -> Some p.A.param_name.A.txt) h.A.ah_params in
              let tys = List.map (fun (p : A.param) -> p.A.param_ty) h.A.ah_params in
              let id =
                new_unit
                  ~name:(mod_path ^ name.A.txt ^ "." ^ h.A.ah_msg.A.txt)
                  ~span:h.A.ah_msg.A.span ~kind:Handler ~params ~tys
                  ~clauses:[ { o_params = params; o_body = h.A.ah_body } ]
                  ~attrs:[]
              in
              pending := `Handler (id, h, mod_path) :: !pending)
            (A.actor_body_handlers actor)
        | A.DMod (name, _, inner, _) -> register (mod_path ^ name.A.txt ^ ".") inner
        | _ -> ())
      decls
  in
  register "" decls;
  let unit_name = Hashtbl.create 64 in
  (* Pass 2: walk bodies. *)
  let add_edge ~src ~dst ~kind ~args ~span ~owner =
    edges := { e_src = src; e_dst = dst; e_kind = kind; e_args = args; e_span = span; e_owner = owner }
             :: !edges
  in
  (* The module path of the body being walked.  A name is resolved
     LEXICALLY: a local binder first, then the enclosing module's own
     declarations, then each outer module's, out to the top level.  The
     stdlib that the driver prepends keeps bare intra-module calls inside
     its [DMod]s (List's own `fold_left(t, ..)`), so resolving a bare name
     at the top level first would tie `List.fold_left` to an entry file's
     unrelated top-level `fold_left` (measured: `Deque.fold_left` came out
     as a two-member SCC with it). *)
  let cur_path = ref "" in
  let candidates path =
    (* "A.B." -> ["A.B."; "A."; ""] *)
    let segs = String.split_on_char '.' path |> List.filter (( <> ) "") in
    let rec prefixes = function
      | [] -> [ "" ]
      | segs -> (String.concat "." segs ^ ".") :: prefixes (List.rev (List.tl (List.rev segs)))
    in
    prefixes segs
  in
  let resolve env n =
    match SM.find_opt n env with
    | Some (Fn id) -> Some id
    | Some Var -> None
    | None ->
      List.fold_left
        (fun acc p -> match acc with Some _ -> acc | None -> Hashtbl.find_opt globals (p ^ n))
        None (candidates !cur_path)
  in
  let is_var env n = match SM.find_opt n env with Some Var -> true | _ -> false in
  ignore is_var;
  (* [walk ~src ~owner ~lam env e]: edges out of unit [src] found in [e].
     [lam]: [e] sits inside a lambda or a [let*] continuation of [src]. *)
  let rec walk ~src ~owner ~lam env (e : A.expr) : unit =
    let w = walk ~src ~owner ~lam env in
    let call head args span =
      match head with
      | A.EVar n -> (
        match resolve env n.A.txt with
        | Some dst ->
          add_edge ~src ~dst ~kind:(if lam then Lambda else Direct) ~args ~span ~owner;
          List.iter w args
        | None -> List.iter w args)
      | f -> w f; List.iter w args
    in
    match e with
    | A.EApp (f, args, sp) -> call f args sp
    | A.EPipe (l, A.EVar n, sp) -> call (A.EVar n) [ l ] sp
    | A.EPipe (l, A.EApp (f, args, _), sp) -> call f (l :: args) sp
    | A.EVar n -> (
      match resolve env n.A.txt with
      | Some dst -> add_edge ~src ~dst ~kind:Reference ~args:[] ~span:n.A.span ~owner
      | None -> ())
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
    | A.ELetFn (n, ps, _, body, _) ->
      let params = List.map (fun (p : A.param) -> Some p.A.param_name.A.txt) ps in
      let tys = List.map (fun (p : A.param) -> p.A.param_ty) ps in
      let lowner = { o_params = params; o_body = body } in
      let parent = try Hashtbl.find unit_name src with Not_found -> "?" in
      let id =
        new_unit ~name:(parent ^ "/" ^ n.A.txt) ~span:n.A.span ~kind:Local ~params ~tys
          ~clauses:[ lowner ] ~attrs:[]
      in
      Hashtbl.replace unit_name id (parent ^ "/" ^ n.A.txt);
      let env = SM.add n.A.txt (Fn id) env in
      let inner = bind_vars env (List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps) in
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
      | `Fn (id, (def : A.fn_def), path) ->
        cur_path := path;
        List.iter
          (fun (c : A.fn_clause) ->
            let owner = { o_params = fst (clause_params c); o_body = c.A.fc_body } in
            let env = bind_vars SM.empty (clause_binders c) in
            Option.iter (walk ~src:id ~owner ~lam:false env) c.A.fc_guard;
            walk ~src:id ~owner ~lam:false env c.A.fc_body)
          def.A.fn_clauses
      | `Handler (id, (h : A.actor_handler), path) ->
        cur_path := path;
        let params = List.map (fun (p : A.param) -> p.A.param_name.A.txt) h.A.ah_params in
        let owner = { o_params = List.map Option.some params; o_body = h.A.ah_body } in
        walk ~src:id ~owner ~lam:false (bind_vars SM.empty params) h.A.ah_body)
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
  { units; edges; out; scc_of; sccs }

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

let loopish = [ "loop"; "serve"; "recv"; "receive"; "accept"; "await"; "listen"; "heartbeat"; "poll"; "wait" ]

let contains_sub (hay : string) (needle : string) : bool =
  let n = String.length needle and h = String.length hay in
  let rec at i = i + n <= h && (String.sub hay i n = needle || at (i + 1)) in
  at 0

type row = {
  r_name : string;
  r_span : A.span;
  r_kind : string;
  r_shape : string;  (** structural | int-dec | int-asc | lex | ref | lambda | none *)
  r_mutual : bool;
  r_class : string;  (** A B C D F, or a heuristic [E?], or [?] *)
  r_scc : int;  (** SCC size *)
}

let classify g (u : unit_) : row =
  let es = intra g u.u_id in
  let mutual = List.length g.sccs.(g.scc_of.(u.u_id)) > 1 in
  let kind = match u.u_kind with Top -> "top" | Local -> "local" | Handler -> "handler" in
  let mk shape cls =
    { r_name = u.u_name; r_span = u.u_span; r_kind = kind; r_shape = shape; r_mutual = mutual;
      r_class = cls; r_scc = List.length g.sccs.(g.scc_of.(u.u_id)) }
  in
  if List.exists (fun e -> e.e_kind = Reference) es then mk "ref" "F"
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
          else
            let callees =
              List.map (fun e -> g.units.(e.e_dst).u_name) g.out.(u.u_id)
            in
            let names = String.lowercase_ascii u.u_name :: List.map String.lowercase_ascii callees in
            if List.exists (fun w -> List.exists (fun n -> contains_sub n w) names) loopish
            then mk "none" "E?"
            else mk "none" "?"))
  end

(* ── Entry points ─────────────────────────────────────────────────────── *)

type t = { graph : graph; rows : row list }

let analyze ?type_map:(_ : (A.span, March_typecheck.Typecheck.ty) Hashtbl.t option)
    ~(file_mod : string) (decls : A.decl list) : t =
  let graph = build_graph ~file_mod decls in
  let rows =
    Array.to_list graph.units
    |> List.filter (fun u -> is_recursive graph u.u_id)
    |> List.map (classify graph)
  in
  { graph; rows }

let rows (t : t) = t.rows

let span_str (s : A.span) = Printf.sprintf "%s:%d:%d" s.A.file s.A.start_line s.A.start_col

(** The [--termination-report] block: one line per recursive unit whose span
    [is_user] accepts (default: all), deduplicated by declaration site, then a
    per-class count.  Lines are tab-separated so they sort and group with
    ordinary shell tools, like [--refine-report-sites]. *)
let report_lines ?(is_user : A.span -> bool = fun _ -> true) (t : t) : string list =
  let seen = Hashtbl.create 64 in
  let rows =
    List.filter
      (fun r ->
        is_user r.r_span
        &&
        let k = span_str r.r_span in
        if Hashtbl.mem seen k then false else (Hashtbl.replace seen k (); true))
      t.rows
  in
  let classes = Hashtbl.create 8 in
  List.iter
    (fun r ->
      Hashtbl.replace classes r.r_class (1 + Option.value ~default:0 (Hashtbl.find_opt classes r.r_class)))
    rows;
  let header = Printf.sprintf "termination report: %d recursive units" (List.length rows) in
  let line r =
    Printf.sprintf "term\t%s\t%s%s\t%s\t%s\t%s\tscc=%d" r.r_class r.r_shape
      (if r.r_mutual then " mutual" else "")
      (span_str r.r_span) r.r_name r.r_kind r.r_scc
  in
  let summary =
    "  by class: "
    ^ String.concat " "
        (List.map
           (fun (c, n) -> Printf.sprintf "%s=%d" c n)
           (List.sort compare (Hashtbl.fold (fun c n acc -> (c, n) :: acc) classes [])))
  in
  (header :: List.map line rows) @ [ summary ]
