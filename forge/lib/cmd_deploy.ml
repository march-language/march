(** [forge deploy --env <env> [--plan] [--yes] [--compact]]: one
    reconciliation pass over the ssh backend (distributed-deploys plan 5,
    6.5, 6.8, II.8; build step 10b).

    [forge deploy hot] (unchanged) patches functions; [forge deploy]
    decides, per pool, how to get from what is deployed to what the working
    tree says: hot patch, hot patch with migration or a protocol drain,
    restart, a topology push, or nothing. Users never choose between "hot"
    and "restart" (6.8). The decision is [Deploy_plan.classify]; this
    module gathers its inputs and carries it out.

    {1 What forge keeps: [.forge/deploy/<env>/]}

    What was last deployed to the environment, the observed side of the
    next plan: [topology.json]; per build [<build>.hcr_manifest],
    [<build>.schemas.json] and [<build>.base.json] (the base image's
    C-runtime digest, target, ABI); [derived.json] (each pool's derived
    caps and initiated roles); [protocols/<P>.json]; [pending_split.json]
    while a D21 split waits for its second deploy. Every successful deploy
    also writes [.forge/protocols/<P>.json] (the current build's
    protocols, the baseline build step 9's compiler will read). *)

let ( let* ) = Result.bind

type ctx = {
  proj      : Project.project;
  root      : string;
  env       : string option;
  t         : Topology.t;
  nodes     : Reconcile.ssh_node list;
  sk        : bytes;
  pubkey    : string;
  prefix    : string;                 (** the hot-reload module prefix *)
  transport : Remote.transport;
  service_ctl : string;
  layout    : Host_layout.t;
  backend   : Reconcile.backend;
}

let env_flag env = match env with Some e -> " --env " ^ e | None -> ""

(** The ssh backend's context for [env], or why there is none. *)
let setup ?(transport = Remote.ssh) ?(service_ctl = "systemctl") ?(layout_prefix = "") ~(proj : Project.project)
    ~env () : (ctx, string) result =
  let root = proj.Project.root in
  if not (Topology.exists ~root) then
    Error "`forge deploy` deploys a topology app (topology.toml); for a single server use `forge deploy hot`"
  else
    let env = Reconcile.existing_overlay ~root env in
    let* t = Reconcile.load_checked ~root env in
    let* () =
      if Reconcile.is_ssh t then Ok ()
      else Error (Printf.sprintf "the topology%s does not say `[backend] kind = \"ssh\"`; `forge deploy` needs the ssh \
                                  backend (a local cluster is reconciled by `forge topology apply`)"
                    (match env with Some e -> Printf.sprintf " with topology.%s.toml" e | None -> ""))
    in
    ignore (Topology.write_digest ~root t);
    let* (backend, nodes, sk) = Reconcile.ssh_backend ~transport ~service_ctl ~layout_prefix ~proj ~env t in
    let missing = List.filter (fun (n : Reconcile.ssh_node) -> n.sn_target = None) nodes in
    let* () =
      if missing = [] then Ok ()
      else Error (Printf.sprintf "%s %s not been initialised: run `forge host init%s` first"
                    (String.concat ", " (List.map (fun (n : Reconcile.ssh_node) -> n.sn.Hosts.ssh) missing))
                    (if List.length missing = 1 then "has" else "have") (env_flag env))
    in
    let* prefix =
      match proj.Project.hot_reload with
      | Some { Project.hr_module_prefix = Some p; _ } -> Ok p
      | _ -> Topology_run.entry_module proj
    in
    Ok { proj; root; env; t; nodes; sk; pubkey = Reconcile.deploy_pubkey ~proj sk; prefix; transport; service_ctl;
         layout = Host_layout.make ~prefix:layout_prefix proj.Project.name; backend }

(* ── Paths of what was deployed ───────────────────────────────────────── *)

let dir c = Reconcile.deploy_dir ~root:c.root c.env
let manifest_file c build = Reconcile.deployed_manifest_file ~root:c.root c.env build
let schemas_file c build = Filename.concat (dir c) (build ^ ".schemas.json")
let base_file c build = Filename.concat (dir c) (build ^ ".base.json")
let derived_file c = Filename.concat (dir c) "derived.json"
let protocols_dir c = Filename.concat (dir c) "protocols"
let split_file c = Filename.concat (dir c) "pending_split.json"
let work_dir c = Filename.concat (dir c) "build"

let copy_file src dst =
  Reconcile.mkdir_p (Filename.dirname dst);
  match In_channel.with_open_bin src In_channel.input_all with
  | s -> Out_channel.with_open_bin dst (fun oc -> output_string oc s)
  | exception Sys_error _ -> ()

(* ── The toolchain's C runtime (the base image's identity) ────────────── *)

(** The runtime directory the [march] this forge runs compiles against:
    MARCH_RUNTIME_DIR, else next to the resolved [march] executable (the
    compiler's own exe-relative search). *)
let march_runtime_dir () : string option =
  match Sys.getenv_opt "MARCH_RUNTIME_DIR" with
  | Some d when d <> "" && Sys.file_exists (Filename.concat d "march_runtime.c") -> Some d
  | _ ->
    let ic = Unix.open_process_in "command -v march 2>/dev/null" in
    let exe = String.trim (In_channel.input_all ic) in
    ignore (Unix.close_process_in ic);
    if exe = "" then None
    else
      let exe = try Unix.realpath exe with Unix.Unix_error _ -> exe in
      let d = Filename.dirname exe in
      List.find_opt (fun c -> Sys.file_exists (Filename.concat c "march_runtime.c"))
        [ Filename.concat d "../runtime"; Filename.concat d "../../runtime"; Filename.concat d "../../../runtime";
          Filename.concat d "../lib/march/runtime" ]

let runtime_identity () : string option =
  Option.map March_cas.Cas.runtime_identity_of_dir (march_runtime_dir ())

(* ── Targets and builds ───────────────────────────────────────────────── *)

(** This machine, as a canonical target ("darwin/arm64", "linux/amd64"). *)
let local_target () =
  let ic = Unix.open_process_in "uname -sm" in
  let s = String.trim (In_channel.input_all ic) in
  ignore (Unix.close_process_in ic);
  Option.value ~default:"" (Cmd_deploy_hot.canonical_of_triple s)

(** The [--target] flag for a host's recorded target: none for this
    machine's own target (a native build), [--target linux/<arch>] for a
    Linux host, else unsupported. *)
let target_flag (target : string) : (string, string) result =
  if target = local_target () then Ok ""
  else match target with
    | "linux/amd64" | "linux/arm64" -> Ok (" --target " ^ target)
    | t -> Error (Printf.sprintf "forge cannot build for %s from this machine (%s)" t (local_target ()))

(** The builds of the topology and the targets their hosts need. *)
let builds c : (string * string list * string list) list =
  List.map (fun (build, pools) ->
      let targets =
        List.sort_uniq String.compare
          (List.filter_map (fun (n : Reconcile.ssh_node) -> if List.mem n.sn_pool pools then n.sn_target else None) c.nodes)
      in
      (build, pools, targets))
    (Topology_run.builds_of c.t)

type artifact = {
  a_build    : string;
  a_target   : string;
  a_so       : string;
  a_manifest : Cmd_deploy_hot.manifest;
  a_manifest_path : string;
  a_schemas  : string;
}

(** Build [build]'s hot-reload patch for [target] (in a fresh directory:
    a CAS hit would copy the .so without its sidecars, the step-8 trap). *)
let build_patch c ~build ~pools ~target : (artifact, string) result =
  let* tflag = target_flag target in
  let* entry = Project.entry c.proj in
  let entry = if Filename.is_relative entry then Filename.concat c.root entry else entry in
  let out = Filename.concat (work_dir c) (Printf.sprintf "%s-%s" build (String.map (fun ch -> if ch = '/' then '-' else ch) target)) in
  (try ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote out))) with _ -> ());
  Reconcile.mkdir_p out;
  let so = Filename.concat out "patch.so" in
  let log = Filename.concat out "build.log" in
  let pools_flag = if build = "shared" then "" else " --topology-pools " ^ Filename.quote (String.concat "," pools) in
  let cmd =
    Printf.sprintf "cd %s && %smarch --compile --compile-so --hot-reload %s --signing-pubkey %s%s --topology %s%s%s -o %s %s > %s 2>&1"
      (Filename.quote out) (Cmd_build.lib_path_env c.proj) (Filename.quote c.prefix) (Filename.quote c.pubkey) tflag
      (Filename.quote (Topology.digest_file ~root:c.root)) pools_flag
      (Cmd_build.ffi_flags_of ~root:c.root c.proj) (Filename.quote so) (Filename.quote entry) (Filename.quote log)
  in
  Printf.printf "building the %s patch for %s...\n%!" build target;
  if Sys.command cmd <> 0 then Error (Printf.sprintf "building build %s for %s failed; see %s" build target log)
  else
    let mpath = so ^ ".hcr_manifest" in
    let* m = Cmd_deploy_hot.parse_manifest mpath in
    Ok { a_build = build; a_target = target; a_so = so; a_manifest = m; a_manifest_path = mpath; a_schemas = so ^ ".schemas.json" }

(** Build every (build, target) patch the hosts need. *)
let build_patches c : (artifact list, string) result =
  List.fold_left (fun acc (build, pools, targets) ->
      let* acc = acc in
      List.fold_left (fun acc target ->
          let* acc = acc in
          let* a = build_patch c ~build ~pools ~target in
          Ok (acc @ [ a ]))
        (Ok acc) targets)
    (Ok []) (builds c)

(* ── What was deployed ────────────────────────────────────────────────── *)

let read_json path = try Some (Yojson.Safe.from_file path) with _ -> None

let base_runtime c build =
  match read_json (base_file c build) with
  | Some j -> (match Yojson.Safe.Util.member "runtime" j with `String s when s <> "" -> Some s | _ -> None)
  | None -> None

let derived_of_json j : Deploy_plan.derived option =
  let module U = Yojson.Safe.Util in
  try
    Some (List.map (fun (pool, v) ->
        (pool, (List.map U.to_string (U.to_list (U.member "caps" v)),
                List.map U.to_string (U.to_list (U.member "initiates" v)))))
        (U.to_assoc j))
  with _ -> None

let derived_json (d : Deploy_plan.derived) : Yojson.Safe.t =
  `Assoc (List.map (fun (pool, (caps, inits)) ->
      (pool, `Assoc [ ("caps", `List (List.map (fun s -> `String s) caps));
                      ("initiates", `List (List.map (fun s -> `String s) inits)) ])) d)

(** The deployed protocol structures: the environment's, else the last
    build's [.forge/protocols/]. *)
let old_protocol c name : Deploy_plan.proto option =
  let file d = Filename.concat d (name ^ ".json") in
  let global = Filename.concat (Filename.concat c.root ".forge") "protocols" in
  match read_json (file (protocols_dir c)) with
  | Some j -> Deploy_plan.proto_of_json j
  | None -> Option.bind (read_json (file global)) Deploy_plan.proto_of_json

let live_of_status (ss : Reconcile.node_status list) : Deploy_plan.live list =
  List.map (fun (s : Reconcile.node_status) ->
      { Deploy_plan.l_node = s.node.name; l_pool = s.node.pool; l_up = s.up;
        l_running = (match s.report with Some r -> r.r_running | None -> 0);
        l_offers = (match s.report with Some r -> r.r_offers | None -> []);
        l_stack = (match s.reload with
            | Some (Ok ri) -> Option.map (fun st -> st.Cmd_deploy_hot.st_entries) ri.compact
            | _ -> None) })
    ss

(** Everything [Deploy_plan.classify] needs, with the patches it was
    computed from. [derived]: the compiler's analysis, when it could run. *)
let gather c ~grant_caps ~compact ~(artifacts : artifact list) ~(derived : Deploy_plan.derived option)
    ~(status : Reconcile.node_status list) : Deploy_plan.input =
  let index = Topology.index_project ~root:c.root in
  let old_t =
    let p = Reconcile.deployed_topology_file ~root:c.root c.env in
    if Sys.file_exists p then Result.to_option (Topology.read_digest p) else None
  in
  let runtime = runtime_identity () in
  let builds =
    List.filter_map (fun (build, pools, _) ->
        match List.find_opt (fun a -> a.a_build = build) artifacts with
        | None -> None
        | Some a ->
          let old = Result.to_option (Cmd_deploy_hot.parse_manifest (manifest_file c build)) in
          Some { Deploy_plan.b_name = build; b_pools = pools;
                 b_old = (if Sys.file_exists (manifest_file c build) then old else None);
                 b_new = a.a_manifest;
                 b_old_schemas = Schema_diff.parse_schemas_file (schemas_file c build);
                 b_new_schemas = Schema_diff.parse_schemas_file a.a_schemas;
                 b_old_runtime = base_runtime c build; b_new_runtime = runtime })
      (builds c)
  in
  let now = Deploy_plan.protos_of_index index in
  let names = List.sort_uniq String.compare (List.map (fun (p : Deploy_plan.proto) -> p.p_name) now) in
  let protocols = List.map (fun n ->
      (n, old_protocol c n, List.find_opt (fun (p : Deploy_plan.proto) -> p.p_name = n) now)) names in
  let compact_after =
    match c.proj.Project.hot_reload with
    | Some hr -> hr.Project.hr_compact_after
    | None -> None
  in
  { Deploy_plan.i_env = c.env; i_old_topology = old_t; i_new_topology = c.t; i_builds = builds; i_protocols = protocols;
    i_old_derived = Option.bind (read_json (derived_file c)) derived_of_json; i_new_derived = derived;
    i_grant_caps = grant_caps; i_live = live_of_status status; i_compact = compact; i_compact_after = compact_after }

(** Build, gather and classify: the plan and the patches it is for. *)
let make_plan c ~grant_caps ~compact : (Deploy_plan.plan * artifact list * Deploy_plan.derived option, string) result =
  let* artifacts = build_patches c in
  let derived =
    match Topology_run.compiler_derived c.proj with
    | Ok d -> Some d
    | Error m -> Printf.eprintf "warning: derived caps unavailable: %s\n%!" m; None
  in
  let status = c.backend.status () in
  let input = gather c ~grant_caps ~compact ~artifacts ~derived ~status in
  Ok (Deploy_plan.classify input, artifacts, derived)

(** [forge deploy --plan]: print the plan; change nothing. *)
let plan_only ?transport ?service_ctl ?layout_prefix ~proj ~env ~grant_caps ~compact () : (string, string) result =
  let* c = setup ?transport ?service_ctl ?layout_prefix ~proj ~env () in
  let* (plan, _, _) = make_plan c ~grant_caps ~compact in
  Ok (Deploy_plan.render plan)
