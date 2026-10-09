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
    - Per protocol: its version as the environment runs it (the deploy
      baseline, [.forge/deploy/<env>/protocols/<P>.json], in the compiler's
      baseline format) and as this build has it (the compiler's
      [--emit-protocols] output of a check against those baselines): the
      wire view of build step 9 (every message's sender, receiver, wire tag
      and payload key) and the fingerprint. [Desugar_endpoints.compare_versions]
      says what KIND of change it is. The generated [<P>_Msg.fingerprint]
      function's impl hash is the fallback when no deploy baseline reads.
    - A pending expand/contract split ([.forge/deploy/<env>/pending_split.json]).
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
    deploy, so it becomes two (D21), decided by [Protocol_split.plan]:
    deploy one (expand) builds every build with
    [--protocol-expand <P>:<label>], so the receivers run the new protocol
    while the chooser keeps offering under the previous fingerprint and
    cannot choose the new branch; deploy two (contract), run once every host
    has deploy one, is the plain build. The deploy baseline of [P] moves to
    the new version only with the contract. A change the compatibility rule
    does not allow (renumbered unlabelled messages among them, named by the
    compiler) is breaking: both fingerprints are offered while it rolls
    through. *)

(* ── Protocol versions ────────────────────────────────────────────────── *)

module E = March_desugar.Desugar_endpoints

type choice_added = {
  ca_by : string;                 (** the chooser *)
  ca_receivers : string list;     (** who receives the choice *)
  ca_label : string;              (** the new branch *)
}

type proto_change =
  | Same
  | Added
  | Removed
  | Choice_added of choice_added
  | Breaking of string

(** Rule one (the compiler's [compare_versions]) on a deployed and a new
    version. *)
let classify_proto (o : E.version option) (n : E.version option) : proto_change =
  match o, n with
  | None, None -> Same
  | None, Some _ -> Added
  | Some _, None -> Removed
  | Some o, Some n ->
    (match E.compare_versions ~old_:o ~new_:n with
     | E.Same -> Same
     | E.Compatible { chooser; label; receivers } ->
       Choice_added { ca_by = chooser; ca_receivers = receivers; ca_label = label }
     | E.Incompatible why -> Breaking why)

(** An expand whose contract has not gone out yet: deploy one of [pe_protocol]
    ran with [--protocol-expand <pe_protocol>:<pe_label>] for the version
    whose fingerprint is [pe_fingerprint]. *)
type pending = {
  pe_protocol    : string;
  pe_label       : string;
  pe_fingerprint : string;
  pe_builds      : string list;
}

let pending_json (ps : pending list) : Yojson.Safe.t =
  `Assoc [ ("format", `Int 2);
           ("pending", `List (List.map (fun p ->
                `Assoc [ ("protocol", `String p.pe_protocol); ("label", `String p.pe_label);
                         ("fingerprint", `String p.pe_fingerprint);
                         ("builds", `List (List.map (fun b -> `String b) p.pe_builds)) ]) ps)) ]

(** None when [j] is not this format (a step-10b [pending_split.json], which
    named builds and artifacts, reads as nothing pending). *)
let pending_of_json (j : Yojson.Safe.t) : pending list option =
  let module U = Yojson.Safe.Util in
  try
    if U.member "format" j <> `Int 2 then None
    else
      Some (List.map (fun p ->
          { pe_protocol = U.to_string (U.member "protocol" p); pe_label = U.to_string (U.member "label" p);
            pe_fingerprint = U.to_string (U.member "fingerprint" p);
            pe_builds = List.map U.to_string (U.to_list (U.member "builds" p)) })
          (U.to_list (U.member "pending" j)))
  with _ -> None

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
  i_protocols    : (string * E.version option * E.version option) list;  (** name, deployed, now *)
  i_pending      : pending list;  (** expands whose contract is due *)
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

(** One protocol's D21 split, and which half this deploy is. *)
type split = {
  sp_protocol : string;
  sp_builds   : string list;        (** the builds that both choose and receive it *)
  sp_choice   : choice_added;
  sp_old_fp   : string;             (** the deployed fingerprint: the chooser's during the expand *)
  sp_new_fp   : string;
  sp_phase    : [ `Expand | `Contract ];
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
  verdict    : Protocol_split.verdict;             (** the whole protocol verdict, for its reasons *)
  pending    : pending list;                       (** as read; a stale entry is reported *)
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
    did not change is not deliverable either.  A slot of the NEW build that
    the running one lacks is reached by any running slot above it: the
    executor redeploys that caller to carry it
    ([Cmd_deploy_hot.unslotted_carriers]), changed or not. *)
let undeliverable ~(slots : string list) ~(changed : string list) (m : Cmd_deploy_hot.manifest) : string list =
  let slot = Hashtbl.create 64 and chg = Hashtbl.create 64 and callers = Hashtbl.create 4096 in
  List.iter (fun n -> Hashtbl.replace slot n ()) slots;
  List.iter (fun n -> Hashtbl.replace chg n ()) changed;
  List.iter (fun (f : Cmd_deploy_hot.fn_manifest) -> Hashtbl.replace callers f.fn_name f.fn_callers) m.functions;
  let new_slot = Hashtbl.create 16 in
  List.iter (fun n -> Hashtbl.replace new_slot n ()) (Option.value ~default:[] m.slots);
  let deliverable f =
    let carried = Hashtbl.mem new_slot f in
    let seen = Hashtbl.create 16 in
    let rec up = function
      | [] -> false
      | n :: rest when Hashtbl.mem seen n -> up rest
      | n :: rest ->
        Hashtbl.replace seen n ();
        if Hashtbl.mem slot n then carried || Hashtbl.mem chg n || up rest
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

(** The roles a build holds: its pools' served and initiated roles, as
    "Protocol.Role" ([Protocol_split.build]). *)
let split_builds ~(derived : derived option) (t : Topology.t) (builds : (string * string list) list)
  : Protocol_split.build list =
  List.map (fun (name, pools) ->
      { Protocol_split.b_name = name;
        b_roles = List.sort_uniq String.compare (List.concat_map (fun pool ->
            match pool_named t pool with Some p -> pool_roles ~derived p | None -> []) pools) })
    builds

(** The protocol verdict and the D21 splits of a deploy, from the versions
    alone: what [Cmd_deploy] needs BEFORE it builds (an expand's builds take
    [--protocol-expand]), and what [classify] reports. A split whose expand
    already went out for this very version (in [pending]) is due its
    contract; any other is an expand. *)
let splits_of ~(derived : derived option) (t : Topology.t) ~(builds : (string * string list) list)
    ~(protocols : (string * E.version option * E.version option) list) ~(pending : pending list)
  : Protocol_split.verdict * split list =
  let changes =
    List.filter_map (fun (_, o, n) -> match o, n with
        | Some o, Some n -> Some { Protocol_split.old_ = o; new_ = n }
        | _ -> None) protocols
  in
  let sbuilds = split_builds ~derived t builds in
  let verdict = Protocol_split.plan changes sbuilds in
  let splits =
    match verdict with
    | Protocol_split.Split (expand, _) ->
      List.filter_map (fun (proto, label) ->
          match List.find_opt (fun (n, _, _) -> n = proto) protocols with
          | Some (_, Some o, Some n) ->
            (match classify_proto (Some o) (Some n) with
             | Choice_added ca ->
               let holds (b : Protocol_split.build) r = List.mem (proto ^ "." ^ r) b.b_roles in
               let both = List.filter_map (fun (b : Protocol_split.build) ->
                   if holds b ca.ca_by && List.exists (holds b) ca.ca_receivers then Some b.b_name else None) sbuilds in
               let expanded = List.exists (fun pe ->
                   pe.pe_protocol = proto && pe.pe_label = label && pe.pe_fingerprint = n.v_fingerprint) pending in
               Some { sp_protocol = proto; sp_builds = both; sp_choice = ca; sp_old_fp = o.v_fingerprint;
                      sp_new_fp = n.v_fingerprint; sp_phase = (if expanded then `Contract else `Expand) }
             | _ -> None)
          | _ -> None)
        expand.d_protocols
    | _ -> []
  in
  (verdict, splits)

(** The compiler flags of this deploy's builds: an expand for every split
    whose expand has not gone out. *)
let expand_flags (splits : split list) : string list =
  List.filter_map (fun sp ->
      if sp.sp_phase = `Expand then Some (Protocol_split.expand_flag ~proto:sp.sp_protocol ~label:sp.sp_choice.ca_label)
      else None) splits

(** What the deploy leaves pending: the expands it runs. *)
let pending_after (splits : split list) : pending list =
  List.filter_map (fun sp ->
      if sp.sp_phase = `Expand then
        Some { pe_protocol = sp.sp_protocol; pe_label = sp.sp_choice.ca_label; pe_fingerprint = sp.sp_new_fp;
               pe_builds = sp.sp_builds }
      else None) splits

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
        (* The fingerprint function's impl hash: what the manifests say, for a
           protocol with no deploy baseline to read (deployed by an older
           forge, whose file held its own structure). *)
        let h_old = List.find_map (fun (b, _, _) -> fp_of b.b_old name) builds in
        let h_new = List.find_map (fun (b, _, _) -> fp_of (Some b.b_new) name) builds in
        let fp v = Option.map (fun (v : E.version) -> v.v_fingerprint) v in
        let unknown =
          Breaking "its wire fingerprint changed, and this environment has no deploy baseline to compare it \
                    against (so the kind of change is unknown)"
        in
        let (change, pr_fp) =
          match o, n with
          | Some _, _ -> (classify_proto o n, (fp o, fp n))
          | None, Some _ when h_old = None || first -> (Added, (None, fp n))
          | None, _ -> ((if h_old = h_new then Same else unknown), (h_old, h_new))
        in
        if change = Same then None
        else if change = Added && first then None
        else Some { pr_name = name; pr_fp; pr_change = change; pr_pools = pools })
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
  (* the D21 splits (Protocol_split, over the versions) *)
  let (verdict, splits) =
    splits_of ~derived:i.i_new_derived t ~builds:(List.map (fun (b, _, _) -> (b.b_name, b.b_pools)) builds)
      ~protocols:i.i_protocols ~pending:i.i_pending
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
                                 module_prefix = None; stdlib_hash = None; slots = None;
                                 functions = []; roles = [] };
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
          (* A stdlib change reaches no dispatch slot (stdlib actors are not
             slots, 2026-09-30): it is a toolchain change, a restart. *)
          @ (match b.b_old with
              | Some o -> Option.to_list (Cmd_deploy_hot.stdlib_change ~prior:o ~current:b.b_new)
              | None -> [])
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
             List.map (fun pr ->
                 match List.find_opt (fun sp -> sp.sp_protocol = pr) splits with
                 | Some sp when sp.sp_phase = `Expand ->
                   Printf.sprintf "%s: the expand of a D21 split: its receivers' offers reopen under the new \
                                   fingerprint and drain the old; %s.%s's stay" pr pr sp.sp_choice.ca_by
                 | Some sp ->
                   Printf.sprintf "%s: the contract of a D21 split: %s.%s's offers reopen under the new fingerprint \
                                   and drain the old" pr pr sp.sp_choice.ca_by
                 | None -> Printf.sprintf "%s: fingerprint changed; its offers close and drain" pr) drained
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
      | Choice_added ca when not (List.exists (fun sp -> sp.sp_protocol = pr.pr_name) splits) ->
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
  { env = i.i_env; builds; protocols; placement; hooks; runtime; pools; order_why = !order_why; splits; verdict;
    pending = i.i_pending; widenings;
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

(** Whether role [r] (["P.Role"]) of [proto] closes its offer in this
    deploy: under a split, the expand keeps the chooser's (it stays on the
    previous fingerprint) and the contract closes only the chooser's. *)
let closes (p : plan) ~proto r =
  match List.find_opt (fun sp -> sp.sp_protocol = proto) p.splits with
  | None -> true
  | Some sp ->
    let is_chooser = r = proto ^ "." ^ sp.sp_choice.ca_by in
    if sp.sp_phase = `Expand then not is_chooser else is_chooser

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
  let fp8 f = short_hash (Some f) in
  List.iter (fun sp ->
      let roles rs = String.concat ", " (List.map (fun r -> sp.sp_protocol ^ "." ^ r) rs) in
      let chooser = sp.sp_protocol ^ "." ^ sp.sp_choice.ca_by in
      say "  SPLIT (D21): build%s %s both make%s and receive%s %s's changed choice (`choose by %s` gained `%s`), \
           so no order within one deploy puts its receivers first: the change is two deploys\n"
        (if List.length sp.sp_builds = 1 then "" else "s") (String.concat ", " sp.sp_builds)
        (if List.length sp.sp_builds = 1 then "s" else "") (if List.length sp.sp_builds = 1 then "s" else "")
        sp.sp_protocol sp.sp_choice.ca_by sp.sp_choice.ca_label;
      let this = " <- this deploy" in
      say "    deploy one (expand)%s: every build compiled with %s. The receivers (%s) run the new version \
           (fingerprint %s) and accept the previous one; %s keeps offering and initiating under the previous \
           fingerprint %s and cannot choose `%s`; guard it with %s.may_choose_%s()\n"
        (if sp.sp_phase = `Expand then this else ", done")
        (Protocol_split.expand_flag ~proto:sp.sp_protocol ~label:sp.sp_choice.ca_label)
        (roles sp.sp_choice.ca_receivers) (fp8 sp.sp_new_fp) chooser (fp8 sp.sp_old_fp) sp.sp_choice.ca_label
        (sp.sp_protocol ^ "_" ^ sp.sp_choice.ca_by) sp.sp_choice.ca_label;
      say "    deploy two (contract)%s: the plain build, once every host runs deploy one. %s moves to fingerprint \
           %s and may choose `%s`%s\n"
        (if sp.sp_phase = `Contract then this else "")
        chooser (fp8 sp.sp_new_fp) sp.sp_choice.ca_label
        (if sp.sp_phase = `Expand then "; `forge deploy` stops after deploy one: run it again for deploy two" else ""))
    p.splits;
  List.iter (fun pr ->
      match pr.pr_change with
      | Breaking why ->
        say "  protocol %s: a breaking change (%s): every node offers both fingerprints while the deploy rolls \
             through (6.4); a session forms only among roles of one fingerprint, and old-fingerprint sessions \
             finish or end at the hard deadline\n" pr.pr_name why
      | _ -> ())
    p.protocols;
  List.iter (fun pe ->
      if not (List.exists (fun sp -> sp.sp_protocol = pe.pe_protocol && sp.sp_phase = `Contract) p.splits) then
        say "  note: %s's pending contract (deploy two, for `%s` at fingerprint %s) no longer applies: the protocol \
             changed again or back, so this deploy is planned against what the environment runs\n"
          pe.pe_protocol pe.pe_label (fp8 pe.pe_fingerprint))
    p.pending;
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
                                                                 && String.sub r 0 (String.length pr + 1) = pr ^ "."
                                                                 && closes p ~proto:pr r) protos)
            (match pool_named p.topology pp.pp_pool with Some po -> po.serves | None -> []) in
        say "  pool %s: offers close: %s; sessions live on the pool's nodes: %d; soft %s, hard %s\n" pp.pp_pool
          (if offers <> [] then String.concat ", " offers
           else if List.exists (fun r -> List.exists (fun pr -> contains r (pr ^ ".")) protos)
               (match pool_named p.topology pp.pp_pool with Some po -> po.serves | None -> [])
           then "(none: its offers stay under the previous fingerprint until the contract)"
           else "(none: it only initiates)") running
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
      | Breaking why when contains why "wire tags" ->
        (* the compiler names the renumbered messages and suggests labels *)
        any := true;
        say "  protocol %s: %s; no session forms between its old and new fingerprints\n" pr.pr_name why
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
