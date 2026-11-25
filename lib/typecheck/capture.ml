(* Capture inference (ocap phase 8a,
   specs/2026-11-11-ocap-capture-checking-design.md; plan:
   specs/plans/2026-11-24-ocap-p8a-capture-sets-plan.md).

   A second pass over the already-typechecked program.  It reads each
   expression's solved type from [env.type_map], builds a parallel annotated
   type ([Capture_ty.t]) and emits inclusion constraints between set
   variables at every flow point; the least solution gives each function
   value an upper bound on what it can do when called.  It adds no
   diagnostic and nothing it computes is read by lowering.

   Two effect variables per function value keep narrowing sound (design
   §6.1): [own] collects the operations its body performs and the own reach
   of the named functions it calls directly, which the static authority at
   its creation site narrows; [valv] collects the sets of the function
   values it calls, which arrive whole.

   Where the pass does not model something the answer is
   [Capture_set.unknown], never a smaller set. *)

open Typecheck_types
open Typecheck_env
module S = March_caps.Capture_set
module T = Capture_ty

type svar = T.svar

(* MARCH_CAPTURE_DEBUG=1: every untracked spot, with its cause, on stderr. *)
let debug = Sys.getenv_opt "MARCH_CAPTURE_DEBUG" <> None

(* ── the constraint store ───────────────────────────────────────────────── *)

type reason = { why : string; rspan : Ast.span }

type edge = {
  dst : svar;
  narrow : S.t option;  (** the source is narrowed by this before it flows *)
  ground_only : bool;  (** an instantiation's link back to its scheme *)
  ewhy : reason option;
}

type store = {
  mutable next : int;
  consts : (svar, S.t) Hashtbl.t;
  const_why : (svar, (S.t * reason) list) Hashtbl.t;
  succ : (svar, edge list) Hashtbl.t;
  unknown_causes : (string, int) Hashtbl.t;
  mutable unknown_at : (string * Ast.span) list;
}

let new_store () =
  { next = 0; consts = Hashtbl.create 1024; const_why = Hashtbl.create 256; succ = Hashtbl.create 1024;
    unknown_causes = Hashtbl.create 8; unknown_at = [] }

let add_const (st : store) ?why (v : svar) (c : S.t) : unit =
  if not (S.is_empty c) then begin
    let prior = Option.value ~default:S.empty (Hashtbl.find_opt st.consts v) in
    Hashtbl.replace st.consts v (S.union prior c);
    match why with
    | Some r ->
      Hashtbl.replace st.const_why v ((c, r) :: Option.value ~default:[] (Hashtbl.find_opt st.const_why v))
    | None -> ()
  end

let add_edge (st : store) ?narrow ?(ground_only = false) ?why (u : svar) (v : svar) : unit =
  if u <> v then begin
    let es = Option.value ~default:[] (Hashtbl.find_opt st.succ u) in
    if not (List.exists (fun e -> e.dst = v && e.narrow = narrow && e.ground_only = ground_only) es) then
      Hashtbl.replace st.succ u ({ dst = v; narrow; ground_only; ewhy = why } :: es)
  end

let add_unknown (st : store) (v : svar) ~(cause : string) (sp : Ast.span) : unit =
  Hashtbl.replace st.unknown_causes cause
    (1 + Option.value ~default:0 (Hashtbl.find_opt st.unknown_causes cause));
  st.unknown_at <- (cause, sp) :: st.unknown_at;
  if debug then
    Printf.eprintf "[capture] not tracked: %s at %s:%d:%d\n" cause sp.Ast.file sp.Ast.start_line sp.Ast.start_col;
  add_const st v S.unknown ~why:{ why = "not tracked: " ^ cause; rspan = sp }

(* The least solution reachable from [seeds], over plain and narrowing
   edges, and over the grounding edges too when [ground]. *)
let solve (st : store) ~(ground : bool) (seeds : svar list) : (svar, S.t) Hashtbl.t =
  let value : (svar, S.t) Hashtbl.t = Hashtbl.create 256 in
  let get v = Option.value ~default:S.empty (Hashtbl.find_opt value v) in
  let work = Queue.create () in
  List.iter
    (fun v ->
       match Hashtbl.find_opt st.consts v with
       | Some c when not (Hashtbl.mem value v) ->
         Hashtbl.replace value v c;
         Queue.add v work
       | _ -> ())
    seeds;
  while not (Queue.is_empty work) do
    let u = Queue.pop work in
    let cu = get u in
    List.iter
      (fun e ->
         if ground || not e.ground_only then begin
           let incoming = match e.narrow with Some by -> S.narrow cu ~by | None -> cu in
           let old =
             match Hashtbl.find_opt value e.dst with
             | Some x -> x
             | None -> Option.value ~default:S.empty (Hashtbl.find_opt st.consts e.dst)
           in
           let merged = S.union old incoming in
           if (not (S.equal merged old)) || not (Hashtbl.mem value e.dst) then begin
             Hashtbl.replace value e.dst merged;
             Queue.add e.dst work
           end
         end)
      (Option.value ~default:[] (Hashtbl.find_opt st.succ u))
  done;
  value

(* ── schemes ────────────────────────────────────────────────────────────── *)

type active = {
  a_params : T.t list;
  a_result : T.t;
  a_result_ty : ty option;
  a_own : svar;
  a_val : svar;
  a_names : string list;  (** the parameters' names *)
  mutable a_kind_params : int list;
      (** parameters passed on as the KIND of an authority check: the
          function's reach has whatever kind its caller names there *)
}

type scheme = {
  sc_params : T.t list;
  sc_param_tys : ty option list;
  sc_result : T.t;
  sc_result_ty : ty option;
  sc_own : S.t;  (** the function's own reach, narrowed by its clause *)
  sc_kind_params : int list;  (** see [active.a_kind_params] *)
  sc_val : svar;
  sc_iface : svar list;
  sc_bounds : (svar * S.t) list;
  sc_flows : (svar * svar) list;
}

type fstate = Done of scheme list | Active of active list * int  (** the depth of its group's root frame *)

type frame = {
  f_depth : int;
  mutable f_root : int;
  mutable f_vars : svar list;
  mutable f_members : (string * active list) list;
}

type site_kind = Lambda | Local_fn of string | Named_value of string

type raw_site = {
  rs_span : Ast.span;
  rs_key : Ast.span;
  rs_kind : site_kind;
  rs_owner : string;
  rs_set : svar;
  rs_ty : T.t;
}

type actor_info = { ac_handlers : string list; ac_init : Ast.expr; ac_init_params : string list }

type binding =
  | Bound of T.t * int  (** type, the lambda depth it was bound at *)
  | Full  (** an actor's state or a message field: whatever arrives, with any authority *)

type st = {
  env : env;
  d : T.decls;
  store : store;
  states : (string, fstate) Hashtbl.t;
  mutable frames : frame list;
  top : frame;
  hv : (int, svar) Hashtbl.t;
  known : (string, unit) Hashtbl.t;  (** every function key: recorded, referenced as a dispatch node, or with a body *)
  let_keys : (string, unit) Hashtbl.t;
  clauses : (string, S.t) Hashtbl.t;  (** a function's `needs` clause, scopes included *)
  extra_bodies : (string, (string list * Ast.expr) list) Hashtbl.t;
      (** bodies read from the declarations, for a checker entry point that
          records none (the editor's: [check_module_with_env]) *)
  actors : (string, actor_info) Hashtbl.t;
  handler_keys : (string, unit) Hashtbl.t;
  mutable sites : raw_site list;
  annot : (Ast.span, T.t) Hashtbl.t;
  binders : (Ast.span, string * string) Hashtbl.t;  (** a `let` or pattern variable: its name, its owner *)
  fn_iface : (string, scheme list) Hashtbl.t;
  unsound : [ `Drop_callee_effect | `Drop_arg_flow | `Narrow_values ] option;
}

type ctx = {
  owner : string;
  act : active option;  (** the named function body being walked, when not inside a function value *)
  own : svar;
  valv : svar;
  scope : (string * binding) list;
  lams : (int * svar) list;  (** enclosing function values: (depth, set), innermost first *)
  depth : int;
  auth : S.t;
  at_module : bool;  (** walking a module-level binding's initialiser *)
}

let fresh (s : st) : svar =
  let v = s.store.next in
  s.store.next <- v + 1;
  let f = match s.frames with f :: _ -> f | [] -> s.top in
  f.f_vars <- v :: f.f_vars;
  v

let hv_of (s : st) (id : int) : svar =
  match Hashtbl.find_opt s.hv id with
  | Some v -> v
  | None ->
    let v = fresh s in
    Hashtbl.replace s.hv id v;
    v

let gen (s : st) : T.gen = { T.fresh = (fun () -> fresh s); hv = hv_of s }
let of_ty (s : st) (ty : ty) : T.t = T.of_ty s.d (gen s) ty
let ty_at (s : st) (sp : Ast.span) : ty option = Hashtbl.find_opt s.env.type_map sp

let plain_at (s : st) (sp : Ast.span) : bool =
  match ty_at s sp with Some ty -> T.ty_is_plain s.d ty | None -> false

let of_span (s : st) (sp : Ast.span) : T.t =
  match ty_at s sp with
  | Some ty -> of_ty s ty
  | None ->
    if debug then
      Printf.eprintf "[capture] no recorded type at %s:%d:%d\n" sp.Ast.file sp.Ast.start_line sp.Ast.start_col;
    T.Opaque

(* ── flow: src ⊆ dst ────────────────────────────────────────────────────── *)

let rec flow (s : st) ?why (src : T.t) (dst : T.t) : unit =
  let st = s.store in
  let edge u v = add_edge st ?why u v in
  let cross a b = List.iter (fun u -> List.iter (fun v -> edge u v) (T.svars b)) (T.svars a) in
  match src, dst with
  | _, T.Plain | T.Plain, _ | _, T.Opaque -> ()
  | T.Opaque, d ->
    List.iter (fun v -> add_const st v S.unknown) (T.svars d)
  | T.Hole { h_ty = Some t; _ }, d -> flow s ?why t d
  | T.Hole ({ h_ty = None; _ } as h), d -> h.h_out <- d :: h.h_out
  | a, T.Hole ({ h_ty = None; _ } as h) -> h.h_in <- a :: h.h_in
  | a, T.Hole { h_ty = Some t; _ } -> flow s ?why a t
  | T.Arrow (p1, r1, s1), T.Arrow (p2, r2, s2) ->
    edge s1 s2;
    flow s ?why p2 p1;
    flow s ?why r1 r2
  | T.Con (n1, a1, o1), T.Con (_, a2, o2) when List.length a1 = List.length a2 ->
    (match o1, o2 with Some u, Some v -> edge u v | _ -> ());
    let inv = T.variance s.d n1 = `Inv in
    List.iter2
      (fun x y ->
         flow s ?why x y;
         if inv then flow s ?why y x)
      a1 a2
  | T.Tuple a, T.Tuple b when List.length a = List.length b -> List.iter2 (flow s ?why) a b
  | T.Record a, T.Record b ->
    List.iter (fun (n, x) -> match List.assoc_opt n b with Some y -> flow s ?why x y | None -> ()) a
  | T.Var (_, h1), T.Var (_, h2) -> edge h1 h2
  | a, b ->
    if T.has_opaque a then List.iter (fun v -> add_const st v S.unknown) (T.svars b);
    cross a b

let fill_hole (s : st) (h : T.hole) (t : T.t) : unit =
  h.h_ty <- Some t;
  let pending_in = h.h_in and pending_out = h.h_out in
  h.h_in <- [];
  h.h_out <- [];
  List.iter (fun a -> flow s a t) pending_in;
  List.iter (fun d -> flow s t d) pending_out

(* ── what the program declares ──────────────────────────────────────────── *)

let qual prefix n = if prefix = "" then n else prefix ^ "." ^ n

let scan_decls (s : st) (decls : Ast.decl list) : unit =
  let add_body key body =
    if not (Hashtbl.mem s.env.fn_row_bodies key) then
      Hashtbl.replace s.extra_bodies key (Option.value ~default:[] (Hashtbl.find_opt s.extra_bodies key) @ [ body ])
  in
  let param_name = function
    | Ast.FPNamed p | Ast.FPDefault (p, _) -> p.Ast.param_name.Ast.txt
    | Ast.FPPat (Ast.PatVar n) -> n.Ast.txt
    | Ast.FPPat _ -> "_"
  in
  let rec go prefix (ds : Ast.decl list) =
    List.iter
      (fun (decl : Ast.decl) ->
         (match decl with
          | Ast.DFn (def, _) ->
            List.iter
              (fun (cl : Ast.fn_clause) ->
                 add_body (qual prefix def.Ast.fn_name.Ast.txt) (List.map param_name cl.Ast.fc_params, cl.Ast.fc_body))
              def.Ast.fn_clauses
          | Ast.DLet (_, { Ast.bind_pat = Ast.PatVar n; bind_expr; _ }, _) ->
            add_body (qual prefix n.Ast.txt) ([], bind_expr)
          | Ast.DActor (_, n, a, _) ->
            List.iter
              (fun (h : Ast.actor_handler) ->
                 add_body
                   (qual prefix n.Ast.txt ^ "_" ^ h.Ast.ah_msg.Ast.txt)
                   (List.map (fun (p : Ast.param) -> p.Ast.param_name.Ast.txt) h.Ast.ah_params, h.Ast.ah_body))
              (a.Ast.actor_handlers @ Option.to_list a.Ast.actor_on_stop)
          (* A test body or a setup block: a body of its own, so the
             function values made in it are sites. *)
          | Ast.DTest (t, sp) ->
            add_body (qual prefix (Printf.sprintf "$test@%d:%d" sp.Ast.start_line sp.Ast.start_col)) ([], t.Ast.test_body)
          | Ast.DSetup (e, sp) | Ast.DSetupAll (e, sp) ->
            add_body (qual prefix (Printf.sprintf "$setup@%d:%d" sp.Ast.start_line sp.Ast.start_col)) ([], e)
          | Ast.DDescribe (_, inner, _) -> go prefix inner
          | _ -> ());
         match decl with
        | Ast.DMod (n, _, inner, _) -> go (qual prefix n.Ast.txt) inner
        | Ast.DLet (_, b, _) -> (
          match b.Ast.bind_pat with
          | Ast.PatVar n -> Hashtbl.replace s.let_keys (qual prefix n.Ast.txt) ()
          | _ -> ())
        | Ast.DFn ({ Ast.fn_needs = Some (entries, _); fn_name; _ }, _) ->
          Hashtbl.replace s.clauses (qual prefix fn_name.Ast.txt) (S.of_entries entries)
        | Ast.DActor (_, n, a, _) ->
          let q = qual prefix n.Ast.txt in
          let handlers =
            List.map (fun (h : Ast.actor_handler) -> q ^ "_" ^ h.Ast.ah_msg.Ast.txt)
              (a.Ast.actor_handlers @ Option.to_list a.Ast.actor_on_stop)
          in
          List.iter (fun k -> Hashtbl.replace s.handler_keys k ()) handlers;
          Hashtbl.replace s.actors q
            { ac_handlers = handlers; ac_init = a.Ast.actor_init;
              ac_init_params = List.map (fun (p : Ast.param) -> p.Ast.param_name.Ast.txt) a.Ast.actor_init_params }
        | _ -> ())
      ds
  in
  go "" decls;
  Hashtbl.iter (fun k _ -> Hashtbl.replace s.known k ()) s.extra_bodies

let resolve (s : st) (owner : string) (name : string) : string option =
  March_caps.Cap_rows.resolve_ref ~scopes:s.env.fn_scopes s.known owner name

let bodies_of (s : st) (key : string) : (string list * Ast.expr) list =
  match Hashtbl.find_opt s.env.fn_row_bodies key with
  | Some bodies -> bodies
  | None -> Option.value ~default:[] (Hashtbl.find_opt s.extra_bodies key)

let clause_of (s : st) (key : string) : S.t option =
  match Hashtbl.find_opt s.clauses key with
  | Some c -> Some c
  | None ->
  match Hashtbl.find_opt s.env.fn_bound_points key with
  | Some { fb_origin = Fn_decl; fb_caps; _ } ->
    Some (S.of_scopes (List.map (fun kind -> { S.kind; arg = None }) fb_caps))
  | _ -> None

(* The package grant of [owner]'s module, as static authority (design §14). *)
let grant_of (s : st) (owner : string) : S.t option =
  if Hashtbl.length s.env.grant_module_pkgs = 0 then None
  else
    let rec up (k : string) : string option =
      match Hashtbl.find_opt s.env.grant_module_pkgs k with
      | Some p -> Some p
      | None -> (
        match String.rindex_opt k '.' with
        | Some i -> up (String.sub k 0 i)
        | None -> if k = "" then None else Hashtbl.find_opt s.env.grant_module_pkgs "")
    in
    match up owner with
    | None -> None
    | Some pkg -> (
      match Hashtbl.find_opt s.env.fn_bound_points (pkg ^ "$grant") with
      | Some { fb_origin = Dep_grant { text; _ }; fb_caps; _ } -> (
        (* The grant as written, scopes included. *)
        match March_caps.Dep_grants.parse_scope_text text with
        | Ok entries -> Some (S.of_entries entries)
        | Error _ -> Some (S.of_scopes (List.map (fun kind -> { S.kind; arg = None }) fb_caps)))
      | Some { fb_caps; _ } -> Some (S.of_scopes (List.map (fun kind -> { S.kind; arg = None }) fb_caps))
      | None -> None)

(* ── literal targets (builder's call 4) ─────────────────────────────────── *)

let lit_string (e : Ast.expr) : (string * bool) option =
  match e with
  | Ast.ELit (Ast.LitString v, _) -> Some (v, false)
  | Ast.EApp (Ast.EVar op, [ Ast.ELit (Ast.LitString v, _); _ ], _) when op.Ast.txt = "++" -> Some (v, true)
  | _ -> None

(* The scoped element a call's literal target gives, if any: (kind, scope). *)
let literal_scope (name : string) (args : Ast.expr list) : S.scope option =
  let arg i = Option.bind (List.nth_opt args i) lit_string in
  match List.assoc_opt name Scoped_literal_check.url_entry_points with
  | Some i -> (
    match arg i with
    | Some (url, prefix) -> (
      match March_caps.Host_scope.authority_of_url ~prefix url with
      | Some a ->
        let default_port =
          (String.length url >= 8 && String.sub url 0 8 = "https://" && a.a_port = 443)
          || (String.length url >= 7 && String.sub url 0 7 = "http://" && a.a_port = 80)
        in
        let host = if default_port then a.a_host else Printf.sprintf "%s:%d" a.a_host a.a_port in
        let path =
          match March_caps.Host_scope.url_path_of_literal ~prefix url with
          | Some p when p <> "/" && March_caps.Host_scope.path_ok p -> p
          | _ -> ""
        in
        let text = host ^ path in
        (match March_caps.Host_scope.parse_decl (Some text) with
         | Ok _ -> Some { S.kind = "IO.NetConnect"; arg = Some text }
         | Error _ -> None)
      | None -> None)
    | None -> None)
  | None -> (
    (* The scans the module-scope checks use, on this call alone: every
       argument that is not a literal is blanked so a nested call's literal
       is not taken for this one's. *)
    let shallow =
      Ast.EApp
        ( Ast.EVar { Ast.txt = name; span = Ast.dummy_span },
          List.map (function Ast.ELit _ as l -> l | _ -> Ast.EHole (None, Ast.dummy_span)) args,
          Ast.dummy_span )
    in
    match Typecheck_caps.literal_path_uses [] shallow with
    | [ (builtin, p, _) ] -> (
      match List.assoc_opt builtin Typecheck_builtins.builtin_cap_table with
      | Some kind when p <> "" && not (String.contains p ';') -> Some { S.kind; arg = Some p }
      | _ -> None)
    | _ :: _ -> None
    | [] -> (
      match Typecheck_caps.name_uses [] shallow with
      | [ Typecheck_caps.NameLit (_, kind, n, _) ]
        when n <> "" && not (String.exists (fun c -> c = ';' || c = '=' || c = ',') n) ->
        Some { S.kind; arg = Some n }
      | _ -> None))

(* A callee's own reach with its kind-level element replaced by the scoped
   one a literal target gives. *)
let scope_own (own : S.t) (lit : S.scope option) : S.t =
  match lit with
  | None -> own
  | Some sc ->
    if S.is_unknown own then own
    else
      let rest, hit =
        List.partition (fun (x : S.scope) -> not (x.kind = sc.kind && x.arg = None)) (S.scopes own)
      in
      if hit = [] then own else S.of_scopes (sc :: rest)

(* Builtins whose result holds no function value from anywhere: one that
   never returns, or one that makes a fresh, empty container.  Every other
   builtin that returns a function-holding value no argument accounts for is
   treated as conjuring it (builder's call 8). *)
let fresh_result_builtins : string list =
  [ (* never return *)
    "panic_"; "unreachable_"; "todo_";
    (* a fresh, empty container *)
    "vault_new"; "ring_buf_make";
    (* a pid: holding one adds nothing to a set (design §2) *)
    "pid_of_int"; "actor_whereis";
    (* decoded or logged data: no function value can come out of it *)
    "from_json"; "elts"; "logger_get_fields"; "diag_context_get" ]

(* Builtins that run function values registered earlier, by other code: the
   caller can do whatever those can.  (The registration itself charges the
   registrant, as any builtin handed a function does.) *)
let dispatching_builtins : string list = [ "logger_dispatch" ]

(* ── schemes: generalise and instantiate ────────────────────────────────── *)

let dedup (l : svar list) : svar list = List.sort_uniq compare l

let rec resolve_holes (t : T.t) : T.t =
  match t with
  | T.Hole { h_ty = Some t'; _ } -> resolve_holes t'
  | T.Arrow (a, b, v) -> T.Arrow (resolve_holes a, resolve_holes b, v)
  | T.Con (n, args, so) -> T.Con (n, List.map resolve_holes args, so)
  | T.Tuple ts -> T.Tuple (List.map resolve_holes ts)
  | T.Record fs -> T.Record (List.map (fun (n, x) -> (n, resolve_holes x)) fs)
  | t -> t

(* A function value's type with its result hole replaced by what filled it;
   parameter holes are kept (an unused parameter stays a hole). *)
let rec resolve_holes_result (t : T.t) : T.t =
  match t with
  | T.Arrow (p, r, v) -> T.Arrow (p, resolve_holes_result r, v)
  | T.Hole { h_ty = Some t'; _ } -> t'
  | t -> t

let generalise (s : st) (key : string) (value : (svar, S.t) Hashtbl.t) (a : active) : scheme =
  let params = List.map resolve_holes a.a_params and result = resolve_holes a.a_result in
  let iface = dedup ((a.a_val :: List.concat_map T.svars params) @ T.svars result) in
  let get v =
    match Hashtbl.find_opt value v with
    | Some x -> x
    | None -> Option.value ~default:S.empty (Hashtbl.find_opt s.store.consts v)
  in
  let own = get a.a_own in
  let own = match clause_of s key with Some c -> S.narrow own ~by:c | None -> own in
  let is_iface = Hashtbl.create 16 in
  List.iter (fun v -> Hashtbl.replace is_iface v ()) iface;
  let flows =
    List.concat_map
      (fun u ->
         let seen = Hashtbl.create 32 in
         let out = ref [] in
         let rec dfs x =
           List.iter
             (fun e ->
                if (not e.ground_only) && e.narrow = None && not (Hashtbl.mem seen e.dst) then begin
                  Hashtbl.replace seen e.dst ();
                  if Hashtbl.mem is_iface e.dst && e.dst <> u then out := (u, e.dst) :: !out;
                  dfs e.dst
                end)
             (Option.value ~default:[] (Hashtbl.find_opt s.store.succ x))
         in
         dfs u;
         !out)
      iface
  in
  { sc_params = params;
    sc_param_tys = List.map (function T.Hole h -> h.T.h_hm | _ -> None) a.a_params;
    sc_result_ty = a.a_result_ty;
    sc_kind_params = List.sort_uniq compare a.a_kind_params;
    sc_result = result; sc_own = own; sc_val = a.a_val; sc_iface = iface;
    sc_bounds = List.filter_map (fun v -> let c = get v in if S.is_empty c then None else Some (v, c)) iface;
    sc_flows = flows }

type inst = {
  i_fresh : (svar, svar) Hashtbl.t;
  i_mapped : (int, T.t) Hashtbl.t;
}

let inst_var (s : st) (i : inst) (v : svar) : svar =
  match Hashtbl.find_opt i.i_fresh v with
  | Some v' -> v'
  | None ->
    let v' = fresh s in
    Hashtbl.replace i.i_fresh v v';
    v'

let rec refresh (s : st) (t : T.t) : T.t =
  match t with
  | T.Plain | T.Opaque | T.Var _ -> t
  | T.Arrow (a, b, _) -> T.Arrow (refresh s a, refresh s b, fresh s)
  | T.Con (n, args, so) -> T.Con (n, List.map (refresh s) args, Option.map (fun _ -> fresh s) so)
  | T.Tuple ts -> T.Tuple (List.map (refresh s) ts)
  | T.Record fs -> T.Record (List.map (fun (n, x) -> (n, refresh s x)) fs)
  | T.Hole { h_ty = Some t'; _ } -> refresh s t'
  | T.Hole { h_ty = None; _ } -> T.Opaque

let map_tvar (s : st) (i : inst) (id : int) (hv : svar) (t : T.t) : unit =
  if not (Hashtbl.mem i.i_mapped id) then begin
    Hashtbl.replace i.i_mapped id t;
    let hv' = inst_var s i hv in
    (* What a value of this type holds is in the variable's set (a
       function's parameters are not something it holds). *)
    List.iter (fun v -> add_edge s.store v hv') (T.held t);
    (* And out again: a value of this type that the function hands back
       holds whatever the function knows a value of this type can hold,
       which is how a function value conjured inside it (read from a table
       opened by name) reaches the caller as not tracked. *)
    List.iter (fun v -> add_edge s.store hv' v) (T.held t);
    if T.has_opaque t then add_const s.store hv' S.unknown
  end

(* Bind the scheme's type variables from an argument's annotated type. *)
let rec bind_actual (s : st) (i : inst) (formal : T.t) (actual : T.t) : unit =
  match formal, actual with
  | T.Var (id, hv), a -> map_tvar s i id hv (refresh s a)
  | T.Hole { h_ty = Some f; _ }, a -> bind_actual s i f a
  | f, T.Hole { h_ty = Some a; _ } -> bind_actual s i f a
  | T.Arrow (p1, r1, _), T.Arrow (p2, r2, _) ->
    bind_actual s i p1 p2;
    bind_actual s i r1 r2
  | T.Con (_, a1, _), T.Con (_, a2, _) when List.length a1 = List.length a2 -> List.iter2 (bind_actual s i) a1 a2
  | T.Tuple a, T.Tuple b when List.length a = List.length b -> List.iter2 (bind_actual s i) a b
  | T.Record a, T.Record b ->
    List.iter (fun (n, x) -> match List.assoc_opt n b with Some y -> bind_actual s i x y | None -> ()) a
  | _ -> ()

(* The instance of a scheme type; [hm] is the solved type at that position
   when it is known, used for a type variable no argument bound. *)
let rec subst (s : st) (i : inst) (formal : T.t) (hm : ty option) : T.t =
  let sub_hm f = Option.bind hm (fun ty -> f (repr ty)) in
  match formal with
  | T.Plain | T.Opaque -> formal
  | T.Hole { h_ty = Some t; _ } -> subst s i t hm
  | T.Hole { h_ty = None; _ } -> T.new_hole ()
  | T.Var (id, hv) -> (
    match Hashtbl.find_opt i.i_mapped id with
    | Some t -> t
    | None ->
      let t = match hm with Some ty -> of_ty s ty | None -> T.Opaque in
      map_tvar s i id hv t;
      t)
  | T.Arrow (a, b, v) ->
    let ha = sub_hm (function TArrow (x, _) -> Some x | _ -> None) in
    let hb = sub_hm (function TArrow (_, y) -> Some y | _ -> None) in
    T.Arrow (subst s i a ha, subst s i b hb, inst_var s i v)
  | T.Con (n, args, so) ->
    let hs = sub_hm (function TCon (_, xs) when List.length xs = List.length args -> Some xs | _ -> None) in
    T.Con
      ( n,
        List.mapi (fun k a -> subst s i a (Option.map (fun xs -> List.nth xs k) hs)) args,
        Option.map (inst_var s i) so )
  | T.Tuple ts ->
    let hs = sub_hm (function TTuple xs when List.length xs = List.length ts -> Some xs | _ -> None) in
    T.Tuple (List.mapi (fun k a -> subst s i a (Option.map (fun xs -> List.nth xs k) hs)) ts)
  | T.Record fs ->
    let hs = sub_hm (function TRecord xs -> Some xs | _ -> None) in
    T.Record (List.map (fun (n, a) -> (n, subst s i a (Option.bind hs (List.assoc_opt n)))) fs)

(* Copy the scheme's bounds and flows onto the instance's variables, and
   link each instance variable back to the scheme's for grounding. *)
let finish_inst (s : st) (i : inst) (sc : scheme) ~(why : reason) : unit =
  List.iter (fun v -> ignore (inst_var s i v)) sc.sc_iface;
  List.iter (fun (v, c) -> add_const s.store ~why (inst_var s i v) c) sc.sc_bounds;
  List.iter (fun (u, v) -> add_edge s.store (inst_var s i u) (inst_var s i v)) sc.sc_flows;
  Hashtbl.iter (fun v v' -> add_edge s.store ~ground_only:true v' v) i.i_fresh

(* ── the walk ───────────────────────────────────────────────────────────── *)

let record_annot (s : st) (sp : Ast.span) (t : T.t) : unit =
  match t with T.Plain -> () | _ -> Hashtbl.replace s.annot sp t

let rec pat_binders (p : Ast.pattern) : Ast.name list =
  match p with
  | Ast.PatVar n -> [ n ]
  | Ast.PatWild _ | Ast.PatLit _ -> []
  | Ast.PatCon (_, ps) -> List.concat_map pat_binders ps
  | Ast.PatTuple (ps, _) | Ast.PatOr (ps, _) | Ast.PatAtom (_, ps, _) -> List.concat_map pat_binders ps
  | Ast.PatRecord (fs, _) -> List.concat_map (fun (_, p) -> pat_binders p) fs
  | Ast.PatAs (p, n, _) -> n :: pat_binders p

let ctor_fields (s : st) (ctor : string) (t : T.t) : T.t list option =
  match t with
  | T.Con (n, args, own) -> (
    let cis = Option.value ~default:[] (StrMap.find_opt ctor s.env.ctors) in
    (* The constructor of THIS type: two modules may each declare a type of
       one bare name with a constructor of one name.  A candidate is exact
       when its module-qualified type name agrees with the value's; with no
       exact one, a single candidate is taken and several are not guessed
       among. *)
    let suffix a b = a = b || String.ends_with ~suffix:("." ^ a) b in
    let full (ci : ctor_info) = if ci.ci_module = "" then ci.ci_type else ci.ci_module ^ "." ^ T.bare ci.ci_type in
    let candidates = List.filter (fun (ci : ctor_info) -> T.bare ci.ci_type = T.bare n) cis in
    let exact = List.filter (fun ci -> suffix (full ci) n || suffix n (full ci)) candidates in
    let pick =
      match exact, candidates with
      | ci :: rest, _ when List.for_all (fun (x : ctor_info) -> x.ci_arg_tys = ci.ci_arg_tys) rest -> Some ci
      | [], [ ci ] -> Some ci
      | [], ci :: rest when List.for_all (fun (x : ctor_info) -> x.ci_arg_tys = ci.ci_arg_tys && x.ci_module = ci.ci_module) rest -> Some ci
      | _ -> None
    in
    match pick with
    | Some ci -> T.decl_field_types s.d (gen s) ~params:ci.ci_params ~field_tys:ci.ci_arg_tys ~args ~own
    | None -> None)
  | _ -> None

let record_field (s : st) (t : T.t) (field : string) : T.t option =
  match t with
  | T.Record fs -> List.assoc_opt field fs
  | T.Con (n, args, own) -> (
    (* By the type's own name only: a bare-name fallback could read another
       module's record of the same name. *)
    match StrMap.find_opt n s.env.records with
    | Some (params, fields) -> (
      match List.assoc_opt field fields with
      | Some fty -> (
        match T.decl_field_types s.d (gen s) ~params ~field_tys:[ fty ] ~args ~own with
        | Some [ ft ] -> Some ft
        | _ -> None)
      | None -> None)
    | None -> None)
  | _ -> None

(* Bind a pattern's variables against the annotated type of what it matches. *)
let rec bind_pat (s : st) (c : ctx) (p : Ast.pattern) (t : T.t) : ctx =
  let t = match t with T.Hole { h_ty = Some t'; _ } -> t' | t -> t in
  let bind (n : Ast.name) (bt : T.t) (c : ctx) : ctx =
    let bt = if plain_at s n.Ast.span then T.Plain else bt in
    record_annot s n.Ast.span bt;
    if bt <> T.Plain then Hashtbl.replace s.binders n.Ast.span (n.Ast.txt, c.owner);
    { c with scope = (n.Ast.txt, Bound (bt, c.depth)) :: c.scope }
  in
  let all_opaque (c : ctx) : ctx = List.fold_left (fun c n -> bind n T.Opaque c) c (pat_binders p) in
  match p, t with
  | Ast.PatWild _, _ | Ast.PatLit _, _ -> c
  | Ast.PatVar n, _ -> bind n t c
  | Ast.PatAs (inner, n, _), _ -> bind_pat s (bind n t c) inner t
  | _, T.Plain -> List.fold_left (fun c n -> bind n T.Plain c) c (pat_binders p)
  | Ast.PatTuple (ps, _), T.Tuple ts when List.length ps = List.length ts ->
    List.fold_left2 (bind_pat s) c ps ts
  | Ast.PatRecord (fs, _), _ ->
    List.fold_left
      (fun c ((fname : Ast.name), fp) ->
         match record_field s t fname.Ast.txt with
         | Some ft -> bind_pat s c fp ft
         | None -> List.fold_left (fun c n -> bind n T.Opaque c) c (pat_binders fp))
      c fs
  | Ast.PatCon (ctor, ps), T.Con _ -> (
    match ctor_fields s ctor.Ast.txt t with
    | Some fts when List.length fts = List.length ps -> List.fold_left2 (bind_pat s) c ps fts
    | _ -> all_opaque c)
  | Ast.PatOr (ps, _), _ -> (
    (* Every alternative binds the same names, but not always from the same
       part of the value (`((f, _), 0) | ((_, f), 1)`): the body sees the
       first alternative's binders, and each other alternative's flow into
       them. *)
    match ps with
    | [] -> c
    | first :: rest ->
      let c1 = bind_pat s c first t in
      List.iter
        (fun alt ->
           let c2 = bind_pat s c alt t in
           List.iter
             (fun (n : Ast.name) ->
                match List.assoc_opt n.Ast.txt c2.scope, List.assoc_opt n.Ast.txt c1.scope with
                | Some (Bound (b2, _)), Some (Bound (b1, _)) -> flow s b2 b1
                | _ -> ())
             (pat_binders alt))
        rest;
      c1)
  | _ -> all_opaque c

let rec walk (s : st) (c : ctx) (e : Ast.expr) : T.t =
  let sp = span_of_expr e in
  let t = walk_inner s c e in
  let t = if t <> T.Plain && plain_at s sp then T.Plain else t in
  record_annot s sp t;
  t

and unmodelled (s : st) (c : ctx) (sp : Ast.span) ~(cause : string) : T.t =
  if plain_at s sp then T.Plain
  else begin
    add_unknown s.store c.valv ~cause sp;
    T.Opaque
  end

and walk_inner (s : st) (c : ctx) (e : Ast.expr) : T.t =
  match e with
  | Ast.ELit _ | Ast.EHole _ | Ast.EResultRef _ | Ast.EDbg (None, _) -> T.Plain
  | Ast.EVar n -> walk_var s c n
  | Ast.EApp (f, args, sp) -> walk_app s c f args sp
  | Ast.EPipe (l, r, sp) -> (
    match r with
    | Ast.EApp (g, args, _) -> walk_app s c g (l :: args) sp
    | _ -> walk_app s c r [ l ] sp)
  | Ast.ELam (ps, body, sp) ->
    let names = List.map (fun (p : Ast.param) -> p.Ast.param_name) ps in
    let t, set = walk_fn_value s c ~params:names ~body in
    s.sites <-
      { rs_span = sp; rs_key = span_of_expr body; rs_kind = Lambda; rs_owner = c.owner; rs_set = set; rs_ty = t }
      :: s.sites;
    t
  | Ast.ELetFn (name, ps, _, body, _) ->
    (* As a standalone expression its value is the function. *)
    let t, _ = walk_let_fn s c name ps body in
    t
  | Ast.EBlock (es, _) -> walk_block s c es
  | Ast.ELet (b, _) ->
    ignore (walk s c b.Ast.bind_expr);
    T.Plain
  | Ast.EMatch (scrut, branches, sp) ->
    let ts = walk s c scrut in
    let join = of_span s sp in
    List.iter
      (fun (br : Ast.branch) ->
         let c' = bind_pat s c br.Ast.branch_pat ts in
         Option.iter (fun g -> ignore (walk s c' g)) br.Ast.branch_guard;
         flow s (walk s c' br.Ast.branch_body) join)
      branches;
    join
  | Ast.EIf (cond, a, b, sp) ->
    ignore (walk s c cond);
    let join = of_span s sp in
    flow s (walk s c a) join;
    flow s (walk s c b) join;
    join
  | Ast.ECond (arms, sp) ->
    let join = of_span s sp in
    List.iter
      (fun (ce, be) ->
         ignore (walk s c ce);
         flow s (walk s c be) join)
      arms;
    join
  | Ast.ECon (name, args, sp) ->
    let ats = List.map (walk s c) args in
    let r = of_span s sp in
    (match r with
     | T.Plain -> ()
     | _ -> (
       match ctor_fields s name.Ast.txt r with
       | Some fts when List.length fts = List.length ats -> List.iter2 (flow s) ats fts
       | _ ->
         (* The declaration could not be read: everything in the arguments
            may be anywhere in the value. *)
         List.iter
           (fun a ->
              if T.has_opaque a then List.iter (fun v -> add_const s.store v S.unknown) (T.svars r);
              List.iter (fun u -> List.iter (fun v -> add_edge s.store u v) (T.svars r)) (T.svars a))
           ats));
    r
  | Ast.EAtom (_, args, sp) ->
    let ats = List.map (walk s c) args in
    if List.for_all (fun a -> a = T.Plain) ats then T.Plain else unmodelled s c sp ~cause:"an atom holding a function value"
  | Ast.ETuple (es, _) ->
    let ts = List.map (walk s c) es in
    if List.for_all (fun a -> a = T.Plain) ts then T.Plain else T.Tuple ts
  | Ast.ERecord (fields, sp) -> (
    let fts = List.map (fun ((n : Ast.name), ex) -> (n.Ast.txt, walk s c ex)) fields in
    match of_span s sp with
    | T.Plain -> T.Plain
    | T.Record rfs as r ->
      List.iter (fun (n, ft) -> match List.assoc_opt n rfs with Some d -> flow s ft d | None -> ()) fts;
      r
    | r ->
      List.iter
        (fun (n, ft) ->
           match record_field s r n with
           | Some d -> flow s ft d
           | None -> flow s ft r)
        fts;
      r)
  | Ast.ERecordUpdate (base, fields, sp) ->
    let bt = walk s c base in
    let r = of_span s sp in
    flow s bt r;
    List.iter
      (fun ((n : Ast.name), ex) ->
         let ft = walk s c ex in
         match record_field s r n.Ast.txt with Some d -> flow s ft d | None -> flow s ft r)
      fields;
    r
  | Ast.EField (ex, name, sp) -> (
    let t = walk s c ex in
    if plain_at s sp then T.Plain
    else
      match record_field s (resolve_holes t) name.Ast.txt with
      | Some ft -> ft
      | None -> unmodelled s c sp ~cause:"a field read the pass could not resolve")
  | Ast.ERestrict (es, body, _) ->
    List.iter (fun x -> ignore (walk s c x)) es;
    let auth =
      match March_caps.Scope_expr.restrict_entries es with
      (* A function value made by module-level code captures nothing: it
         runs under its caller's authority, so a module-level restrict does
         not bound it (parent design §21).  One made by a function value
         that module-level code created does capture, when that one runs. *)
      | Some _ when c.at_module && c.lams = [] -> c.auth
      | Some entries -> S.narrow c.auth ~by:(S.of_entries entries)
      | None -> c.auth
    in
    walk s { c with auth } body
  | Ast.EAnnot (ex, _, _) -> walk s c ex
  | Ast.EDbg (Some ex, _) -> walk s c ex
  | Ast.ESend (a, b, _) ->
    ignore (walk s c a);
    ignore (walk s c b);
    T.Plain
  | Ast.ESpawn (ex, sp) ->
    (match ex with
     | Ast.ECon (actor, init_args, _) ->
       List.iter (fun a -> ignore (walk s c a)) init_args;
       charge_actor s c actor.Ast.txt sp
     | other -> ignore (walk s c other));
    of_span s sp
  | Ast.ELetQ (p, rhs, k, sp) ->
    let rt = walk s c rhs in
    let payload =
      match resolve_holes rt with T.Con (_, [ ok; _ ], _) -> ok | T.Plain -> T.Plain | _ -> T.Opaque
    in
    let c' = bind_pat s c p payload in
    let kt = walk s c' k in
    let r = of_span s sp in
    flow s kt r;
    flow s rt r;
    r
  | Ast.ELetStar (p, rhs, k, sp) ->
    ignore (walk s c rhs);
    let c' = List.fold_left (fun c n -> bind_name s c n T.Opaque) c (pat_binders p) in
    let kt = walk s c' k in
    let r = of_span s sp in
    flow s kt r;
    r
  | Ast.EAssert (ex, _) ->
    ignore (walk s c ex);
    T.Plain
  | Ast.ESigil (_, ex, sp) ->
    ignore (walk s c ex);
    unmodelled s c sp ~cause:"a sigil"
  | Ast.ERefineMsg (ex, _, _) -> walk s c ex
  | Ast.EProof (p, _) ->
    List.iter (fun x -> ignore (walk s c x)) (Ast.proof_children p);
    T.Plain

and bind_name (s : st) (c : ctx) (n : Ast.name) (t : T.t) : ctx =
  let t = if plain_at s n.Ast.span then T.Plain else t in
  record_annot s n.Ast.span t;
  { c with scope = (n.Ast.txt, Bound (t, c.depth)) :: c.scope }

and walk_block (s : st) (c : ctx) (es : Ast.expr list) : T.t =
  match es with
  | [] -> T.Plain
  | [ last ] -> walk s c last
  | Ast.ELet (b, _) :: rest ->
    let t = walk s c b.Ast.bind_expr in
    walk_block s (bind_pat s c b.Ast.bind_pat t) rest
  | Ast.ELetFn (name, ps, _, body, _) :: rest ->
    let _, c' = walk_let_fn s c name ps body in
    walk_block s c' rest
  | x :: rest ->
    ignore (walk s c x);
    walk_block s c rest

(* A lambda or a local fn: its annotated type and its set. *)
and walk_fn_value ?(self : Ast.name option) (s : st) (c : ctx) ~(params : Ast.name list) ~(body : Ast.expr)
    : T.t * svar =
  let set = fresh s and own = fresh s and valv = fresh s in
  let holes = List.map (fun (n : Ast.name) -> (n, T.new_hole ())) params in
  (* The function's type exists before its body is walked, so a local fn's
     calls to itself flow their arguments into its real parameters and take
     its real result (the result is a hole the walked body fills). *)
  let result = T.new_hole () in
  let t =
    match holes with
    | [] -> T.Arrow (T.Plain, result, set)
    | _ -> List.fold_right (fun (_, h) acc -> T.Arrow (h, acc, set)) holes result
  in
  let depth = c.depth + 1 in
  let outer_scope =
    match self with Some n -> (n.Ast.txt, Bound (t, c.depth)) :: c.scope | None -> c.scope
  in
  let scope =
    List.fold_left (fun sc ((n : Ast.name), h) -> (n.Ast.txt, Bound (h, depth)) :: sc) outer_scope holes
  in
  (* What a function value creates is in the set of the one that creates it
     (design §6.1). *)
  (match c.lams with (_, outer) :: _ -> add_edge s.store set outer | [] -> ());
  let c' = { c with act = None; own; valv; scope; lams = (depth, set) :: c.lams; depth } in
  let bt = walk s c' body in
  (match result with T.Hole h -> fill_hole s h bt | _ -> ());
  List.iter (fun ((n : Ast.name), h) -> record_annot s n.Ast.span h) holes;
  add_edge s.store ~narrow:c.auth own set;
  (* What arrives through a called or captured value is never narrowed: it
     runs under its own authority (design §6.1).  [`Narrow_values] is the
     unsound rule, kept only to show the oracle catches it. *)
  if s.unsound = Some `Narrow_values then add_edge s.store ~narrow:c.auth valv set
  else add_edge s.store valv set;
  (resolve_holes_result t, set)

and walk_let_fn (s : st) (c : ctx) (name : Ast.name) (ps : Ast.param list) (body : Ast.expr) : T.t * ctx =
  let names = List.map (fun (p : Ast.param) -> p.Ast.param_name) ps in
  let t, set = walk_fn_value ~self:name s c ~params:names ~body in
  s.sites <-
    { rs_span = name.Ast.span; rs_key = span_of_expr body; rs_kind = Local_fn name.Ast.txt; rs_owner = c.owner;
      rs_set = set; rs_ty = t }
    :: s.sites;
  record_annot s name.Ast.span t;
  (t, { c with scope = (name.Ast.txt, Bound (t, c.depth)) :: c.scope })

and use_local (s : st) (c : ctx) (n : Ast.name) (b : binding) : T.t =
  match b with
  | Full ->
    if plain_at s n.Ast.span then T.Plain
    else begin
      let t = of_span s n.Ast.span in
      List.iter (fun v -> add_const s.store v S.full) (T.svars t);
      if T.has_opaque t then add_unknown s.store c.valv ~cause:"an actor's state or message of unknown type" n.Ast.span;
      t
    end
  | Bound (t, depth) ->
    (match t with
     | T.Hole ({ h_ty = None; _ } as h) ->
       h.h_hm <- ty_at s n.Ast.span;
       fill_hole s h (of_span s n.Ast.span)
     | _ -> ());
    List.iter
        (fun (ld, set) ->
           if ld > depth && s.unsound <> Some `Narrow_values then begin
             let why = { why = Printf.sprintf "captures `%s`" n.Ast.txt; rspan = n.Ast.span } in
             List.iter (fun v -> add_edge s.store ~why v set) (T.held t);
             if T.has_opaque t then add_unknown s.store set ~cause:"a captured value the pass does not model" n.Ast.span
           end)
        c.lams;
    t

and walk_var (s : st) (c : ctx) (n : Ast.name) : T.t =
  match List.assoc_opt n.Ast.txt c.scope with
  | Some b -> use_local s c n b
  | None -> (
    if plain_at s n.Ast.span then T.Plain
    else
      match resolve s c.owner n.Ast.txt with
      | Some key when Hashtbl.mem s.let_keys key -> (
        match state_of s key with
        | Done (sc :: _) ->
          let i = { i_fresh = Hashtbl.create 8; i_mapped = Hashtbl.create 4 } in
          let t = subst s i sc.sc_result (ty_at s n.Ast.span) in
          finish_inst s i sc ~why:{ why = Printf.sprintf "uses `%s`" n.Ast.txt; rspan = n.Ast.span };
          t
        | Active (a :: _, _) -> a.a_result
        | _ -> unmodelled s c n.Ast.span ~cause:"a top-level value with no recorded body")
      | Some key -> named_value s c n key
      | None -> builtin_value s c n)

(* A named function read as a value (design §6.1): its reach, narrowed by
   its clause and by the static authority here. *)
and named_value (s : st) (c : ctx) (n : Ast.name) (key : string) : T.t =
  let set = fresh s in
  let why = { why = Printf.sprintf "is `%s`" n.Ast.txt; rspan = n.Ast.span } in
  (match c.lams with (_, outer) :: _ -> add_edge s.store set outer | [] -> ());
  let hm = ty_at s n.Ast.span in
  let peel ty = match Option.map repr ty with Some (TArrow (a, b)) -> (Some a, Some b) | _ -> (None, None) in
  let build ~(params : T.t list) ~(result : T.t) ~(sub : T.t -> ty option -> T.t) : T.t option =
    match params with
    | [] -> (
      match Option.map repr hm with
      | Some (TArrow (_, r)) -> Some (T.Arrow (T.Plain, sub result (Some r), set))
      | _ -> None)
    | _ ->
      let rec go ps ty =
        match ps with
        | [] -> Some (sub result ty)
        | p :: rest -> (
          match peel ty with
          | (Some a, b) -> Option.map (fun r -> T.Arrow (sub p (Some a), r, set)) (go rest b)
          | _ -> None)
      in
      go params hm
  in
  let t =
    match state_of s key with
    | Done schemes ->
      let ts =
        List.filter_map
          (fun sc ->
             let i = { i_fresh = Hashtbl.create 8; i_mapped = Hashtbl.create 4 } in
             let t = build ~params:sc.sc_params ~result:sc.sc_result ~sub:(subst s i) in
             finish_inst s i sc ~why;
             (match t with
              | Some _ ->
                add_const s.store ~why set (S.narrow sc.sc_own ~by:c.auth);
                if sc.sc_kind_params <> [] then
                  add_unknown s.store set ~cause:"an authority check of a computed kind" n.Ast.span;
                add_edge s.store (inst_var s i sc.sc_val) set
              | None -> ());
             t)
          schemes
      in
      (match ts with t :: _ -> Some t | [] -> None)
    | Active (acts, _) ->
      let ts =
        List.filter_map
          (fun a ->
             let t = build ~params:a.a_params ~result:a.a_result ~sub:(fun t _ -> t) in
             add_edge s.store ~narrow:c.auth a.a_own set;
             add_edge s.store a.a_val set;
             t)
          acts
      in
      (match ts with t :: _ -> Some t | [] -> None)
  in
  s.sites <-
    { rs_span = n.Ast.span; rs_key = n.Ast.span; rs_kind = Named_value n.Ast.txt; rs_owner = c.owner; rs_set = set;
      rs_ty = Option.value ~default:T.Opaque t }
    :: s.sites;
  match t with
  | Some t -> t
  | None ->
    add_unknown s.store set ~cause:"a named function used as a value whose type the pass could not rebuild" n.Ast.span;
    add_unknown s.store c.valv ~cause:"a named function used as a value whose type the pass could not rebuild" n.Ast.span;
    T.Opaque

(* A name that is not local and not a recorded function: a builtin, an
   extern, an actor's `state`, a constructor function. *)
and builtin_value (s : st) (c : ctx) (n : Ast.name) : T.t =
  let t = of_span s n.Ast.span in
  (match t with
   | T.Arrow (_, _, set) ->
     (match List.assoc_opt n.Ast.txt Typecheck_builtins.builtin_cap_table with
      | Some kind ->
        add_const s.store set (S.narrow (S.of_scopes [ { S.kind; arg = None } ]) ~by:c.auth)
          ~why:{ why = Printf.sprintf "is `%s`" n.Ast.txt; rspan = n.Ast.span }
      | None -> ());
     (* It may call anything it is given. *)
     List.iter (fun v -> if v <> set then add_edge s.store v set) (T.svars t);
     s.sites <-
       { rs_span = n.Ast.span; rs_key = n.Ast.span; rs_kind = Named_value n.Ast.txt; rs_owner = c.owner; rs_set = set;
         rs_ty = t }
       :: s.sites
   | T.Plain -> ()
   | _ ->
     List.iter (fun v -> add_const s.store v S.full) (T.svars t);
     if T.has_opaque t then add_unknown s.store c.valv ~cause:"a name the pass could not resolve" n.Ast.span);
  t

(* Apply a function-typed value to arguments: each arrow consumed adds its
   set to the effect of the code that calls it. *)
and apply_value (s : st) (c : ctx) (ft : T.t) (args : T.t list) (sp : Ast.span) ~(what : string) : T.t =
  let why = { why = what; rspan = sp } in
  let rec go ft args =
    let ft = match ft with T.Hole { h_ty = Some t; _ } -> t | t -> t in
    match ft, args with
    | T.Arrow (_, r, set), [] ->
      if s.unsound <> Some `Drop_callee_effect then add_edge s.store ~why set c.valv;
      r
    | T.Arrow (p, r, set), a :: rest ->
      if s.unsound <> Some `Drop_callee_effect then add_edge s.store ~why set c.valv;
      if s.unsound <> Some `Drop_arg_flow then flow s a p;
      if rest = [] then r else go r rest
    | T.Plain, _ -> T.Plain
    | _ ->
      (* Not an arrow the pass can see: whatever it is may run, and it may
         run anything it is handed. *)
      if plain_at s sp && List.for_all (fun a -> a = T.Plain) args && ft = T.Plain then T.Plain
      else begin
        add_unknown s.store c.valv ~cause:"a call of a value whose function type the pass could not rebuild" sp;
        T.Opaque
      end
  in
  go ft args

and walk_app (s : st) (c : ctx) (f : Ast.expr) (args : Ast.expr list) (sp : Ast.span) : T.t =
  let local = match f with Ast.EVar n -> List.assoc_opt n.Ast.txt c.scope | _ -> None in
  match f, local with
  | Ast.EVar n, Some b ->
    let ft = use_local s c n b in
    let ats = List.map (walk s c) args in
    apply_value s c ft ats sp ~what:(Printf.sprintf "calls `%s`" n.Ast.txt)
  | Ast.EVar n, None -> (
    let ats = List.map (walk s c) args in
    match resolve s c.owner n.Ast.txt with
    | Some key when Hashtbl.mem s.let_keys key ->
      let ft = walk_var s c n in
      apply_value s c ft ats sp ~what:(Printf.sprintf "calls `%s`" n.Ast.txt)
    | Some "Authority.check" ->
      (* A direct authority check is an operation of the kind it names
         (every capability entry point of the stdlib is one). *)
      (match args with kind :: _ -> charge_kind s c kind sp | [] -> ());
      T.Plain
    | Some key -> call_named s c n key args ats sp
    | None -> call_builtin s c n args ats sp)
  | _ ->
    let ft = walk s c f in
    let ats = List.map (walk s c) args in
    let what =
      match f with
      | Ast.EField (_, fld, _) -> Printf.sprintf "calls `.%s`" fld.Ast.txt
      | _ -> "calls a function value"
    in
    apply_value s c ft ats sp ~what

(* The operation an authority check of kind [kind_expr] is: a literal names
   it; the enclosing named function's own parameter makes the function
   kind-parametric (its callers name the kind); anything else is not
   tracked. *)
and charge_kind (s : st) (c : ctx) (kind_expr : Ast.expr) (sp : Ast.span) : unit =
  let param_index (name : string) : int option =
    match c.act, List.assoc_opt name c.scope with
    | Some a, Some (Bound (_, 0)) ->
      let rec find i = function [] -> None | x :: rest -> if x = name then Some i else find (i + 1) rest in
      find 0 a.a_names
    | _ -> None
  in
  match kind_expr with
  | Ast.ELit (Ast.LitString kind, _) when March_caps.Cap_lattice.suggest_cap kind = None ->
    add_const s.store c.own
      (S.of_scopes [ { S.kind; arg = None } ])
      ~why:{ why = Printf.sprintf "checks `%s`" kind; rspan = sp }
  | Ast.EVar p when c.lams = [] && param_index p.Ast.txt <> None -> (
    match c.act, param_index p.Ast.txt with
    | Some a, Some i -> a.a_kind_params <- i :: a.a_kind_params
    | _ -> ())
  | _ -> add_unknown s.store c.own ~cause:"an authority check of a computed kind" sp

and call_named (s : st) (c : ctx) (n : Ast.name) (key : string) (args : Ast.expr list) (ats : T.t list)
    (sp : Ast.span) : T.t =
  let why = { why = Printf.sprintf "calls `%s`" n.Ast.txt; rspan = sp } in
  let lit = literal_scope n.Ast.txt args in
  let nargs = List.length ats in
  let result_ty = ty_at s sp in
  let join = if plain_at s sp then T.Plain else of_span s sp in
  let finish (r : T.t) (params_len : int) : unit =
    (* More arguments than parameters: the rest are applied to the result. *)
    let r =
      if nargs > params_len then
        apply_value s c r (List.filteri (fun k _ -> k >= params_len) ats) sp ~what:why.why
      else r
    in
    flow s r join
  in
  (match state_of s key with
   | Done [] | Active ([], _) ->
     (* A dispatch node (an interface method), an extern, or a function
        with no recorded body. *)
     call_bodiless s c n key args ats sp join
   | Done schemes ->
     let pick = List.filter (fun sc -> List.length sc.sc_params = nargs) schemes in
     let pick = if pick = [] then schemes else pick in
     List.iter
       (fun sc ->
          let i = { i_fresh = Hashtbl.create 8; i_mapped = Hashtbl.create 4 } in
          List.iteri
            (fun k p -> match List.nth_opt ats k with Some a -> bind_actual s i p a | None -> ())
            sc.sc_params;
          List.iteri
            (fun k p ->
               match List.nth_opt ats k with
               | Some a -> if s.unsound <> Some `Drop_arg_flow then flow s a (subst s i p None)
               | None -> ())
            sc.sc_params;
          let r = subst s i sc.sc_result (if nargs <= List.length sc.sc_params then result_ty else None) in
          finish_inst s i sc ~why;
          add_const s.store ~why c.own (scope_own sc.sc_own lit);
          List.iter
            (fun k -> match List.nth_opt args k with Some a -> charge_kind s c a sp | None -> ())
            sc.sc_kind_params;
          if s.unsound <> Some `Drop_callee_effect then add_edge s.store ~why (inst_var s i sc.sc_val) c.valv;
          finish r (List.length sc.sc_params))
       pick
   | Active (acts, _) ->
     let pick = List.filter (fun a -> List.length a.a_params = nargs) acts in
     let pick = if pick = [] then acts else pick in
     List.iter
       (fun a ->
          if s.unsound <> Some `Drop_arg_flow then
            List.iteri (fun k p -> match List.nth_opt ats k with Some x -> flow s x p | None -> ()) a.a_params;
          add_edge s.store ~why a.a_own c.own;
          add_edge s.store ~why a.a_val c.valv;
          (* Inside a recursive group the kind parameters are not final. *)
          if a.a_kind_params <> [] then
            add_unknown s.store c.own ~cause:"an authority check of a computed kind" sp;
          finish a.a_result (List.length a.a_params))
       pick);
  join

(* A resolved name with no body of its own. *)
and call_bodiless (s : st) (c : ctx) (n : Ast.name) (key : string) (args : Ast.expr list) (ats : T.t list)
    (sp : Ast.span) (join : T.t) : unit =
  let why = { why = Printf.sprintf "calls `%s`" n.Ast.txt; rspan = sp } in
  let impls =
    List.filter_map
      (fun r ->
         match resolve s key r with
         | Some k when k <> key && bodies_of s k <> [] -> Some k
         | _ -> None)
      (Option.value ~default:[] (Hashtbl.find_opt s.env.fn_refs key))
  in
  if impls <> [] then
    (* An interface method: any impl may run (builder's call 7). *)
    List.iter
      (fun k ->
         let name = { n with Ast.txt = k } in
         let r = call_named s c name k args ats sp in
         flow s r join)
      impls
  else begin
    (* An extern or another bodiless name: its recorded kinds, and the
       builtin rule for what it is handed. *)
    let kinds = Option.value ~default:[] (Hashtbl.find_opt s.env.own_cap_closures key) in
    add_const s.store ~why c.own (S.of_scopes (List.map (fun kind -> { S.kind; arg = None }) kinds));
    builtin_flows ~name:n.Ast.txt s c ats sp join
  end

(* The default capture signature of a builtin (builder's call 8): it may
   call any function value it is handed, and anything in its arguments may
   be in its result.  A function value in the result that no argument
   accounts for came from somewhere the pass cannot see. *)
and builtin_flows ?(name = "") (s : st) (c : ctx) (ats : T.t list) (sp : Ast.span) (join : T.t) : unit =
  let arg_vars = List.concat_map T.svars ats in
  if List.exists T.has_opaque ats then begin
    add_unknown s.store c.valv ~cause:"a builtin handed a value the pass does not model" sp;
    List.iter (fun v -> add_const s.store v S.unknown) (T.svars join)
  end;
  (* A builtin calls only what it can see is a function: an arrow, or a
     declared value holding one.  A value of a type variable is opaque to it. *)
  let rec callable (t : T.t) : svar list =
    match t with
    | T.Plain | T.Opaque | T.Var _ | T.Hole { h_ty = None; _ } -> []
    | T.Hole { h_ty = Some t'; _ } -> callable t'
    | T.Arrow (a, b, v) -> (v :: callable a) @ callable b
    | T.Con (_, args, so) -> Option.to_list so @ List.concat_map callable args
    | T.Tuple ts -> List.concat_map callable ts
    | T.Record fs -> List.concat_map (fun (_, x) -> callable x) fs
  in
  List.iter (fun v -> add_edge s.store v c.valv) (List.concat_map callable ats);
  (* A builtin may store one argument in another (`vault_set(table, key,
     value)` returns unit): what any argument holds may end up in any other. *)
  List.iteri
    (fun i a ->
       List.iteri
         (fun j b -> if i <> j then List.iter (fun u -> List.iter (fun v -> add_edge s.store u v) (T.svars b)) (T.held a))
         ats)
    ats;
  let rvars = T.svars join in
  List.iter (fun u -> List.iter (fun v -> add_edge s.store u v) rvars) arg_vars;
  if debug && arg_vars = [] && T.svars join <> [] then
    Printf.eprintf "[capture] builtin with a set-carrying result and no set-carrying argument: %s\n" name;
  if arg_vars = [] && not (List.mem name fresh_result_builtins) then begin
    let rec conjured (t : T.t) =
      match t with
      | T.Arrow (a, b, v) ->
        add_unknown s.store v ~cause:"a function value a builtin returned from nowhere the pass can see" sp;
        conjured a;
        conjured b
      | T.Con (n, args, so) ->
        (match so with
         | Some v when T.declared s.d n ->
           add_unknown s.store v ~cause:"a function value a builtin returned from nowhere the pass can see" sp
         | _ -> ());
        List.iter conjured args
      | T.Tuple ts -> List.iter conjured ts
      | T.Record fs -> List.iter (fun (_, x) -> conjured x) fs
      | T.Var (_, v) ->
        add_unknown s.store v ~cause:"a function value a builtin returned from nowhere the pass can see" sp
      | T.Plain | T.Opaque | T.Hole _ -> ()
    in
    conjured join
  end

and call_builtin (s : st) (c : ctx) (n : Ast.name) (args : Ast.expr list) (ats : T.t list) (sp : Ast.span) : T.t =
  let why = { why = Printf.sprintf "calls `%s`" n.Ast.txt; rspan = sp } in
  (match List.assoc_opt n.Ast.txt Typecheck_builtins.builtin_cap_table with
   | Some kind ->
     let own = S.of_scopes [ { S.kind; arg = None } ] in
     add_const s.store ~why c.own (scope_own own (literal_scope n.Ast.txt args))
   | None -> ());
  if List.mem n.Ast.txt dispatching_builtins then
    add_unknown s.store c.valv ~cause:"a builtin that runs callbacks registered elsewhere" sp;
  let join = if plain_at s sp then T.Plain else of_span s sp in
  if join <> T.Plain || List.exists (fun a -> a <> T.Plain) ats then builtin_flows ~name:n.Ast.txt s c ats sp join;
  join

(* `spawn(A)`: the actor's handlers and `init` run under the authority
   current here, so their reach belongs to whoever spawns (design §6.1). *)
and charge_actor (s : st) (c : ctx) (actor : string) (sp : Ast.span) : unit =
  let why = { why = Printf.sprintf "spawns `%s`" actor; rspan = sp } in
  match Option.bind (resolve_actor s c.owner actor) (fun q -> Option.map (fun a -> (q, a)) (Hashtbl.find_opt s.actors q)) with
  | None -> add_unknown s.store c.valv ~cause:"a spawned actor the pass could not find" sp
  | Some (q, info) ->
    List.iter
      (fun hk ->
         match state_of s hk with
         | Done schemes ->
           List.iter
             (fun sc ->
                add_const s.store ~why c.own sc.sc_own;
                let i = { i_fresh = Hashtbl.create 4; i_mapped = Hashtbl.create 1 } in
                finish_inst s i sc ~why;
                add_edge s.store ~why (inst_var s i sc.sc_val) c.valv)
             schemes
         | Active (acts, _) ->
           List.iter
             (fun a ->
                add_edge s.store ~why a.a_own c.own;
                add_edge s.store ~why a.a_val c.valv)
             acts)
      info.ac_handlers;
    (* `init` runs at the spawn, in the actor. *)
    let init_scope = List.map (fun p -> (p, Full)) info.ac_init_params in
    ignore
      (walk s
         { c with owner = q; scope = init_scope @ [ ("state", Full); ("self", Full) ]; at_module = false }
         info.ac_init)

and resolve_actor (s : st) (owner : string) (actor : string) : string option =
  let prefix = March_caps.Cap_rows.ref_prefix ~scopes:s.env.fn_scopes owner in
  if Hashtbl.mem s.actors (prefix ^ actor) then Some (prefix ^ actor)
  else if Hashtbl.mem s.actors actor then Some actor
  else
    Hashtbl.fold
      (fun q _ acc -> if acc = None && T.bare q = T.bare actor then Some q else acc)
      s.actors None

(* ── per-function analysis, one recursive group at a time ───────────────── *)

and state_of (s : st) (key : string) : fstate =
  match Hashtbl.find_opt s.states key with
  | Some (Done _ as d) -> d
  | Some (Active (_, root) as a) ->
    (match s.frames with f :: _ -> f.f_root <- min f.f_root root | [] -> ());
    a
  | None ->
    let bodies = bodies_of s key in
    let depth = List.length s.frames + 1 in
    let frame = { f_depth = depth; f_root = depth; f_vars = []; f_members = [] } in
    s.frames <- frame :: s.frames;
    let is_handler = Hashtbl.mem s.handler_keys key in
    let acts =
      List.map
        (fun (params, (body : Ast.expr)) ->
           let result = if plain_at s (span_of_expr body) then T.Plain else of_span s (span_of_expr body) in
           ( { a_params = List.map (fun _ -> T.new_hole ()) params; a_result = result;
               a_result_ty = ty_at s (span_of_expr body); a_own = fresh s; a_val = fresh s; a_names = params;
               a_kind_params = [] },
             params, body ))
        bodies
    in
    Hashtbl.replace s.states key (Active (List.map (fun (a, _, _) -> a) acts, depth));
    let auth = match grant_of s key with Some g -> g | None -> S.full in
    let auth = match clause_of s key with Some cl -> S.narrow auth ~by:cl | None -> auth in
    let is_let = Hashtbl.mem s.let_keys key in
    List.iter
      (fun (a, params, body) ->
         let scope =
           if is_handler then
             List.map (fun p -> (p, Full)) params @ [ ("state", Full); ("self", Full) ]
           else List.map2 (fun p h -> (p, Bound (h, 0))) params a.a_params
         in
         let c =
           { owner = key; act = Some a; own = a.a_own; valv = a.a_val; scope; lams = []; depth = 0;
             auth = (if is_let then S.full else auth); at_module = is_let }
         in
         let bt = walk s c body in
         flow s bt a.a_result)
      acts;
    s.frames <- List.tl s.frames;
    let acts = List.map (fun (a, _, _) -> a) acts in
    if frame.f_root < depth then begin
      (* Part of a recursive group whose root is still being walked. *)
      let parent = match s.frames with f :: _ -> f | [] -> s.top in
      parent.f_root <- min parent.f_root frame.f_root;
      parent.f_vars <- frame.f_vars @ parent.f_vars;
      parent.f_members <- ((key, acts) :: frame.f_members) @ parent.f_members;
      let st' = Active (acts, frame.f_root) in
      Hashtbl.replace s.states key st';
      st'
    end
    else begin
      let value = solve s.store ~ground:false frame.f_vars in
      List.iter
        (fun (k, acts) ->
           let schemes = List.map (generalise s k value) acts in
           Hashtbl.replace s.states k (Done schemes);
           Hashtbl.replace s.fn_iface k schemes)
        ((key, acts) :: frame.f_members);
      (* Its variables stay solvable for the sites inside it. *)
      s.top.f_vars <- frame.f_vars @ s.top.f_vars;
      Option.get (Hashtbl.find_opt s.states key)
    end

(* ── the result ─────────────────────────────────────────────────────────── *)

type site = {
  s_span : Ast.span;
  s_key : Ast.span;
  s_kind : site_kind;
  s_owner : string;
  s_set : string;
  s_ground : S.t;
  s_reasons : (string * string * Ast.span) list;  (** element, why, where *)
}

type result = {
  sites : site list;
  type_at : Ast.span -> string option;
  hover_type_at : Ast.span -> string option;
  binders : (Ast.span * string * string) list;  (** where, name, annotated type: bindings that hold a set *)
  fn_types : (string * string) list;  (** "fn f" or "let x", and its printed capture type *)
  unknown_causes : (string * int) list;  (** over everything analysed, the stdlib included *)
  unknown_at : (string * Ast.span) list;  (** each place something was not tracked, and why *)
}

let empty : result =
  { sites = []; type_at = (fun _ -> None); hover_type_at = (fun _ -> None); binders = []; fn_types = []; unknown_causes = []; unknown_at = [] }

let cmp_span (a : Ast.span) (b : Ast.span) =
  compare (a.Ast.file, a.Ast.start_line, a.Ast.start_col, a.Ast.end_line, a.Ast.end_col)
    (b.Ast.file, b.Ast.start_line, b.Ast.start_col, b.Ast.end_line, b.Ast.end_col)

let analyse ?unsound ?(all = false) (env : env) (decls : Ast.decl list) : result =
  let top = { f_depth = 0; f_root = 0; f_vars = []; f_members = [] } in
  let s =
    { env; d = T.decls_of env; store = new_store (); states = Hashtbl.create 256; frames = []; top;
      hv = Hashtbl.create 64; known = Hashtbl.create 1024; let_keys = Hashtbl.create 64; clauses = Hashtbl.create 16; extra_bodies = Hashtbl.create 16; actors = Hashtbl.create 16;
      handler_keys = Hashtbl.create 32; sites = []; annot = Hashtbl.create 256; binders = Hashtbl.create 256; fn_iface = Hashtbl.create 256;
      unsound }
  in
  scan_decls s decls;
  Hashtbl.iter (fun k _ -> Hashtbl.replace s.known k ()) env.own_cap_closures;
  Hashtbl.iter (fun k _ -> Hashtbl.replace s.known k ()) env.fn_refs;
  Hashtbl.iter (fun k _ -> Hashtbl.replace s.known k ()) env.fn_row_bodies;
  let keys =
    List.sort compare
      (Hashtbl.fold
         (fun k _ acc -> if all || not (Hashtbl.mem env.stdlib_fns k) then k :: acc else acc)
         env.fn_row_bodies []
       @ Hashtbl.fold (fun k _ acc -> k :: acc) s.extra_bodies [])
  in
  List.iter (fun k -> ignore (state_of s k)) keys;
  let st = s.store in
  let all_vars = List.init st.next Fun.id in
  let local = solve st ~ground:false all_vars in
  let ground = solve st ~ground:true all_vars in
  let get tbl v =
    match Hashtbl.find_opt tbl v with
    | Some x -> x
    | None -> Option.value ~default:S.empty (Hashtbl.find_opt st.consts v)
  in
  (* Predecessors over plain edges, for naming the variables a set depends
     on and for finding the reason of an element. *)
  let preds : (svar, (svar * edge) list) Hashtbl.t = Hashtbl.create 1024 in
  Hashtbl.iter
    (fun u es ->
       List.iter
         (fun e ->
            if not e.ground_only then
              Hashtbl.replace preds e.dst ((u, e) :: Option.value ~default:[] (Hashtbl.find_opt preds e.dst)))
         es)
    st.succ;
  let back (v : svar) : (svar * reason option) list =
    (* every variable that reaches [v], with the reasoned edge nearest [v]
       on the way *)
    let seen = Hashtbl.create 16 in
    let out = ref [] in
    let rec go x (near : reason option) =
      if not (Hashtbl.mem seen x) then begin
        Hashtbl.replace seen x ();
        out := (x, near) :: !out;
        List.iter
          (fun (u, e) -> go u (match near with Some _ -> near | None -> e.ewhy))
          (Option.value ~default:[] (Hashtbl.find_opt preds x))
      end
    in
    go v None;
    List.rev !out
  in
  (* Names for the variables a printed type is polymorphic in: a variable
     with nothing flowing into it that something printed depends on. *)
  let saw_unknown = ref false in
  let printer ?(unknown = "?") () =
    let names : (svar, string) Hashtbl.t = Hashtbl.create 8 in
    let name_of v =
      match Hashtbl.find_opt names v with
      | Some n -> n
      | None ->
        let n = Printf.sprintf "c%d" (Hashtbl.length names + 1) in
        Hashtbl.replace names v n;
        n
    in
    let symbolic : (svar, unit) Hashtbl.t = Hashtbl.create 8 in
    let set v =
      let consts = get local v in
      if S.is_unknown consts then begin
        saw_unknown := true;
        unknown
      end
      else
        let syms =
          List.filter_map
            (fun (u, _) -> if Hashtbl.mem symbolic u then Some (name_of u) else None)
            (back v)
        in
        String.concat ", " (List.filter (fun x -> x <> "") [ S.to_string consts ] @ List.sort_uniq compare syms)
    in
    (symbolic, set)
  in
  (* The input positions of an annotated type: parameters of its arrows. *)
  let rec inputs ?(neg = false) (t : T.t) : svar list =
    match t with
    | T.Plain | T.Opaque | T.Hole { h_ty = None; _ } -> []
    | T.Hole { h_ty = Some t'; _ } -> inputs ~neg t'
    | T.Arrow (a, b, v) -> (if neg then [ v ] else []) @ inputs ~neg:(not neg) a @ inputs ~neg b
    | T.Con (_, args, so) -> (if neg then Option.to_list so else []) @ List.concat_map (inputs ~neg) args
    | T.Tuple ts -> List.concat_map (inputs ~neg) ts
    | T.Record fs -> List.concat_map (fun (_, x) -> inputs ~neg x) fs
    | T.Var (_, v) -> if neg then [ v ] else []
  in
  let owner_inputs (owner : string) : svar list =
    List.concat_map
      (fun sc -> List.concat_map (inputs ~neg:true) sc.sc_params)
      (Option.value ~default:[] (Hashtbl.find_opt s.fn_iface owner))
  in
  let print_ty ?unknown ~(owner : string) (ty : ty) (t : T.t) : string * bool =
    (* Each printed type names its type variables afresh (a, b, ...), so a
       report does not depend on what was printed before it. *)
    reset_tvar_display_names ();
    let symbolic, set = printer ?unknown () in
    List.iter
      (fun v -> if S.is_empty (get local v) then Hashtbl.replace symbolic v ())
      (owner_inputs owner @ inputs t);
    T.pp_flag ~set ty t
  in
  let print_set ~(owner : string) ?(own_ty = T.Plain) (v : svar) : string =
    let symbolic, set = printer () in
    List.iter
      (fun v -> if S.is_empty (get local v) then Hashtbl.replace symbolic v ())
      (owner_inputs owner @ inputs own_ty);
    set v
  in
  let reasons ~(owner : string) ?(own_ty = T.Plain) (v : svar) : (string * string * Ast.span) list =
    let symbolic, _ = printer () in
    let ins = owner_inputs owner @ inputs own_ty in
    List.iter (fun v -> if S.is_empty (get local v) then Hashtbl.replace symbolic v ()) ins;
    let names = Hashtbl.create 4 in
    let reached = back v in
    let out = ref [] in
    let have = Hashtbl.create 8 in
    let note elem why sp =
      if not (Hashtbl.mem have elem) then begin
        Hashtbl.replace have elem ();
        out := (elem, why, sp) :: !out
      end
    in
    List.iter
      (fun (u, near) ->
         List.iter
           (fun (c, (r : reason)) ->
              let r = match near with Some n -> n | None -> r in
              if S.is_unknown c then note "?" r.why r.rspan
              else List.iter (fun sc -> note (S.scope_to_string sc) r.why r.rspan) (S.scopes c))
           (List.rev (Option.value ~default:[] (Hashtbl.find_opt st.const_why u)));
         if Hashtbl.mem symbolic u then begin
           let n =
             match Hashtbl.find_opt names u with
             | Some n -> n
             | None ->
               let n = Printf.sprintf "c%d" (Hashtbl.length names + 1) in
               Hashtbl.replace names u n;
               n
           in
           match near with Some r -> note n r.why r.rspan | None -> ()
         end)
      reached;
    (* One line per element of the solved set.  An element narrowing
       rewrote keeps the reason of the kind it came from. *)
    let all = List.rev !out in
    let final = get local v in
    let kind_of (elem : string) = match String.index_opt elem '(' with Some i -> String.sub elem 0 i | None -> elem in
    let for_scope (sc : S.scope) =
      let text = S.scope_to_string sc in
      match List.find_opt (fun (e, _, _) -> e = text) all with
      | Some r -> Some r
      | None ->
        Option.map
          (fun (_, why, sp) -> (text, why, sp))
          (List.find_opt
             (fun (e, _, _) -> e <> "?" && March_caps.Cap_lattice.cap_subsumes (kind_of e) sc.S.kind) all)
    in
    (if S.is_unknown final then List.filter (fun (e, _, _) -> e = "?") all
     else List.filter_map for_scope (S.scopes final))
    @ List.filter (fun (e, _, _) -> String.length e > 1 && e.[0] = 'c' && not (String.contains e '.')) all
  in
  let sites =
    List.map
      (fun rs ->
         { s_span = rs.rs_span; s_key = rs.rs_key; s_kind = rs.rs_kind; s_owner = rs.rs_owner;
           s_set = print_set ~owner:rs.rs_owner ~own_ty:rs.rs_ty rs.rs_set; s_ground = get ground rs.rs_set;
           s_reasons = reasons ~owner:rs.rs_owner ~own_ty:rs.rs_ty rs.rs_set })
      (List.sort (fun a b -> cmp_span a.rs_span b.rs_span) s.sites)
  in
  let type_at (sp : Ast.span) : string option =
    match Hashtbl.find_opt s.annot sp, Hashtbl.find_opt env.type_map sp with
    | Some t, Some ty ->
      let owner = match Hashtbl.find_opt s.binders sp with Some (_, o) -> o | None -> "" in
      let annotated, any = print_ty ~owner ty t in
      if any then Some annotated else None
    | _ -> None
  in
  let fn_types =
    List.filter_map
      (fun k ->
         match Hashtbl.find_opt s.fn_iface k with
         | Some (sc :: _) ->
           reset_tvar_display_names ();
           let symbolic, set = printer () in
           List.iter
             (fun v -> if S.is_empty (get local v) then Hashtbl.replace symbolic v ())
             (List.concat_map (inputs ~neg:true) sc.sc_params);
           let show (ty : ty option) (t : T.t) : string =
             match ty with Some ty -> T.pp ~set ty t | None -> "_"
           in
           let params = "(" ^ String.concat ", " (List.map2 show sc.sc_param_tys sc.sc_params) ^ ")" in
           let eff =
             String.concat ", "
               (List.filter (fun x -> x <> "") [ (if S.is_unknown sc.sc_own then "?" else S.to_string sc.sc_own); set sc.sc_val ])
           in
           let res =
             match sc.sc_result_ty with
             | Some ty ->
               let r, carries = T.pp_flag ~set ty sc.sc_result in
               if carries && String.length r > 0 && r.[0] <> '(' then "(" ^ r ^ ")" else r
             | None -> "_"
           in
           if Hashtbl.mem s.handler_keys k then None
           else if Hashtbl.mem s.let_keys k then
             (* A module-level value: its type is its initialiser's. *)
             Some ("let " ^ k, match sc.sc_result_ty with Some ty -> T.pp ~set ty sc.sc_result | None -> "_")
           else Some ("fn " ^ k, params ^ " -> " ^ res ^ if eff = "" then "" else " needs " ^ eff)
         | _ -> None)
      keys
  in
  (* For an editor: a set the pass does not track reads as any authority,
     which is what it is treated as, with a line saying so. *)
  let hover_type_at (sp : Ast.span) : string option =
    match Hashtbl.find_opt s.annot sp, Hashtbl.find_opt env.type_map sp with
    | Some t, Some ty ->
      let owner = match Hashtbl.find_opt s.binders sp with Some (_, o) -> o | None -> "" in
      saw_unknown := false;
      let annotated, any = print_ty ~unknown:"IO" ~owner ty t in
      if not any then None
      else if !saw_unknown then Some (annotated ^ "\n-- part of this is not tracked: it is treated as any authority")
      else Some annotated
    | _ -> None
  in
  let binders =
    List.sort
      (fun (a, _, _) (b, _, _) -> cmp_span a b)
      (Hashtbl.fold
         (fun sp (name, _) acc -> match type_at sp with Some t -> (sp, name, t) :: acc | None -> acc)
         s.binders [])
  in
  { sites; type_at; hover_type_at; binders; fn_types;
    unknown_causes = List.sort compare (Hashtbl.fold (fun k n acc -> (k, n) :: acc) st.unknown_causes []);
    unknown_at = List.rev st.unknown_at }

(* ── `march --dump-captures` ────────────────────────────────────────────── *)

let render ~(file : string) (r : result) : string =
  let b = Buffer.create 1024 in
  let mine (sp : Ast.span) = sp.Ast.file = file in
  let pos (sp : Ast.span) = Printf.sprintf "%d:%d" sp.Ast.start_line sp.Ast.start_col in
  let sites = List.filter (fun x -> mine x.s_span) r.sites in
  List.iter
    (fun x ->
       let what =
         match x.s_kind with
         | Lambda -> "lambda"
         | Local_fn n -> Printf.sprintf "local fn `%s`" n
         | Named_value n -> Printf.sprintf "`%s` as a value" n
       in
       let where = if x.s_owner = "" then "at module level" else Printf.sprintf "in `%s`" x.s_owner in
       Buffer.add_string b
         (Printf.sprintf "%-7s%s %s  %s\n" (pos x.s_span) what where
            (if x.s_set = "" then "captures nothing" else "needs " ^ x.s_set));
       List.iter
         (fun (elem, why, sp) ->
            Buffer.add_string b
              (Printf.sprintf "         %s  %s%s\n" elem why
                 (if sp.Ast.file = file then Printf.sprintf " (%s)" (pos sp) else "")))
         x.s_reasons)
    sites;
  List.iter
    (fun (sp, name, t) ->
       if mine sp then Buffer.add_string b (Printf.sprintf "%-7slet %s : %s\n" (pos sp) name t))
    r.binders;
  List.iter (fun (k, t) -> Buffer.add_string b (Printf.sprintf "%s : %s\n" k t)) r.fn_types;
  List.iter
    (fun (cause, sp) ->
       if mine sp then Buffer.add_string b (Printf.sprintf "%-7snot tracked: %s\n" (pos sp) cause))
    (List.sort_uniq compare r.unknown_at);
  let unknown = List.length (List.filter (fun x -> x.s_set = "?") sites) in
  Buffer.add_string b
    (Printf.sprintf "%d function value%s, %d not tracked\n" (List.length sites)
       (if List.length sites = 1 then "" else "s") unknown);
  Buffer.contents b
