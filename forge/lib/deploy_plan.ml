(** [forge deploy --plan]: what a deploy will do, per pool and build
    (distributed-deploys plan 6.8, II.8, D21, D26; build step 10b).

    [classify] is a pure function from the old and new versions of every
    input to a [plan]; [render] prints its six blocks (6.8): what changed,
    the mechanism and why, order and splits, drains, what may be lost,
    authority and derived values. [Cmd_deploy] gathers the inputs (it
    builds, reads what forge last deployed from [.forge/deploy/<env>/], asks
    the backend for live sessions) and executes the plan.

    {1 Inputs}

    - Per build (the shared one and each isolated pool's): the manifest
      last deployed and the new one (function set-diff, signature changes,
      hooks' impl hashes, protocol fingerprint functions, role closures,
      [<actor>_migrate_state] presence), the actor schemas (state and
      message types, [migrate_msg]), and the identity of the base image
      (runtime ABI, target, C-runtime digest).
    - Per protocol: its structure as the parse declares it, now and as of
      the last deploy ([.forge/deploy/<env>/protocols/<P>.json]), and whether its wire
      fingerprint changed: the generated [<P>_Msg.fingerprint] function's
      impl hash, whose body is the fingerprint literal, so it changes
      exactly when the fingerprint does. forge's structure is not the wire
      fingerprint: it tells what KIND of change it is.
    - The topology deployed and the new one ([Reconcile.diff_topologies]).
    - Each pool's derived caps and initiated roles (the compiler's,
      [--emit-core-ast]'s [topology] object), then and now.
    - Live sessions per node, from the backend's [status].

    {1 Mechanisms (6.8)}

    Per pool, the strongest that applies: [Blocked] (a refusal the deploy
    would hit: a state change with no [migrate_state] under [@compat],
    a [migrate_msg] for the wrong old type, an ungranted widening);
    [Restart] (a hook changed: hooks run once, at start; the C runtime,
    HCR ABI or target changed; a pool is new or its process layout
    changed; nothing is deployed yet); [Hot_drain] (a protocol's
    fingerprint changed: its offers close and drain); [Hot_migrate]
    (actor state changed, [migrate_state] found); [Hot]; [Placement]
    (the topology alone changed: a push, D16); [Nothing].

    {1 Order and the D21 split}

    A choice that gained a branch is compatible when every receiver of the
    choice runs the new version before its chooser does (6.4). Pools that
    receive it go first. When one build both chooses and receives the
    changed choice (a replicated monolith), no order exists within one
    deploy, so it becomes two (D21): deploy one activates everything except
    the chooser role's functions; deploy two, run after every host has
    deploy one, activates them. The finer rule (which (role, version)
    combinations may form a session, over wire tags) is the compatibility
    table of build step 9; until then forge splits on "the same build both
    chooses and receives the changed choice", from the declarations, and
    names the unlabelled messages a branch would renumber. *)

(* ── Protocol structure ───────────────────────────────────────────────── *)

type step =
  | Msg of { src : string; dst : string; ty : string; label : string option }
  | Loop of step list
  | Choice of { by : string; branches : (string * step list) list }
  | Stop
  | Crash_or of step * step list

type proto = { p_name : string; p_steps : step list }

module Ast = March_ast.Ast

let rec ty_text (t : Ast.ty) : string =
  match t with
  | Ast.TyCon (n, []) -> n.Ast.txt
  | Ast.TyCon (n, args) -> n.Ast.txt ^ "(" ^ String.concat ", " (List.map ty_text args) ^ ")"
  | Ast.TyVar n -> "'" ^ n.Ast.txt
  | Ast.TyArrow (a, b) -> "(" ^ ty_text a ^ " -> " ^ ty_text b ^ ")"
  | Ast.TyTuple ts -> "(" ^ String.concat ", " (List.map ty_text ts) ^ ")"
  | Ast.TyRecord fs -> "{" ^ String.concat ", " (List.map (fun (n, t) -> n.Ast.txt ^ " : " ^ ty_text t) fs) ^ "}"
  | Ast.TyLinear (_, t) -> "linear " ^ ty_text t
  | Ast.TyNat n -> string_of_int n
  | Ast.TyNatOp (_, a, b) -> "(" ^ ty_text a ^ " op " ^ ty_text b ^ ")"
  | Ast.TyChan (a, b) -> "Chan(" ^ a.Ast.txt ^ ", " ^ b.Ast.txt ^ ")"
  | Ast.TyRefine (t, _, _) -> "{" ^ ty_text t ^ " | ...}"

let rec steps_of_ast (steps : Ast.protocol_step list) : step list =
  List.concat_map (function
      | Ast.ProtoMsg (s, r, t, l) ->
        [ Msg { src = s.Ast.txt; dst = r.Ast.txt; ty = ty_text t; label = Option.map (fun (n : Ast.name) -> n.txt) l } ]
      | Ast.ProtoLoop (inner, _atomic) -> [ Loop (steps_of_ast inner) ]
      | Ast.ProtoChoice (by, bs) ->
        [ Choice { by = by.Ast.txt; branches = List.map (fun ((l : Ast.name), ss) -> (l.txt, steps_of_ast ss)) bs } ]
      | Ast.ProtoStop _ -> [ Stop ]
      | Ast.ProtoCrashOr (m, crash, _) ->
        (match steps_of_ast [ m ] with
         | [ m ] -> [ Crash_or (m, steps_of_ast crash) ]
         | ms -> ms @ steps_of_ast crash)
      | Ast.ProtoMayCrash _ | Ast.ProtoRoleNeeds _ -> [])
    steps

(** Every protocol the project declares, by the short name the topology
    uses. *)
let protos_of_index (idx : Topology.index) : proto list =
  List.map (fun (_q, short, (def : Ast.protocol_def)) -> { p_name = short; p_steps = steps_of_ast def.Ast.proto_steps })
    idx.Topology.protocols

let rec step_json (s : step) : Yojson.Safe.t =
  match s with
  | Msg { src; dst; ty; label } ->
    `Assoc [ ("msg", `List [ `String src; `String dst; `String ty ]);
             ("label", match label with Some l -> `String l | None -> `Null) ]
  | Loop ss -> `Assoc [ ("loop", `List (List.map step_json ss)) ]
  | Choice { by; branches } ->
    `Assoc [ ("choose", `String by);
             ("branches", `List (List.map (fun (l, ss) -> `List [ `String l; `List (List.map step_json ss) ]) branches)) ]
  | Stop -> `String "stop"
  | Crash_or (m, ss) -> `Assoc [ ("crash_or", `List [ step_json m; `List (List.map step_json ss) ]) ]

let proto_json (p : proto) : Yojson.Safe.t =
  `Assoc [ ("version", `Int 1); ("protocol", `String p.p_name); ("steps", `List (List.map step_json p.p_steps)) ]

let rec step_of_json (j : Yojson.Safe.t) : step =
  let module U = Yojson.Safe.Util in
  match j with
  | `String "stop" -> Stop
  | `Assoc kv when List.mem_assoc "msg" kv ->
    (match U.to_list (List.assoc "msg" kv) with
     | [ s; d; t ] ->
       Msg { src = U.to_string s; dst = U.to_string d; ty = U.to_string t;
             label = (match List.assoc_opt "label" kv with Some (`String l) -> Some l | _ -> None) }
     | _ -> failwith "msg")
  | `Assoc kv when List.mem_assoc "loop" kv -> Loop (List.map step_of_json (U.to_list (List.assoc "loop" kv)))
  | `Assoc kv when List.mem_assoc "choose" kv ->
    Choice { by = U.to_string (List.assoc "choose" kv);
             branches = List.map (fun b -> match U.to_list b with
                 | [ l; ss ] -> (U.to_string l, List.map step_of_json (U.to_list ss))
                 | _ -> failwith "branch") (U.to_list (List.assoc "branches" kv)) }
  | `Assoc kv when List.mem_assoc "crash_or" kv ->
    (match U.to_list (List.assoc "crash_or" kv) with
     | [ m; ss ] -> Crash_or (step_of_json m, List.map step_of_json (U.to_list ss))
     | _ -> failwith "crash_or")
  | _ -> failwith "step"

let proto_of_json (j : Yojson.Safe.t) : proto option =
  let module U = Yojson.Safe.Util in
  try Some { p_name = U.to_string (U.member "protocol" j); p_steps = List.map step_of_json (U.to_list (U.member "steps" j)) }
  with _ -> None

(** The message names (wire tags) in reading order, as [@[endpoints]]
    makes them (lib/desugar/desugar_endpoints.ml, [annotate]): a label,
    a branch label for a choice's head message sent by the chooser, else
    [Msg_<From>_<To>_<k>] counted per ordered pair. *)
let wire_names ?skip (steps : step list) : string list =
  (* [skip = (chooser, label)]: the names of that branch's messages are
     left out of the result, but its unlabelled messages still advance the
     counters, as they do in the generated code: what an added branch does
     to the names of the messages around it. *)
  let counts = Hashtbl.create 8 in
  let synth s r =
    let k = 1 + Option.value ~default:0 (Hashtbl.find_opt counts (s, r)) in
    Hashtbl.replace counts (s, r) k;
    Printf.sprintf "Msg_%s_%s_%d" s r k
  in
  let rec go steps =
    List.concat_map (function
        | Msg { label = Some l; _ } -> [ String.capitalize_ascii l ]
        | Msg { src; dst; label = None; _ } -> [ synth src dst ]
        | Loop ss -> go ss
        | Stop -> []
        | Crash_or (m, ss) -> go [ m ] @ go ss
        | Choice { by; branches } ->
          List.concat_map (fun (l, arm) ->
              let names =
                match arm with
                | Msg { src; _ } :: rest when src = by -> String.capitalize_ascii l :: go rest
                | arm -> go arm
              in
              if skip = Some (by, l) then [] else names)
            branches)
      steps
  in
  go steps

type choice_added = {
  ca_by : string;                 (** the chooser *)
  ca_receivers : string list;     (** who receives the choice *)
  ca_label : string;              (** the new branch *)
  ca_renumbered : (string * string) list;  (** unlabelled messages whose tag moves: old, new *)
}

type proto_change =
  | Same
  | Added
  | Removed
  | Choice_added of choice_added
  | Breaking of string

let receivers_of ~by (arm : step list) =
  match arm with
  | Msg { src; dst; _ } :: _ when src = by -> [ dst ]
  | arm ->
    let rec roles acc = function
      | [] -> acc
      | Msg { src; dst; _ } :: rest -> roles (List.filter (fun r -> r <> by) [ src; dst ] @ acc) rest
      | (Loop ss | Crash_or (_, ss)) :: rest -> roles (roles acc ss) rest
      | Choice { branches; _ } :: rest -> roles (List.fold_left (fun a (_, ss) -> roles a ss) acc branches) rest
      | Stop :: rest -> roles acc rest
    in
    List.sort_uniq String.compare (roles [] arm)

(** [old_steps] with exactly one more branch in one choice is [new_steps]:
    that branch, else None. *)
let rec one_branch_added (o : step list) (n : step list) : (string * string list * string * step list) option =
  (* the chooser, its receivers, the label, and new_steps without the branch *)
  match o, n with
  | [], [] -> None
  | x :: xs, y :: ys when x = y -> Option.map (fun (b, r, l, rest) -> (b, r, l, y :: rest)) (one_branch_added xs ys)
  | Choice { by = b1; branches = ob } :: xs, Choice { by = b2; branches = nb } :: ys
    when b1 = b2 && xs = ys && List.length nb = List.length ob + 1 ->
    let extra = List.filter (fun (l, _) -> not (List.mem_assoc l ob)) nb in
    (match extra with
     | [ (l, arm) ] when List.filter (fun (l', _) -> l' <> l) nb = ob ->
       Some (b1, receivers_of ~by:b1 arm, l, Choice { by = b1; branches = ob } :: ys)
     | _ ->
       (* a branch added deeper inside one of the branches *)
       None)
  | Loop a :: xs, Loop b :: ys when xs = ys ->
    Option.map (fun (by, r, l, inner) -> (by, r, l, Loop inner :: ys)) (one_branch_added a b)
  | Choice { by = b1; branches = ob } :: xs, Choice { by = b2; branches = nb } :: ys
    when b1 = b2 && xs = ys && List.map fst ob = List.map fst nb ->
    (* the same branches: the added choice branch is inside one of them *)
    let rec find acc = function
      | [] -> None
      | ((l, oa), (_, na)) :: rest when oa = na -> find ((l, na) :: acc) rest
      | ((l, oa), (_, na)) :: rest ->
        (match one_branch_added oa na with
         | Some (by, r, lb, inner) when List.for_all (fun ((_, a), (_, b)) -> a = b) rest ->
           Some (by, r, lb, Choice { by = b1; branches = List.rev acc @ [ (l, inner) ] @ List.map snd rest } :: ys)
         | _ -> None)
    in
    find [] (List.combine ob nb)
  | _ -> None

let classify_proto (o : proto option) (n : proto option) : proto_change =
  match o, n with
  | None, None -> Same
  | None, Some _ -> Added
  | Some _, None -> Removed
  | Some o, Some n ->
    if o.p_steps = n.p_steps then Same
    else
      match one_branch_added o.p_steps n.p_steps with
      | Some (by, receivers, label, without) when without = o.p_steps ->
        ignore without;
        let old_names = wire_names o.p_steps and kept = wire_names ~skip:(by, label) n.p_steps in
        let renumbered =
          List.filter_map (fun (a, b) -> if a <> b then Some (a, b) else None)
            (try List.combine old_names kept with Invalid_argument _ -> [])
        in
        Choice_added { ca_by = by; ca_receivers = receivers; ca_label = label; ca_renumbered = renumbered }
      | _ -> Breaking "its steps changed (not one added choice branch)"

(* ── Inputs ───────────────────────────────────────────────────────────── *)

type build_in = {
  b_name          : string;                     (** "shared" or an isolated pool *)
  b_pools         : string list;
  b_old           : Cmd_deploy_hot.manifest option;  (** None: nothing deployed yet *)
  b_new           : Cmd_deploy_hot.manifest;
  b_old_schemas   : (string * Schema_diff.actor_schema) list;
  b_new_schemas   : (string * Schema_diff.actor_schema) list;
  b_old_runtime   : string option;              (** C-runtime digest of the deployed base image *)
  b_new_runtime   : string option;              (** this toolchain's *)
  b_slots         : string list option;         (** the dispatch slots the running nodes report (VERSIONS_DETAIL);
                                                    None: no node answered *)
}

type live = {
  l_node     : string;
  l_pool     : string;
  l_up       : bool;
  l_running  : int;          (** sessions running on the node *)
  l_offers   : string list;
  l_stack    : int option;   (** persisted patch entries (COMPACT) *)
}

type derived = (string * (string list * string list)) list   (** pool -> (caps, initiates) *)

type input = {
  i_env          : string option;
  i_old_topology : Topology.t option;
  i_new_topology : Topology.t;
  i_builds       : build_in list;
  i_protocols    : (string * proto option * proto option) list;  (** name, deployed, now *)
  i_old_derived  : derived option;
  i_new_derived  : derived option;
  i_grant_caps   : string list;
  i_live         : live list;
  i_compact      : bool;          (** [--compact]: rebuild base images from the current version *)
  i_compact_after : int option;   (** forge.toml [hot-reload] compact_after *)
}

(* ── Output ───────────────────────────────────────────────────────────── *)

type mechanism =
  | Nothing
  | Placement
  | Hot
  | Hot_migrate of string list      (** actors migrated *)
  | Hot_drain of string list        (** protocols drained *)
  | Restart of string list          (** why *)
  | Blocked of string list          (** what would refuse it *)

type fn_diff = {
  changed : string list;
  added   : string list;
  removed : string list;
  sig_changed : string list;
}

type actor_change = {
  ac_actor        : string;
  ac_state        : Schema_diff.field_change list;
  ac_migrate      : bool;           (** migrate_state found *)
  ac_compat_error : string option;  (** the @compat violation, when no migrate_state *)
  ac_msgs         : bool;           (** message type changed *)
  ac_migrate_msg  : [ `None | `Matches | `Wrong_old_type ];
}

type proto_row = {
  pr_name   : string;
  pr_fp     : (string option * string option);   (** fingerprint function impl hash, deployed and new *)
  pr_change : proto_change;
  pr_pools  : string list;                      (** pools that serve or initiate one of its roles *)
}

type split = {
  sp_protocol : string;
  sp_build    : string;
  sp_choice   : choice_added;
  sp_held     : string list;        (** the chooser role's functions: held back to deploy two *)
}

type pool_plan = {
  pp_pool      : string;
  pp_build     : string;
  pp_hosts     : string list;
  pp_mechanism : mechanism;
  pp_why       : string list;
  pp_push      : bool;              (** the topology push reaches it *)
}

type widening = { w_pool : string; w_what : string; w_caps : string list; w_granted : bool }

type plan = {
  env        : string option;
  builds     : (build_in * fn_diff * actor_change list) list;
  protocols  : proto_row list;
  placement  : Reconcile.change list;
  hooks      : (string * string) list;             (** pool, hook: changed *)
  runtime    : (string * string) list;             (** build, what changed in its base image *)
  pools      : pool_plan list;                     (** in deploy order *)
  order_why  : string list;
  splits     : split list;
  widenings  : widening list;
  derived    : (string * (string list * string list) * (string list * string list) option) list;
  compact    : (string * string) list;             (** builds whose base image is rebuilt, and why *)
  live       : live list;
  topology   : Topology.t;
  first      : bool;                               (** nothing deployed yet *)
}

(* ── Helpers ──────────────────────────────────────────────────────────── *)

let contains s sub =
  let n = String.length s and k = String.length sub in
  let rec go i = i + k <= n && (String.sub s i k = sub || go (i + 1)) in
  k = 0 || go 0

let short name = match String.rindex_opt name '.' with Some i -> String.sub name (i + 1) (String.length name - i - 1) | None -> name

(** A qualified topology name ("App.Back.start") as the manifest names it:
    the module prefix stripped ("Back.start"), else as is. *)
let manifest_name (m : Cmd_deploy_hot.manifest) (q : string) =
  match m.module_prefix with
  | Some p when p <> "" && String.length q > String.length p + 1 && String.sub q 0 (String.length p + 1) = p ^ "." ->
    String.sub q (String.length p + 1) (String.length q - String.length p - 1)
  | _ -> q

let impl_of (m : Cmd_deploy_hot.manifest) name =
  List.find_map (fun (f : Cmd_deploy_hot.fn_manifest) -> if f.fn_name = name then Some f.fn_impl_hash else None) m.functions

let impl_of_q (m : Cmd_deploy_hot.manifest) q =
  match impl_of m q with Some h -> Some h | None -> impl_of m (manifest_name m q)

let list_some_fwd ?(max = 6) xs =
  let n = List.length xs in
  String.concat ", " (List.filteri (fun i _ -> i < max) xs)
  ^ (if n > max then Printf.sprintf ", ... (%d more)" (n - max) else "")

let fn_diff (o : Cmd_deploy_hot.manifest option) (n : Cmd_deploy_hot.manifest) : fn_diff =
  match o with
  | None -> { changed = []; added = List.map (fun (f : Cmd_deploy_hot.fn_manifest) -> f.fn_name) n.functions;
              removed = []; sig_changed = [] }
  | Some o ->
    let tbl = Hashtbl.create 1024 in
    List.iter (fun (f : Cmd_deploy_hot.fn_manifest) -> Hashtbl.replace tbl f.fn_name f) o.functions;
    let changed = ref [] and added = ref [] and sigs = ref [] in
    List.iter (fun (f : Cmd_deploy_hot.fn_manifest) ->
        match Hashtbl.find_opt tbl f.fn_name with
        | None -> added := f.fn_name :: !added
        | Some g ->
          if g.fn_impl_hash <> f.fn_impl_hash then changed := f.fn_name :: !changed;
          if g.fn_sig_hash <> "" && f.fn_sig_hash <> "" && g.fn_sig_hash <> f.fn_sig_hash then sigs := f.fn_name :: !sigs)
      n.functions;
    let now = Hashtbl.create 1024 in
    List.iter (fun (f : Cmd_deploy_hot.fn_manifest) -> Hashtbl.replace now f.fn_name ()) n.functions;
    let removed = List.filter_map (fun (f : Cmd_deploy_hot.fn_manifest) ->
        if Hashtbl.mem now f.fn_name then None else Some f.fn_name) o.functions in
    { changed = List.sort String.compare !changed; added = List.sort String.compare !added;
      removed = List.sort String.compare removed; sig_changed = List.sort String.compare !sigs }

(** Changed functions a hot patch cannot deliver: no dispatch slot in the
    running base ([slots]), and no chain of callers (the manifest's
    [callers:], transitively) up to a slotted function that changes too.
    Only a slot can be swapped; an unslotted function reaches the running
    program only through a new version of a slotted caller, which carries
    it inside the patch. A lifted closure is called through its closure
    value, not by name, so a change inside a lambda whose enclosing function
    did not change is not deliverable either. *)
let undeliverable ~(slots : string list) ~(changed : string list) (m : Cmd_deploy_hot.manifest) : string list =
  let slot = Hashtbl.create 64 and chg = Hashtbl.create 64 and callers = Hashtbl.create 4096 in
  List.iter (fun n -> Hashtbl.replace slot n ()) slots;
  List.iter (fun n -> Hashtbl.replace chg n ()) changed;
  List.iter (fun (f : Cmd_deploy_hot.fn_manifest) -> Hashtbl.replace callers f.fn_name f.fn_callers) m.functions;
  let deliverable f =
    let seen = Hashtbl.create 16 in
    let rec up = function
      | [] -> false
      | n :: rest when Hashtbl.mem seen n -> up rest
      | n :: rest ->
        Hashtbl.replace seen n ();
        if Hashtbl.mem slot n then Hashtbl.mem chg n || up rest
        else up (Option.value ~default:[] (Hashtbl.find_opt callers n) @ rest)
    in
    up (Option.value ~default:[] (Hashtbl.find_opt callers f))
  in
  List.filter (fun f -> not (Hashtbl.mem slot f) && not (deliverable f)) changed

(** [<actor lowercased-first>_migrate_state] in the manifest (the name the
    compiler aliases as [__migrate_<Actor>]). *)
let has_migrate_state (m : Cmd_deploy_hot.manifest) actor =
  let sfx = "_migrate_state" in
  List.exists (fun (f : Cmd_deploy_hot.fn_manifest) ->
      let n = f.fn_name in
      let ln = String.length n and ls = String.length sfx in
      ln > ls && String.sub n (ln - ls) ls = sfx
      && String.capitalize_ascii (short (String.sub n 0 (ln - ls))) = short actor)
    m.functions

let actor_changes (b : build_in) : actor_change list =
  let diffs = Schema_diff.diff_schemas b.b_old_schemas b.b_new_schemas in
  let with_state =
    List.map (fun (d : Schema_diff.actor_diff) ->
        let compat = match List.assoc_opt d.actor b.b_new_schemas with Some s -> s.Schema_diff.compat | None -> "full" in
        let migrate = has_migrate_state b.b_new d.actor in
        let compat_error =
          match Schema_diff.check_compat compat d.changes with
          | Ok () -> None
          | Error m -> if migrate then None else Some m
        in
        (d.actor, d.changes, migrate, compat_error))
      diffs
  in
  let msgs =
    List.filter_map (fun (actor, (ns : Schema_diff.actor_schema)) ->
        match List.assoc_opt actor b.b_old_schemas with
        | Some { Schema_diff.handlers = Some oh; _ } ->
          (match ns.handlers with
           | Some nh when Schema_diff.messages_changed ~old_h:oh ~new_h:nh ->
             Some (actor, match ns.migrate_msg_from with
               | None -> `None
               | Some f when f = oh -> `Matches
               | Some _ -> `Wrong_old_type)
           | _ -> None)
        | _ -> None)
      b.b_new_schemas
  in
  let actors = List.sort_uniq String.compare (List.map (fun (a, _, _, _) -> a) with_state @ List.map fst msgs) in
  List.map (fun a ->
      let (state, migrate, compat_error) =
        match List.find_opt (fun (x, _, _, _) -> x = a) with_state with
        | Some (_, c, m, e) -> (c, m, e)
        | None -> ([], false, None)
      in
      let mm = List.assoc_opt a msgs in
      { ac_actor = a; ac_state = state; ac_migrate = migrate; ac_compat_error = compat_error;
        ac_msgs = mm <> None; ac_migrate_msg = Option.value ~default:`None mm })
    actors

let pool_named (t : Topology.t) n = List.find_opt (fun (p : Topology.pool) -> p.pool_name = n) t.pools

(** The protocols a pool takes part in: what it serves, what it initiates
    (written, else derived). *)
let pool_protocols ~(derived : derived option) (p : Topology.pool) : string list =
  let initiates =
    match p.initiates with
    | Some l -> l
    | None -> (match Option.bind derived (List.assoc_opt p.pool_name) with Some (_, i) -> i | None -> [])
  in
  List.sort_uniq String.compare
    (List.filter_map (fun r -> match String.split_on_char '.' r with [ pr; _ ] -> Some pr | _ -> None)
       (p.serves @ initiates))

let pool_roles ~(derived : derived option) (p : Topology.pool) : string list =
  let initiates =
    match p.initiates with
    | Some l -> l
    | None -> (match Option.bind derived (List.assoc_opt p.pool_name) with Some (_, i) -> i | None -> [])
  in
  List.sort_uniq String.compare (p.serves @ initiates)

let build_of (t : Topology.t) pool = Reconcile.build_of_pool t pool

let fp_of (m : Cmd_deploy_hot.manifest option) proto =
  Option.bind m (fun m ->
      let target = proto ^ "_Msg.fingerprint" in
      let tl = String.length target in
      List.find_map (fun (f : Cmd_deploy_hot.fn_manifest) ->
          let n = f.fn_name in
          let ln = String.length n in
          if n = target || (ln > tl && String.sub n (ln - tl - 1) (tl + 1) = "." ^ target) then Some f.fn_impl_hash
          else None)
        m.functions)

(** The functions of a role's side of a protocol: the generated
    [<P>_<Role>.*] module, plus the role's bound body or actor. *)
let role_functions (t : Topology.t) (m : Cmd_deploy_hot.manifest) ~proto ~role (names : string list) =
  let gen = proto ^ "_" ^ role ^ "." in
  let bound =
    match List.find_opt (fun (r : Topology.role) -> r.role_name = proto ^ "." ^ role) t.roles with
    | Some r ->
      List.filter_map (fun x -> x) [ Option.map (manifest_name m) r.body;
                                      Option.map (fun a -> short (manifest_name m a) ^ "_dispatch") r.actor ]
    | None -> []
  in
  List.filter (fun n ->
      let gl = String.length gen in
      (String.length n >= gl && String.sub n 0 gl = gen)
      || contains n ("." ^ gen)
      || List.mem n bound || List.mem (short n) (List.map short bound))
    names

(* ── classify ─────────────────────────────────────────────────────────── *)

let classify (i : input) : plan =
  let t = i.i_new_topology in
  let first = List.for_all (fun b -> b.b_old = None) i.i_builds in
  let builds = List.map (fun b -> (b, fn_diff b.b_old b.b_new, actor_changes b)) i.i_builds in
  let build_named n = List.find_opt (fun (b, _, _) -> b.b_name = n) builds in
  (* protocols *)
  let protocols =
    List.filter_map (fun (name, o, n) ->
        let pools = List.filter_map (fun (p : Topology.pool) ->
            if List.mem name (pool_protocols ~derived:i.i_new_derived p) then Some p.pool_name else None) t.pools in
        let fp_old = List.find_map (fun (b, _, _) -> fp_of b.b_old name) builds in
        let fp_new = List.find_map (fun (b, _, _) -> fp_of (Some b.b_new) name) builds in
        let change =
          match classify_proto o n with
          | Same when fp_old <> None && fp_new <> None && fp_old <> fp_new ->
            (* the declaration reads the same but the wire fingerprint moved
               (a payload type's definition changed) *)
            Breaking "its wire fingerprint changed (a payload type changed)"
          | c -> c
        in
        let fp_moved = fp_old <> fp_new in
        if change = Same && not fp_moved then None
        else if o = None && n <> None && first then None
        else Some { pr_name = name; pr_fp = (fp_old, fp_new); pr_change = change; pr_pools = pools })
      i.i_protocols
  in
  (* placement *)
  let placement = match i.i_old_topology with Some o -> Reconcile.diff_topologies o t | None -> [] in
  let pools_of_subject subject =
    if String.length subject > 5 && String.sub subject 0 5 = "pool " then [ String.sub subject 5 (String.length subject - 5) ]
    else List.filter_map (fun (p : Topology.pool) -> if List.mem subject p.serves then Some p.pool_name else None) t.pools
  in
  (* hooks *)
  let hooks =
    List.filter_map (fun (p : Topology.pool) ->
        match p.start, build_named (build_of t p.pool_name) with
        | Some hook, Some (b, _, _) ->
          (match b.b_old with
           | Some o when impl_of_q o hook <> impl_of_q b.b_new hook -> Some (p.pool_name, hook)
           | _ -> None)
        | _ -> None)
      t.pools
  in
  (* base image identity *)
  let runtime =
    List.concat_map (fun (b, _, _) ->
        match b.b_old with
        | None -> []
        | Some o ->
          (if o.target <> b.b_new.target then
             [ (b.b_name, Printf.sprintf "target %s -> %s" (Option.value ~default:"?" o.target)
                  (Option.value ~default:"?" b.b_new.target)) ] else [])
          @ (if o.hcr_abi <> None && o.hcr_abi <> b.b_new.hcr_abi then
               [ (b.b_name, Printf.sprintf "HCR ABI %s -> %s" (Option.value ~default:"?" o.hcr_abi)
                    (Option.value ~default:"?" b.b_new.hcr_abi)) ] else [])
          @ (match b.b_old_runtime, b.b_new_runtime with
              | Some x, Some y when x <> y ->
                [ (b.b_name, Printf.sprintf "C runtime %s -> %s" (String.sub x 0 (min 12 (String.length x)))
                     (String.sub y 0 (min 12 (String.length y)))) ]
              | _ -> []))
      builds
  in
  (* authority *)
  let widenings =
    let derived_w =
      match i.i_old_derived, i.i_new_derived with
      | Some od, Some nd ->
        List.filter_map (fun (pool, (caps, _)) ->
            let prior = match List.assoc_opt pool od with Some (c, _) -> c | None -> [] in
            let w = Cmd_deploy_hot.compute_cap_widening ~prior ~new_caps:caps in
            if w = [] then None
            else
              let ungranted = Cmd_deploy_hot.filter_granted_widening ~widening:w ~grant_caps:i.i_grant_caps in
              Some { w_pool = pool; w_what = "derived caps (D26)"; w_caps = w; w_granted = ungranted = [] })
          nd
      | _ -> []
    in
    let role_w =
      List.concat_map (fun (b, _, _) ->
          match b.b_old with
          | Some o when o.roles <> [] ->
            List.filter_map (fun ((rm : Cmd_deploy_hot.role_manifest), w) ->
                let role = rm.role_name in
                let ungranted = Cmd_deploy_hot.filter_granted_widening ~widening:w ~grant_caps:i.i_grant_caps in
                let pools = List.filter_map (fun (p : Topology.pool) ->
                    if List.mem role p.serves && build_of t p.pool_name = b.b_name then Some p.pool_name else None) t.pools in
                Some { w_pool = (match pools with [] -> "build " ^ b.b_name | ps -> String.concat "," ps);
                       w_what = "role " ^ role ^ "'s closure"; w_caps = w; w_granted = ungranted = [] })
              (Option.value ~default:[] (Cmd_deploy_hot.compute_role_widening ~prior:o ~current:b.b_new))
          | _ -> [])
        builds
    in
    derived_w @ role_w
  in
  (* the D21 splits *)
  let splits =
    List.concat_map (fun pr ->
        match pr.pr_change with
        | Choice_added ca ->
          List.filter_map (fun (b, fd, _) ->
              let roles = List.concat_map (fun pool ->
                  match pool_named t pool with Some p -> pool_roles ~derived:i.i_new_derived p | None -> []) b.b_pools in
              let has r = List.mem (pr.pr_name ^ "." ^ r) roles in
              if has ca.ca_by && List.exists has ca.ca_receivers then
                let touched = fd.changed @ fd.added in
                Some { sp_protocol = pr.pr_name; sp_build = b.b_name; sp_choice = ca;
                       sp_held = role_functions t b.b_new ~proto:pr.pr_name ~role:ca.ca_by touched }
              else None)
            builds
        | _ -> [])
      protocols
  in
  (* per-pool mechanism *)
  let compact =
    List.filter_map (fun (b, _, _) ->
        if b.b_old = None then None
        else if i.i_compact then Some (b.b_name, "--compact")
        else
          match i.i_compact_after with
          | Some n ->
            let stack = List.fold_left (fun acc l ->
                if List.mem l.l_pool b.b_pools then max acc (Option.value ~default:0 l.l_stack) else acc) 0 i.i_live in
            if stack > n then Some (b.b_name, Printf.sprintf "a persisted patch stack of %d entries is above compact_after = %d" stack n)
            else None
          | None -> None)
      builds
  in
  let any_placement = List.exists (fun (c : Reconcile.change) -> c.kind = Reconcile.Placement) placement in
  let pools =
    List.map (fun (p : Topology.pool) ->
        let bname = build_of t p.pool_name in
        let (b, fd, acs) = match build_named bname with
          | Some x -> x
          | None -> ({ b_name = bname; b_pools = [ p.pool_name ]; b_old = None;
                       b_new = { Cmd_deploy_hot.version = 1; cas_hash = ""; target = None; hcr_abi = None;
                                 module_prefix = None; functions = []; roles = [] };
                       b_old_schemas = []; b_new_schemas = []; b_old_runtime = None; b_new_runtime = None;
                       b_slots = None },
                     { changed = []; added = []; removed = []; sig_changed = [] }, [])
        in
        let blocked =
          List.filter_map (fun ac ->
              match ac.ac_compat_error with
              | Some m -> Some (Printf.sprintf "actor %s: %s, and no %s_migrate_state" ac.ac_actor m (String.uncapitalize_ascii ac.ac_actor))
              | None -> None) acs
          @ List.filter_map (fun ac ->
              if ac.ac_migrate_msg = `Wrong_old_type then
                Some (Printf.sprintf "actor %s: %s_migrate_msg's old type is not the running version's handlers"
                        ac.ac_actor (String.uncapitalize_ascii ac.ac_actor))
              else None) acs
          @ List.filter_map (fun w ->
              if (not w.w_granted) && List.mem p.pool_name (String.split_on_char ',' w.w_pool) then
                Some (Printf.sprintf "%s widens to %s: needs --grant-cap" w.w_what (String.concat ", " w.w_caps))
              else None) widenings
        in
        let restart =
          (if b.b_old = None then [ "nothing is deployed yet: install the base build and start it" ] else [])
          @ List.filter_map (fun (pool, hook) ->
              if pool = p.pool_name then Some (Printf.sprintf "hook %s changed (hooks run once, at start)" hook) else None) hooks
          @ List.filter_map (fun (bn, what) -> if bn = bname then Some (what ^ " (the base image changes)") else None) runtime
          @ List.filter_map (fun (c : Reconcile.change) ->
              if c.kind = Reconcile.Needs_restart && List.mem p.pool_name (pools_of_subject c.subject)
              then Some (Printf.sprintf "%s: %s" c.subject c.detail) else None) placement
          @ (match b.b_slots with
              | Some slots when b.b_old <> None ->
                (match undeliverable ~slots ~changed:fd.changed b.b_new with
                 | [] -> []
                 | fs ->
                   [ Printf.sprintf "%d changed function(s) have no dispatch slot in the running base build and no \
                                     changed caller that has one, so a hot patch cannot reach them: %s"
                       (List.length fs) (list_some_fwd fs) ])
              | _ -> [])
          @ (match List.assoc_opt bname compact with
              | Some why -> [ "compaction: " ^ why ^ "; the base image is rebuilt from the current version" ]
              | None -> [])
        in
        let drained =
          List.filter_map (fun pr ->
              if List.mem p.pool_name pr.pr_pools then
                match pr.pr_change with
                | Breaking _ | Choice_added _ | Removed -> Some pr.pr_name
                | Same when fst pr.pr_fp <> snd pr.pr_fp -> Some pr.pr_name
                | _ -> None
              else None) protocols
        in
        let migrated = List.filter_map (fun ac -> if ac.ac_state <> [] && ac.ac_migrate then Some ac.ac_actor else None) acs in
        let code = fd.changed <> [] || fd.added <> [] || fd.removed <> [] in
        (* A push reaches every node; it concerns this pool when a placement
           change names one of its roles or the pool itself. *)
        let push = List.exists (fun (c : Reconcile.change) ->
            c.kind = Reconcile.Placement && List.mem p.pool_name (pools_of_subject c.subject)) placement in
        let (mechanism, why) =
          if blocked <> [] then (Blocked blocked, blocked)
          else if restart <> [] then (Restart restart, restart)
          else if drained <> [] then
            (Hot_drain drained,
             List.map (fun pr -> Printf.sprintf "%s: fingerprint changed; its offers close and drain" pr) drained
             @ List.map (fun a -> Printf.sprintf "%s: state changed, migrate_state found" a) migrated)
          else if migrated <> [] then
            (Hot_migrate migrated, List.map (fun a -> Printf.sprintf "%s: state changed, migrate_state found" a) migrated)
          else if code then
            (Hot, [ Printf.sprintf "%d function(s) changed, %d added, %d removed" (List.length fd.changed)
                      (List.length fd.added) (List.length fd.removed) ])
          else if push then (Placement, [ "the topology alone changed: pushed, the nodes re-read it (D16)" ])
          else (Nothing, [ "no change" ])
        in
        let hosts = List.map (fun (h : Topology.host) -> h.host) p.hosts in
        { pp_pool = p.pool_name; pp_build = bname; pp_hosts = hosts; pp_mechanism = mechanism; pp_why = why;
          pp_push = push || any_placement || i.i_old_topology = None })
      t.pools
  in
  (* order: receivers of an added choice before its chooser *)
  let order_why = ref [] in
  let rank (pp : pool_plan) =
    List.fold_left (fun acc pr ->
        match pr.pr_change with
        | Choice_added ca when List.mem pp.pp_pool pr.pr_pools ->
          (match pool_named t pp.pp_pool with
           | Some p ->
             let roles = pool_roles ~derived:i.i_new_derived p in
             if List.mem (pr.pr_name ^ "." ^ ca.ca_by) roles && not (List.exists (fun r -> List.mem (pr.pr_name ^ "." ^ r) roles) ca.ca_receivers)
             then max acc 1 else acc
           | None -> acc)
        | _ -> acc)
      0 protocols
  in
  let pools = List.stable_sort (fun a b -> compare (rank a) (rank b)) pools in
  List.iter (fun pr ->
      match pr.pr_change with
      | Choice_added ca ->
        order_why := !order_why
                     @ [ Printf.sprintf "%s gained the branch `%s` of `choose by %s`: pools receiving it (%s) go before \
                                         pools choosing it (6.4)" pr.pr_name ca.ca_label ca.ca_by
                           (String.concat ", " (List.map (fun r -> pr.pr_name ^ "." ^ r) ca.ca_receivers)) ]
      | _ -> ())
    protocols;
  let derived =
    match i.i_new_derived with
    | None -> []
    | Some nd ->
      List.map (fun (pool, now) -> (pool, now, Option.bind i.i_old_derived (List.assoc_opt pool))) nd
  in
  { env = i.i_env; builds; protocols; placement; hooks; runtime; pools; order_why = !order_why; splits; widenings;
    derived; compact; live = i.i_live; topology = t; first }

(* ── render: the six blocks of 6.8 ────────────────────────────────────── *)

let mechanism_text = function
  | Nothing -> "nothing to do"
  | Placement -> "topology push only"
  | Hot -> "hot patch"
  | Hot_migrate _ -> "hot patch + migration"
  | Hot_drain _ -> "hot patch + protocol drain"
  | Restart _ -> "restart"
  | Blocked _ -> "BLOCKED"

let list_some ?(max = 6) xs =
  let n = List.length xs in
  let shown = List.filteri (fun i _ -> i < max) xs in
  String.concat ", " shown ^ (if n > max then Printf.sprintf ", ... (%d more)" (n - max) else "")

let short_hash = function None -> "none" | Some h -> String.sub h 0 (min 8 (String.length h))

let drain_ms (t : Topology.t) =
  match t.drain with
  | Some d -> (d.soft_ms, d.hard_ms)
  | None -> (None, None)

let ms_text dflt = function Some n -> Printf.sprintf "%d ms" n | None -> dflt ^ " (default)"

let render (p : plan) : string =
  let b = Buffer.create 4096 in
  let say fmt = Printf.bprintf b fmt in
  say "forge deploy --plan%s\n" (match p.env with Some e -> " (env " ^ e ^ ")" | None -> "");
  if p.first then say "nothing has been deployed to this environment yet\n";
  (* 1 *)
  say "\n1. What changed\n";
  let any = ref false in
  List.iter (fun ((bi : build_in), fd, acs) ->
      let pools = String.concat ", " bi.b_pools in
      if bi.b_old = None then begin
        any := true;
        say "  build %s (pools %s): first deploy, %d functions\n" bi.b_name pools (List.length fd.added)
      end else if fd.changed <> [] || fd.added <> [] || fd.removed <> [] || acs <> [] then begin
        any := true;
        say "  build %s (pools %s): %d function(s) changed, %d added, %d removed\n" bi.b_name pools
          (List.length fd.changed) (List.length fd.added) (List.length fd.removed);
        if fd.changed <> [] then say "    changed: %s\n" (list_some fd.changed);
        if fd.added <> [] then say "    added: %s (they ship inside the patch; their dispatch slots come with the next restart)\n" (list_some fd.added);
        if fd.removed <> [] then say "    removed: %s\n" (list_some fd.removed);
        if fd.sig_changed <> [] then say "    signature changed: %s\n" (list_some fd.sig_changed);
        List.iter (fun ac ->
            if ac.ac_state <> [] then
              say "    actor %s: state changed (%s)\n" ac.ac_actor
                (String.concat "; " (List.map (function
                     | Schema_diff.FieldAdded f -> "+" ^ f.Schema_diff.name ^ " : " ^ f.ty
                     | Schema_diff.FieldRemoved f -> "-" ^ f.Schema_diff.name
                     | Schema_diff.FieldTypeChanged c -> Printf.sprintf "%s : %s -> %s" c.name c.old_ty c.new_ty)
                     ac.ac_state));
            if ac.ac_msgs then say "    actor %s: message type changed\n" ac.ac_actor)
          acs
      end)
    p.builds;
  List.iter (fun pr ->
      any := true;
      let kind = match pr.pr_change with
        | Same -> "declaration unchanged"
        | Added -> "new"
        | Removed -> "removed"
        | Choice_added ca -> Printf.sprintf "the branch `%s` added to `choose by %s`" ca.ca_label ca.ca_by
        | Breaking why -> why
      in
      say "  protocol %s: fingerprint %s -> %s (%s)\n" pr.pr_name (short_hash (fst pr.pr_fp)) (short_hash (snd pr.pr_fp)) kind)
    p.protocols;
  List.iter (fun (c : Reconcile.change) -> any := true; say "  placement: %s: %s\n" c.subject c.detail) p.placement;
  List.iter (fun (pool, hook) -> any := true; say "  hook: %s (pool %s) changed\n" hook pool) p.hooks;
  List.iter (fun (bn, what) -> any := true; say "  base image of build %s: %s\n" bn what) p.runtime;
  if not !any then say "  nothing\n";
  (* 2 *)
  say "\n2. Mechanism and why\n";
  List.iter (fun pp ->
      say "  pool %s (build %s, %d host%s): %s%s\n" pp.pp_pool pp.pp_build (List.length pp.pp_hosts)
        (if List.length pp.pp_hosts = 1 then "" else "s") (mechanism_text pp.pp_mechanism)
        (if pp.pp_push && pp.pp_mechanism <> Placement && pp.pp_mechanism <> Nothing then " + topology push" else "");
      List.iter (fun w -> say "    %s\n" w) pp.pp_why)
    p.pools;
  (* 3 *)
  say "\n3. Order and splits\n";
  List.iteri (fun n pp -> say "  %d. pool %s (%s)\n" (n + 1) pp.pp_pool (mechanism_text pp.pp_mechanism)) p.pools;
  List.iter (fun w -> say "  %s\n" w) p.order_why;
  if p.pools <> [] && List.exists (fun pp -> pp.pp_push) p.pools then
    say "  the topology is pushed after the code, so no node offers a role before its code is there\n";
  List.iter (fun sp ->
      say "  SPLIT (D21): build %s both chooses and receives %s's new branch `%s` (`choose by %s`), so this is two deploys:\n"
        sp.sp_build sp.sp_protocol sp.sp_choice.ca_label sp.sp_choice.ca_by;
      say "    deploy one: everything except %s's side of %s%s\n" sp.sp_choice.ca_by sp.sp_protocol
        (if sp.sp_held = [] then "" else " (held back: " ^ list_some sp.sp_held ^ ")");
      say "    deploy two: %s's side, once every host runs deploy one; `forge deploy` stops after deploy one and \
           does deploy two when you run it again\n" sp.sp_choice.ca_by;
      say "    (the finer rule, which versions of which roles may share a session over wire tags, is build step 9's \
           compatibility table)\n")
    p.splits;
  (* 4 *)
  say "\n4. Drains\n";
  let (soft, hard) = drain_ms p.topology in
  let any = ref false in
  let live_in pool = List.filter (fun l -> l.l_pool = pool) p.live in
  List.iter (fun pp ->
      let running = List.fold_left (fun a l -> a + l.l_running) 0 (live_in pp.pp_pool) in
      match pp.pp_mechanism with
      | Hot_drain protos ->
        any := true;
        let offers = List.filter (fun r -> List.exists (fun pr -> String.length r > String.length pr
                                                                 && String.sub r 0 (String.length pr + 1) = pr ^ ".") protos)
            (match pool_named p.topology pp.pp_pool with Some po -> po.serves | None -> []) in
        say "  pool %s: offers close: %s; sessions live on the pool's nodes: %d; soft %s, hard %s\n" pp.pp_pool
          (if offers = [] then "(none: it only initiates)" else String.concat ", " offers) running
          (ms_text "30000 ms" soft) (ms_text "120000 ms" hard)
      | Restart _ when not p.first ->
        any := true;
        say "  pool %s: a restart drains every offer (SIGTERM); sessions live: %d; hard %s\n" pp.pp_pool running
          (ms_text "120000 ms" hard)
      | _ -> ())
    p.pools;
  if not !any then say "  none\n";
  (* 5 *)
  say "\n5. What may be lost\n";
  let any = ref false in
  List.iter (fun ((bi : build_in), _, acs) ->
      List.iter (fun ac ->
          if ac.ac_msgs && ac.ac_migrate_msg = `None then begin
            any := true;
            say "  build %s: actor %s's message type changed and it has no %s_migrate_msg: its queued old-format \
                 messages will be dropped (and counted)\n" bi.b_name ac.ac_actor (String.uncapitalize_ascii ac.ac_actor)
          end)
        acs)
    p.builds;
  List.iter (fun pp ->
      match pp.pp_mechanism with
      | Hot_drain protos ->
        let running = List.fold_left (fun a l -> a + l.l_running) 0 (live_in pp.pp_pool) in
        if running > 0 then begin
          any := true;
          say "  pool %s: %d live session(s) of %s run to their end or the hard deadline %s; D27's automatic drains \
               at loop boundaries are not in this build\n" pp.pp_pool running (String.concat ", " protos) (ms_text "120000 ms" hard)
        end
      | Restart _ when not p.first ->
        let running = List.fold_left (fun a l -> a + l.l_running) 0 (live_in pp.pp_pool) in
        if running > 0 then begin
          any := true;
          say "  pool %s: the restart ends %d live session(s) that have not finished by the hard deadline\n" pp.pp_pool running
        end
      | _ -> ())
    p.pools;
  List.iter (fun pr ->
      match pr.pr_change with
      | Choice_added ca when ca.ca_renumbered <> [] ->
        any := true;
        say "  protocol %s: the new branch renumbers unlabelled messages (%s): old peers would misread them; label \
             those steps to pin their tags\n" pr.pr_name
          (String.concat ", " (List.map (fun (a, b) -> a ^ " -> " ^ b) ca.ca_renumbered))
      | _ -> ())
    p.protocols;
  if not !any then say "  nothing\n";
  (* 6 *)
  say "\n6. Authority and derived values\n";
  if p.widenings = [] then say "  no capability widens\n";
  List.iter (fun w ->
      say "  %s %s widens to %s: %s\n" w.w_pool w.w_what (String.concat ", " w.w_caps)
        (if w.w_granted then "granted by --grant-cap" else
           "needs " ^ String.concat " " (List.map (fun c -> "--grant-cap " ^ c) w.w_caps)))
    p.widenings;
  List.iter (fun (pool, (caps, inits), old) ->
      let mark now before = if Some now = before then "" else if before = None then "" else "  [changed]" in
      say "  pool %s: caps %s%s; initiates %s%s\n" pool
        (if caps = [] then "(none)" else String.concat ", " caps) (mark caps (Option.map fst old))
        (if inits = [] then "(none)" else String.concat ", " inits) (mark inits (Option.map snd old)))
    p.derived;
  if p.derived = [] then say "  derived values: not available (the compiler's analysis did not run)\n";
  List.iter (fun (b, why) ->
      say "  compaction: build %s: %s; its hosts restart on a base image rebuilt from the current version and \
           their persisted patch stack is cleared\n" b why) p.compact;
  Buffer.contents b

let blocked (p : plan) = List.exists (fun pp -> match pp.pp_mechanism with Blocked _ -> true | _ -> false) p.pools
