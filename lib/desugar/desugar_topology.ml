(** The generated [main] of a topology app (distributed-deploys plan, build
    step 3: sections 4.1 and II.3; D9, D15-D18, D20, D23, D24, D34).

    When the compiler is given [--topology <digest.json>] and the entry module
    has no [main], [main] is generated: it starts the ClusterNode from the
    environment, runs each pool's hook (under [Topology.hook]'s watchdog) with
    one [cap_narrow] per [Cap(P)] parameter the hook declares plus the node
    handle, then hands [Topology.place] one entry per served role, installs
    [Topology.drain_on_signal] and ends in [Topology.supervise_offers], which
    keeps [main] alive.  Under [forge run] the one generated [main] runs every
    pool (D9); a process of a shared build runs the pools [MARCH_POOLS] names
    ([Topology.runs_pool]), and [--topology-pools] restricts which pools a
    build contains at all (an isolated pool's own build).

    {1 Shape}

    - A role bound to a function ([body = "M.f"]) becomes
      [Topology.offer_role(name, place, capacity, fn cap -> <P>_Run.offer_<R>(io,
      node, cap, fn (s, caps..., st) -> M.f(env, s, caps..., st)))]: the body's
      type is the role's granted body type with the pool's [Env] in front (4.1,
      D34). The capacity is an argument so that a topology re-read on SIGHUP
      can change it without a rebuild (build step 8).
    - A role bound to an actor ([actor = "M.A"], D23) becomes
      [Topology.offer_actor_role(name, place, capacity, fn () -> spawn(A, env),
      fn (a, cap) -> <P>_Run.offer_hosted_<R>(io, node, cap, a, start, deliver,
      cancel))],
      one actor per offer, whose three callbacks forward to the actor's
      [Start(sid, s, caps...)], [Deliver(sid, s, from, msg, ep)] and
      [Cancel(sid, s, role, cause, ep)] handlers -- the same messages a
      hand-written hosted offer's actor takes (test/two_node/cluster_ap_hosted),
      from which it drives the generated [Parked_<Role>] API.
    - [spawn] takes only a bare actor name and a message constructor resolves
      in its actor's module, so the spawn and the three sends are small helper
      functions INJECTED INTO THE ACTOR'S OWN MODULE
      ([topology_spawn_<A>], [topology_start_<A>], ...), and [main] calls them.
      The generated code takes every user function as a callee written in
      [main], never as a forward reference from a nested module: an
      interpreted nested module that calls a parent function declared later
      dies with "stub called before initialisation".

    Nothing here parses: [lib/desugar] does not link the parser.  The pass
    emits March SOURCE ([main_source], [helper_sources]) and the driver
    (bin/main.ml) parses and desugars it, as it does the capability-dispatch
    wrappers ([Io_ops_gen]).  So the generated code is checked like any
    other: the grant walk, linearity and the endpoint types all apply to it.

    {1 Checks}

    [check] reports what the AST can decide, each naming the topology entry:
    a body's arity and first parameter against the hook's return type, a
    bound actor's [init] parameter and its three handlers, a hook's signature
    (its [Cap] parameters within the pool's written [caps], the handle last),
    a role's grant within its pool's written [caps], and, when asked, an
    [IO.Foreign] role in a pool that is not isolated.  What needs types beyond
    the annotations (a hook's or body's REACH, the derived pool caps) is the
    driver's, after typechecking (bin/topology_gen.ml: [derive], [reach_errors]). *)

open March_ast.Ast

(* ── The digest, as the compiler sees it ───────────────────────────────── *)

type placement = Everywhere | On of string | Count of int | Count_on of string * int

type role = {
  r_name     : string;          (** "Checkout.Ledger" *)
  r_protocol : string;
  r_role     : string;
  r_body     : string option;   (** qualified from the file's top module *)
  r_actor    : string option;
  r_capacity : int option;
  r_place    : placement;
}

type pool = {
  p_name    : string;
  p_start   : string option;
  p_serves  : string list;
  p_caps    : string list option;  (** written: an upper limit; None: derived (D22) *)
  p_isolate : bool;
}

type t = { roles : role list; pools : pool list; soft_ms : int; hard_ms : int }

let default_capacity = 64
let default_soft_ms = 30000
let default_hard_ms = 120000

(* ── Facts read off the AST ────────────────────────────────────────────── *)

type fn_info = {
  fi_params : (string * ty option) list;
  fi_ret    : ty option;
  fi_path   : string list;   (** enclosing module path, entry name first *)
}

type actor_info = {
  ai_init     : (string * ty option) list;
  ai_handlers : (string * int) list;   (** message name, arity *)
  ai_path     : string list;
}

type proto_info = {
  pi_path   : string list;               (** module path of the file module declaring it *)
  pi_roles  : string list;
  pi_grants : (string * string list) list;  (** role -> `role R needs` paths *)
}

type facts = {
  entry  : string;
  fns    : (string, fn_info) Hashtbl.t;     (** by qualified name *)
  actors : (string, actor_info) Hashtbl.t;
  protos : (string, proto_info) Hashtbl.t;  (** by protocol name *)
  types  : (string, unit) Hashtbl.t;        (** qualified type names *)
}

let qualify path name = String.concat "." (path @ [ name ])

let params_of (clause : fn_clause) =
  List.map (function
      | FPNamed p | FPDefault (p, _) -> (p.param_name.txt, p.param_ty)
      | FPPat _ -> ("_", None))
    clause.fc_params

let rec proto_roles_of acc (steps : protocol_step list) =
  List.fold_left (fun acc st ->
      match st with
      | ProtoMsg (a, b, _, _) -> b.txt :: a.txt :: acc
      | ProtoLoop (ss, _) -> proto_roles_of acc ss
      | ProtoChoice (r, brs) ->
        List.fold_left (fun acc (_, ss) -> proto_roles_of acc ss) (r.txt :: acc) brs
      | ProtoCrashOr (s, ss, _) -> proto_roles_of (proto_roles_of acc [ s ]) ss
      | ProtoMayCrash _ | ProtoStop _ | ProtoRoleNeeds _ -> acc)
    acc steps

(* IO paths only, as [Desugar_endpoints.grants_of]: a non-IO path is refused
   by the typechecker at the grant line, and dropping it here keeps that the
   only diagnostic in a topology app too. *)
let grants_of (steps : protocol_step list) =
  List.filter_map (function
      | ProtoRoleNeeds (r, caps, _) ->
        Some (r.txt,
              List.filter_map
                (fun (c : name) -> if March_caps.Cap_lattice.cap_subsumes "IO" c.txt then Some c.txt else None)
                caps)
      | _ -> None)
    steps

(** [collect ~entry ~entry_decls ~imports]: the entry module's declarations
    (flat, under [entry]) and each imported file module ([DMod]s). *)
let collect ~entry ~(entry_decls : decl list) ~(imports : decl list) : facts =
  let f = { entry; fns = Hashtbl.create 64; actors = Hashtbl.create 16;
            protos = Hashtbl.create 8; types = Hashtbl.create 64 } in
  let rec walk ~file_path path (decls : decl list) =
    List.iter (function
        | DFn (def, _) ->
          (match def.fn_clauses with
           | c :: _ ->
             Hashtbl.replace f.fns (qualify path def.fn_name.txt)
               { fi_params = params_of c; fi_ret = def.fn_ret_ty; fi_path = path }
           | [] -> ())
        | DActor (_, nm, a, _) ->
          Hashtbl.replace f.actors (qualify path nm.txt)
            { ai_init = List.map (fun p -> (p.param_name.txt, p.param_ty)) a.actor_init_params;
              ai_handlers = List.map (fun h -> (h.ah_msg.txt, List.length h.ah_params)) a.actor_handlers;
              ai_path = path }
        | DType (_, nm, _, _, _) -> Hashtbl.replace f.types (qualify path nm.txt) ()
        | DProtocol (nm, pdef, _) ->
          Hashtbl.replace f.protos nm.txt
            { pi_path = file_path;
              pi_roles = List.sort_uniq String.compare (proto_roles_of [] pdef.proto_steps);
              pi_grants = grants_of pdef.proto_steps }
        | DMod (nm, _, ds, _) -> walk ~file_path (path @ [ nm.txt ]) ds
        | _ -> ())
      decls
  in
  walk ~file_path:[] [ entry ] entry_decls;
  List.iter (function
      | DMod (nm, _, ds, _) -> walk ~file_path:[ nm.txt ] [ nm.txt ] ds
      | _ -> ())
    imports;
  f

let has_main (decls : decl list) =
  List.exists (function DFn (d, _) -> d.fn_name.txt = "main" | _ -> false) decls

(* ── Types as text ─────────────────────────────────────────────────────── *)

(** A type name resolved the way the declaring module would: a bare name
    declared in the module [path] or an enclosing one is qualified with that
    module, so [Env] inside [mod Edge] and [Edge.Env] outside compare equal. *)
let resolve_type f path (n : string) =
  let rec up p =
    if Hashtbl.mem f.types (qualify p n) then Some (qualify p n)
    else match List.rev p with [] -> None | _ :: rest -> up (List.rev rest)
  in
  match up path with
  | Some q -> q
  | None ->
    (* A qualified name from the entry's point of view. *)
    if Hashtbl.mem f.types (qualify [ f.entry ] n) then qualify [ f.entry ] n else n

let rec show_ty ?(f : facts option) ?(path = []) (t : ty) : string =
  let go = show_ty ?f ~path in
  match t with
  | TyCon (n, []) -> (match f with Some f -> resolve_type f path n.txt | None -> n.txt)
  | TyCon (n, args) ->
    let head = match f with Some f -> resolve_type f path n.txt | None -> n.txt in
    head ^ "(" ^ String.concat ", " (List.map go args) ^ ")"
  | TyVar n -> n.txt
  | TyArrow (a, b) -> "(" ^ go a ^ " -> " ^ go b ^ ")"
  | TyTuple [] -> "()"
  | TyTuple ts -> "(" ^ String.concat ", " (List.map go ts) ^ ")"
  | TyRecord fs -> "{ " ^ String.concat ", " (List.map (fun ((n : name), t) -> n.txt ^ " : " ^ go t) fs) ^ " }"
  | TyLinear (_, t) -> go t
  | TyNat n -> string_of_int n
  | TyNatOp (_, a, b) -> go a ^ " op " ^ go b
  | TyChan (a, b) -> "Chan(" ^ a.txt ^ ", " ^ b.txt ^ ")"
  | TyRefine (t, _, _) -> go t

(** The capability a [Cap(P)] type names, if it is one. *)
let cap_of_ty (t : ty) : string option =
  match t with
  | TyCon ({ txt = "Cap"; _ }, [ TyCon (p, []) ]) -> Some p.txt
  | _ -> None

let is_handle_ty (t : ty) =
  match t with
  | TyCon ({ txt = "Cap"; _ }, [ TyCon ({ txt = ("ClusterNode.Live" | "Live"); _ }, []) ]) -> true
  | _ -> false

let is_unit_ty (t : ty) =
  match t with
  | TyTuple [] | TyCon ({ txt = ("Unit" | "()"); _ }, []) -> true
  | _ -> false

(* ── Names ─────────────────────────────────────────────────────────────── *)

(** How [main], at the entry's top level, spells a qualified name. *)
let ref_of f (qname : string) =
  let pre = f.entry ^ "." in
  let n = String.length pre in
  if String.length qname > n && String.sub qname 0 n = pre then String.sub qname n (String.length qname - n)
  else qname

let path_ref f (path : string list) (leaf : string) =
  match path with
  | e :: rest when e = f.entry -> String.concat "." (rest @ [ leaf ])
  | _ -> String.concat "." (path @ [ leaf ])

let run_module f (proto : string) =
  match Hashtbl.find_opt f.protos proto with
  | Some pi -> String.concat "." (pi.pi_path @ [ proto ^ "_Run" ])
  | None -> proto ^ "_Run"

let grants_for f (r : role) =
  match Hashtbl.find_opt f.protos r.r_protocol with
  | Some pi -> Option.value ~default:[] (List.assoc_opt r.r_role pi.pi_grants)
  | None -> []

let hook_info f (p : pool) = match p.p_start with Some s -> Hashtbl.find_opt f.fns s | None -> None

(** The hook's leading [Cap(P)] parameters, in order. *)
let hook_caps (hi : fn_info) =
  List.filter_map (fun (_, t) ->
      match t with
      | Some t when is_handle_ty t -> None
      | _ -> Option.bind t cap_of_ty)
    hi.fi_params

(** The pool's environment type, as text: the hook's declared return type,
    or [()] for a pool with no hook. *)
let env_ty f (p : pool) : string option =
  match p.p_start with
  | None -> Some "()"
  | Some _ ->
    (match hook_info f p with
     | Some hi -> Option.map (show_ty ~f ~path:hi.fi_path) hi.fi_ret
     | None -> None)

let selected_pools ?pools (t : t) =
  match pools with
  | None -> t.pools
  | Some names -> List.filter (fun p -> List.mem p.p_name names) t.pools

let role_by_name (t : t) n = List.find_opt (fun r -> r.r_name = n) t.roles

(* ── Checks the annotations can decide ─────────────────────────────────── *)

let subsumes (granted : string list) (cap : string) =
  List.exists (fun g -> March_caps.Cap_lattice.cap_subsumes g cap) granted

(** Errors, each naming the topology entry it is about. [foreign_isolated]:
    also reject an [IO.Foreign] role (or hook) in a pool that is not
    isolated (section 4, "when opted in"). *)
let check ?(foreign_isolated = false) ?pools (f : facts) (t : t) : string list =
  let errs = ref [] in
  let err fmt = Printf.ksprintf (fun s -> errs := s :: !errs) fmt in
  let pools = selected_pools ?pools t in
  List.iter (fun (p : pool) ->
      (* The hook: [Cap(P)]... then the handle; annotated return type. *)
      (match p.p_start, hook_info f p with
       | Some s, Some hi ->
         let ps = hi.fi_params in
         let n = List.length ps in
         List.iteri (fun i (pn, ty) ->
             let last = i = n - 1 in
             match ty with
             | None -> err "pool \"%s\": hook '%s': parameter `%s` needs a type annotation (a hook takes `Cap(P)` parameters and then the node, `Cap(ClusterNode.Live)`)" p.p_name s pn
             | Some ty when last ->
               if not (is_handle_ty ty) then
                 err "pool \"%s\": hook '%s': its last parameter must be the node, `Cap(ClusterNode.Live)`, not `%s`" p.p_name s (show_ty ty)
             | Some ty ->
               (match cap_of_ty ty with
                | None -> err "pool \"%s\": hook '%s': parameter `%s : %s` is not a capability; a hook takes `Cap(P)` parameters and then the handle" p.p_name s pn (show_ty ty)
                | Some c ->
                  (match p.p_caps with
                   | Some written when not (subsumes written c) ->
                     err "pool \"%s\": hook '%s' takes `Cap(%s)`, beyond the pool's written caps [%s]" p.p_name s c (String.concat ", " written)
                   | _ -> ())))
           ps;
         if n = 0 then err "pool \"%s\": hook '%s' takes no parameters; it takes `Cap(P)` parameters and then the node, `Cap(ClusterNode.Live)`" p.p_name s;
         if hi.fi_ret = None then
           err "pool \"%s\": hook '%s' needs a declared return type: it is the environment its roles' bodies receive" p.p_name s;
         if foreign_isolated && not p.p_isolate && List.mem "IO.Foreign" (hook_caps hi) then
           err "pool \"%s\": hook '%s' takes `Cap(IO.Foreign)`, but the pool is not isolated (`isolate = true`)" p.p_name s
       | _ -> ());
      List.iter (fun rn ->
          match role_by_name t rn with
          | None -> ()
          | Some r ->
            let grants = grants_for f r in
            (* Role grant within the pool's written caps. *)
            (match p.p_caps with
             | Some written ->
               List.iter (fun g ->
                   if not (subsumes written g) then
                     err "role \"%s\" is granted `%s` (`role %s needs ...` in protocol %s), beyond pool \"%s\"'s written caps [%s]"
                       r.r_name g r.r_role r.r_protocol p.p_name (String.concat ", " written))
                 grants
             | None -> ());
            if foreign_isolated && not p.p_isolate && List.mem "IO.Foreign" grants then
              err "role \"%s\" is granted `IO.Foreign`, but pool \"%s\" is not isolated (`isolate = true`)" r.r_name p.p_name;
            let env = env_ty f p in
            let k = List.length grants in
            (match r.r_body, r.r_actor with
             | Some b, _ ->
               (match Hashtbl.find_opt f.fns b with
                | None -> ()
                | Some bi ->
                  let n = List.length bi.fi_params in
                  if n <> 3 + k then
                    err "role \"%s\": body '%s' takes %d parameter(s); a body of this role takes %d: the pool's environment, the session, %sand the entry state"
                      r.r_name b n (3 + k) (if k = 0 then "" else Printf.sprintf "%d granted cap(s), " k)
                  else begin
                    match bi.fi_params, env with
                    | (_, Some t1) :: _, Some e ->
                      let got = show_ty ~f ~path:bi.fi_path t1 in
                      if got <> e && not (is_unit_ty t1 && e = "()") then
                        err "role \"%s\": body '%s' takes its environment as `%s`, but pool \"%s\"'s hook returns `%s`"
                          r.r_name b got p.p_name e
                    | _ -> ()
                  end)
             | None, Some a ->
               (match Hashtbl.find_opt f.actors a with
                | None -> ()
                | Some ai ->
                  (match ai.ai_init, env with
                   | [], Some "()" -> ()
                   | [], Some e ->
                     err "role \"%s\": actor '%s' has no `init` parameter; it receives pool \"%s\"'s environment, `%s`: write `init(env : %s) { ... }`"
                       r.r_name a p.p_name e e
                   | [ (_, Some t1) ], Some e ->
                     let got = show_ty ~f ~path:ai.ai_path t1 in
                     if got <> e then
                       err "role \"%s\": actor '%s''s `init` takes `%s`, but pool \"%s\"'s hook returns `%s`" r.r_name a got p.p_name e
                   | [ _ ], _ -> ()
                   | _ :: _ :: _, _ ->
                     err "role \"%s\": actor '%s''s `init` takes %d parameters; a role-bound actor's `init` takes one, the pool's environment"
                       r.r_name a (List.length ai.ai_init)
                   | [], None -> ());
                  List.iter (fun (msg, want) ->
                      match List.assoc_opt msg ai.ai_handlers with
                      | Some got when got = want -> ()
                      | Some got ->
                        err "role \"%s\": actor '%s''s `on %s` takes %d parameter(s), %d expected (%s)" r.r_name a msg got want
                          (match msg with
                           | "Start" -> "sid, s" ^ (if k = 0 then "" else ", the granted caps")
                           | "Deliver" -> "sid, s, from, msg, ep"
                           | _ -> "sid, s, role, cause, ep")
                      | None ->
                        err "role \"%s\": actor '%s' has no `on %s` handler; a role-bound actor takes Start(sid, s%s), Deliver(sid, s, from, msg, ep) and Cancel(sid, s, role, cause, ep)"
                          r.r_name a msg (if k = 0 then "" else ", caps...")
                    )
                    [ ("Start", 2 + k); ("Deliver", 5); ("Cancel", 5) ])
             | None, None -> ()))
        p.p_serves)
    pools;
  List.rev !errs

(* ── Generation ────────────────────────────────────────────────────────── *)

let place_src = function
  | Everywhere -> "Topology.everywhere()"
  | On l -> Printf.sprintf "Topology.on_label(%S)" l
  | Count n -> Printf.sprintf "Topology.count(%d)" n
  | Count_on (l, n) -> Printf.sprintf "Topology.count_on(%S, %d)" l n

let xs k = List.init k (fun i -> Printf.sprintf "topology_x%d" (i + 1))

(** The helpers injected into each bound actor's module: [(module path,
    source of the helper functions)], one entry per actor. *)
let helper_sources ?pools (f : facts) (t : t) : (string list * string) list =
  let pools = selected_pools ?pools t in
  let served = List.sort_uniq String.compare (List.concat_map (fun p -> p.p_serves) pools) in
  let actors =
    List.filter_map (fun rn ->
        match role_by_name t rn with
        | Some ({ r_actor = Some a; _ } as r) -> Some (a, r)
        | _ -> None)
      served
    |> List.sort_uniq (fun (a, _) (b, _) -> String.compare a b)
  in
  List.filter_map (fun (a, r) ->
      match Hashtbl.find_opt f.actors a with
      | None -> None
      | Some ai ->
        let leaf = match List.rev (String.split_on_char '.' a) with l :: _ -> l | [] -> a in
        let caps = xs (List.length (grants_for f r)) in
        let spawn = if ai.ai_init = [] then Printf.sprintf "spawn(%s)" leaf else Printf.sprintf "spawn(%s, topology_env)" leaf in
        let fwd name msg args =
          Printf.sprintf
            "  fn topology_%s_%s(topology_a, %s) do\n    let _ = send(topology_a, %s(%s))\n    ()\n  end\n"
            name leaf (String.concat ", " args) msg (String.concat ", " args)
        in
        let src =
          Printf.sprintf "  fn topology_spawn_%s(topology_env) do %s end\n" leaf spawn
          ^ fwd "start" "Start" ([ "topology_sid"; "topology_s" ] @ caps)
          ^ fwd "deliver" "Deliver" [ "topology_sid"; "topology_s"; "topology_from"; "topology_m"; "topology_ep" ]
          ^ fwd "cancel" "Cancel" [ "topology_sid"; "topology_s"; "topology_role"; "topology_cause"; "topology_ep" ]
        in
        Some (ai.ai_path, src))
    actors

(** The generated [main], as March source (one [fn] declaration). *)
let main_source ?pools (f : facts) (t : t) : string =
  let b = Buffer.create 2048 in
  let add fmt = Printf.bprintf b fmt in
  let pools = selected_pools ?pools t in
  add "fn main(topology_io : Cap(IO)) do\n";
  (* Only ClusterNode may hand out a Cap(ClusterNode.Live) (D35), so the
     node is started here, not by a Topology helper. *)
  add "  let topology_node = match ClusterNode.start(topology_io, Topology.config_from_env()) do\n";
  add "    Ok(topology_n) -> topology_n\n";
  add "    Err(topology_e) -> Topology.start_failed(topology_e)\n";
  add "  end\n";
  List.iteri (fun i (p : pool) ->
      let env = Printf.sprintf "topology_env_%d" i in
      add "  let topology_roles_%d = if Topology.runs_pool(%S) do\n" i p.p_name;
      (match p.p_start, hook_info f p with
       | Some s, Some hi ->
         let args =
           List.map (fun (_, ty) ->
               match ty with
               | Some t when is_handle_ty t -> "topology_node"
               | _ ->
               match Option.bind ty cap_of_ty with
               | Some "IO" -> "topology_io"
               | Some _ -> "cap_narrow(topology_io)"
               | None -> "topology_node")
             hi.fi_params
         in
         add "    let %s = Topology.hook(%S, fn () -> %s(%s))\n" env s (ref_of f s) (String.concat ", " args)
       | _ -> add "    let %s = ()\n" env);
      let entries =
        List.filter_map (fun rn ->
            match role_by_name t rn with
            | None -> None
            | Some r ->
              let cap = Option.value ~default:default_capacity r.r_capacity in
              let run = run_module f r.r_protocol in
              let caps = xs (List.length (grants_for f r)) in
              (match r.r_body, r.r_actor with
               | Some body, _ ->
                 let ps = [ "topology_s" ] @ caps @ [ "topology_st" ] in
                 Some (Printf.sprintf
                         "      Topology.offer_role(%S, %s, %d, fn topology_cap -> %s.offer_%s(topology_io, topology_node, topology_cap,\n        fn (%s) -> %s(%s)))"
                         r.r_name (place_src r.r_place) cap run r.r_role
                         (String.concat ", " ps) (ref_of f body) (String.concat ", " (env :: ps)))
               | None, Some a ->
                 (match Hashtbl.find_opt f.actors a with
                  | None -> None
                  | Some ai ->
                    let leaf = match List.rev (String.split_on_char '.' a) with l :: _ -> l | [] -> a in
                    let h name = path_ref f ai.ai_path (Printf.sprintf "topology_%s_%s" name leaf) in
                    let start_ps = [ "topology_sid"; "topology_s" ] @ caps in
                    let dl = [ "topology_sid"; "topology_s"; "topology_from"; "topology_m"; "topology_ep" ] in
                    let cl = [ "topology_sid"; "topology_s"; "topology_role"; "topology_cause"; "topology_ep" ] in
                    let call name ps = Printf.sprintf "fn (%s) -> %s(%s)" (String.concat ", " ps) (h name)
                        (String.concat ", " ("topology_a" :: ps)) in
                    Some (Printf.sprintf
                            "      Topology.offer_actor_role(%S, %s, %d, fn () -> %s(%s),\n        fn (topology_a, topology_cap) -> %s.offer_hosted_%s(topology_io, topology_node, topology_cap, topology_a,\n          %s,\n          %s,\n          %s))"
                            r.r_name (place_src r.r_place) cap (h "spawn") env run r.r_role
                            (call "start" start_ps) (call "deliver" dl) (call "cancel" cl)))
               | None, None -> None))
          p.p_serves
      in
      if entries = [] then add "    let _ = %s\n    Nil\n" env
      else add "    [\n%s\n    ]\n" (String.concat ",\n" entries);
      add "  else Nil end\n")
    pools;
  add "  Topology.place(topology_node, List.concat([%s]))\n"
    (String.concat ", " (List.mapi (fun i _ -> Printf.sprintf "topology_roles_%d" i) pools));
  add "  Topology.drain_on_signal(topology_node, %d, %d)\n" t.soft_ms t.hard_ms;
  add "  Topology.supervise_offers(topology_node)\n";
  add "end\n";
  Buffer.contents b

(** Insert [extra] at the end of the module at [path] ([path] starts with
    the module the declarations are rooted at: the entry's name for
    [entry_decls], an imported module's name for its [DMod]). *)
let rec insert_at (path : string list) (extra : decl list) (decls : decl list) : decl list =
  match path with
  | [] -> decls @ extra
  | m :: rest ->
    List.map (function
        | DMod (nm, vis, ds, sp) when nm.txt = m -> DMod (nm, vis, insert_at rest extra ds, sp)
        | d -> d)
      decls

(* ── After typechecking: reach and derived caps ────────────────────────── *)

(** The row keys a pool's user code starts from: its hook, and each served
    role's body, or its actor's handlers and init. [key] maps a qualified
    name to how the capability rows name it. *)
let pool_roots ?pools:_ (f : facts) (t : t) (p : pool) : (string * string) list =
  let hook = match p.p_start with Some s -> [ ("hook " ^ s, s) ] | None -> [] in
  hook
  @ List.concat_map (fun rn ->
      match role_by_name t rn with
      | Some { r_body = Some b; _ } -> [ ("body " ^ b, b) ]
      | Some { r_actor = Some a; _ } ->
        (match Hashtbl.find_opt f.actors a with
         | Some _ -> [ ("actor " ^ a, a) ]
         | None -> [])
      | _ -> [])
    p.p_serves
