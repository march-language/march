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
}

type graph = {
  units : unit_ array;
  edges : edge list;  (** every edge, in walk order *)
  out : edge list array;  (** edges by source *)
  scc_of : int array;  (** unit id -> SCC index *)
  sccs : int list array;  (** SCC index -> member ids *)
  fv_calls : (int * A.expr) list;
      (** (unit, callee expression) of every call through a FUNCTION VALUE: a
          callee bound by a parameter, [let], arm or lambda binder, or any
          callee that is not a name at all.  Positivity (§3.6) reads these. *)
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

(** Build the graph over [decls].  [file_mod] is the name the file declares
    (the module's [mod_name]); see the module comment for why both naming
    conventions are registered. *)
let build_graph ~(file_mod : string) (decls : A.decl list) : graph =
  let units = ref [] in
  let n_units = ref 0 in
  let edges = ref [] in
  let fv_calls = ref [] in
  let new_unit ~name ~span ~kind ~params ~tys ~pspans ~clauses ~attrs =
    let id = !n_units in
    incr n_units;
    units :=
      { u_id = id; u_name = name; u_span = span; u_kind = kind; u_params = params;
        u_param_tys = tys; u_param_spans = pspans; u_clauses = clauses; u_attrs = attrs }
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
              ~params ~tys
              ~pspans:(match def.A.fn_clauses with c :: _ -> clause_param_spans c | [] -> [])
              ~clauses ~attrs:def.A.fn_attrs
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
                  ~pspans:(List.map (fun (p : A.param) -> Some p.A.param_name.A.span) h.A.ah_params)
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
        | None ->
          if is_var env n.A.txt then fv_calls := (src, head) :: !fv_calls;
          List.iter w args)
      | f ->
        fv_calls := (src, f) :: !fv_calls;
        w f;
        List.iter w args
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
          ~pspans:(List.map (fun (p : A.param) -> Some p.A.param_name.A.span) ps)
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
  { units; edges; out; scc_of; sccs; fv_calls = List.rev !fv_calls }

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
  r_recursive : bool;
      (** false only for a non-recursive unit listed because it calls a
          function value of a non-positive type (§3.6) *)
  r_cert : string;  (** [structural], or [unproved:<reason>] (phase 1) *)
}

let classify g (u : unit_) : row =
  let es = intra g u.u_id in
  let mutual = List.length g.sccs.(g.scc_of.(u.u_id)) > 1 in
  let kind = match u.u_kind with Top -> "top" | Local -> "local" | Handler -> "handler" in
  let mk shape cls =
    { r_name = u.u_name; r_span = u.u_span; r_kind = kind; r_shape = shape; r_mutual = mutual;
      r_class = cls; r_scc = List.length g.sccs.(g.scc_of.(u.u_id)); r_recursive = true;
      r_cert = "" }
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

(* ── Strict positivity (§3.6), phase 1 ─────────────────────────────────── *)

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

type cert = Structural | Unproved of string

let cert_name = function Structural -> "structural" | Unproved r -> "unproved:" ^ r

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
  if List.exists (fun e -> e.e_kind = Reference) es then Unproved "reference"
  else if List.exists nonpos_call members then Unproved "non-positive"
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

(* ── Entry points ─────────────────────────────────────────────────────── *)

type t = {
  graph : graph;
  rows : row list;
  certs : cert array;  (** by SCC index *)
}

let analyze ?(type_map : (A.span, March_typecheck.Typecheck.ty) Hashtbl.t option)
    ~(file_mod : string) (decls : A.decl list) : t =
  let graph = build_graph ~file_mod decls in
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
  let rows =
    Array.to_list graph.units
    |> List.filter_map (fun u ->
           if is_recursive graph u.u_id then Some { (classify graph u) with r_cert = cert_of u.u_id }
           else if nonpos_call u.u_id then
             Some
               { r_name = u.u_name; r_span = u.u_span; r_kind = kind_name u; r_shape = "value";
                 r_mutual = false; r_class = "F"; r_scc = 1; r_recursive = false;
                 r_cert = cert_name (Unproved "non-positive") }
           else None)
  in
  { graph; rows; certs }

let rows (t : t) = t.rows

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
  let header =
    Printf.sprintf "termination report: %d recursive units" (List.length recursive)
    ^
    match List.length rows - List.length recursive with
    | 0 -> ""
    | k -> Printf.sprintf ", %d calling a non-positive function value" k
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
  let certified = List.length (List.filter (fun r -> r.r_cert = "structural") rows) in
  let cert_line =
    Printf.sprintf "  certificate: %d structural, %d unproved" certified
      (List.length rows - certified)
  in
  (header :: List.map line rows) @ [ summary; cert_line ]
