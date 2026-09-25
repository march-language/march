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
                 b_old_runtime = base_runtime c build; b_new_runtime = runtime;
                 b_slots =
                   (let names = List.concat_map (fun (s : Reconcile.node_status) ->
                        if List.mem s.node.pool pools then
                          match s.reload with
                          | Some (Ok ri) -> List.map (fun (d : Cmd_deploy_hot.detail_slot) -> d.ds_name) ri.versions
                          | _ -> []
                        else []) status in
                    if names = [] then None else Some (List.sort_uniq String.compare names)) })
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

(* ── Carrying a plan out (item 4) ─────────────────────────────────────── *)

type opts = {
  yes        : bool;                    (** skip the confirmation *)
  grant_caps : string list;
  compact    : bool;                    (** [--compact] *)
  canary     : int;                     (** hot pools: this many hosts first, then a PING window *)
  timeout_ms : int;                     (** the canary window *)
  up_timeout : float;                   (** seconds a restarted node has to answer PING *)
  confirm    : string -> bool;          (** asks the operator; [yes] skips it *)
}

let ask_stdin prompt =
  if not (Unix.isatty Unix.stdin) then begin
    Printf.eprintf "%s(stdin is not a terminal: pass --yes to deploy without asking)\n%!" prompt;
    false
  end else begin
    print_string prompt;
    flush stdout;
    match In_channel.input_line stdin with
    | Some l -> (match String.lowercase_ascii (String.trim l) with "y" | "yes" -> true | _ -> false)
    | None -> false
  end

let default_opts = { yes = false; grant_caps = []; compact = false; canary = 0; timeout_ms = 30000; up_timeout = 60.;
                     confirm = ask_stdin }

(* The pending D21 split: which builds ran deploy one, with the artifact
   (cas hash) they ran it with. Deploy two runs when the same build is
   deployed again. *)

let read_split c : (string * string) list =
  match read_json (split_file c) with
  | Some (`Assoc kv) -> List.filter_map (fun (b, v) -> match v with `String h -> Some (b, h) | _ -> None) kv
  | _ -> []

let write_split c (entries : (string * string) list) =
  Reconcile.mkdir_p (dir c);
  Yojson.Safe.to_file (split_file c) (`Assoc (List.map (fun (b, h) -> (b, `String h)) entries))

let clear_split c = try Sys.remove (split_file c) with Sys_error _ -> ()

let pool_of c name = List.find (fun (p : Topology.pool) -> p.pool_name = name) c.t.pools

let nodes_of_pool c pool = List.filter (fun (n : Reconcile.ssh_node) -> n.sn_pool = pool) c.nodes

(** A base image for [build] and [target], built once per run. *)
let base_images : (string * string, string) Hashtbl.t = Hashtbl.create 4

let build_base c ~build ~pools ~target : (string, string) result =
  match Hashtbl.find_opt base_images (build, target) with
  | Some path -> Ok path
  | None ->
    let* flags = Topology_run.hot_reload_flags ~pubkey:c.pubkey c.proj in
    let target_opt = if target = local_target () then None else Some target in
    Printf.printf "building the %s base image for %s...\n%!" build target;
    let* out =
      Cmd_build.build ~release:false ?target:target_opt ~topology_pools:pools ~output_suffix:("-" ^ build)
        ?topology_env:c.env ~extra_flags:flags ()
    in
    Hashtbl.replace base_images (build, target) out;
    Ok out

(** Wait until the node's reload server answers PING. *)
let wait_up c (h : Hosts.host) ~timeout =
  let t0 = Unix.gettimeofday () in
  let rec go () =
    if Reconcile.ping ~transport:c.transport h then true
    else if Unix.gettimeofday () -. t0 > timeout then false
    else (Unix.sleepf 0.5; go ())
  in
  go ()

(** The health gate between hosts: the node answers PING (a restarted one
    gets [up_timeout] to come up), and forge.toml's health_check_url when
    there is one. *)
let health c ~(opts : opts) : Hosts.health = fun h ->
  let up = wait_up c h ~timeout:opts.up_timeout in
  if not up then Printf.eprintf "  %s did not answer PING within %.0f s\n%!" h.Hosts.name opts.up_timeout;
  up
  && (match c.proj.Project.hot_reload with
      | Some { Project.hr_health_check_url = Some url; _ } ->
        let ok = Cmd_deploy_hot.http_health_check ~url ~timeout_s:10 in
        if not ok then Printf.eprintf "  health check %s failed after %s\n%!" url h.Hosts.name;
        ok
      | _ -> true)

(** Restart one node on [binary]: upload it, give it the topology, restart
    its unit. The health gate waits for it to come up. *)
let restart_node c ~binary (n : Reconcile.ssh_node) : (unit, string) result =
  let p = pool_of c n.sn_pool in
  let remote = Host_layout.binary c.layout ~binary_name:(Topology.Gen.binary_name ~project:c.proj.Project.name p) in
  Printf.printf "  %s: uploading %s\n%!" n.sn.Hosts.name (Filename.basename binary);
  let* () = Remote.upload c.transport n.sn ~sudo:(c.layout.Host_layout.prefix = "") ~local:binary ~remote ~mode:0o755 in
  let script =
    Reconcile.sudo_prelude c.layout
    ^ Reconcile.put_file_script ~path:(Host_layout.topology_file c.layout) ~mode:0o644 (Topology.digest_text c.t)
    ^ Printf.sprintf "$SUDO %s restart %s\n" c.service_ctl (Remote.sh_quote (Host_layout.unit_name n.sn_pool))
  in
  let r = c.transport.Remote.exec n.sn script in
  if r.Remote.rc <> 0 then Error (Printf.sprintf "restart failed (exit %d): %s" r.rc (String.trim (r.err ^ r.out)))
  else (Printf.printf "  %s: restarted\n%!" n.sn.Hosts.name; Ok ())

(** A node's persisted patch stack (COMPACT), or None when it does not
    answer. *)
let stack_of c (h : Hosts.host) : Cmd_deploy_hot.stack_size option =
  match c.transport.Remote.with_socket h (fun conn ->
      Cmd_deploy_hot.send_line conn "COMPACT";
      Ok (Cmd_deploy_hot.parse_compact (Cmd_deploy_hot.recv_line conn))) with
  | Ok s -> s
  | Error _ -> None

(** Compaction's last step on a node restarted onto the rebuilt base image
    (plan 6.5): its persisted patch stack must be empty. A new base build
    makes the runtime set the old stack aside ([state.base-changed]); forge
    removes what was set aside. A stack still there (the rebuilt base has
    the same baseline hashes, so the runtime replayed it) is removed and the
    node restarted once more. *)
let clear_stack c ~(before : int option) (n : Reconcile.ssh_node) : (string, string) result =
  let dir = Host_layout.hcr_state_dir c.layout in
  let remove what =
    let script =
      Reconcile.sudo_prelude c.layout
      ^ Printf.sprintf "for f in %s/*/%s; do [ -e \"$f\" ] && $SUDO rm -f \"$f\" && echo \"removed $f\"; done; true\n"
        (Remote.sh_quote dir) what
    in
    let r = c.transport.Remote.exec n.sn script in
    if r.Remote.rc <> 0 then Error (Printf.sprintf "clearing the patch stack failed: %s" (String.trim r.err)) else Ok ()
  in
  let* () =
    match stack_of c n.sn with
    | Some st when st.Cmd_deploy_hot.st_entries > 0 ->
      Printf.printf "  %s: the stack survived the restart (%d entries); removing it and restarting again\n%!"
        n.sn.Hosts.name st.st_entries;
      let* () = remove "state" in
      let r = c.transport.Remote.exec n.sn
          (Reconcile.sudo_prelude c.layout
           ^ Printf.sprintf "$SUDO %s restart %s\n" c.service_ctl (Remote.sh_quote (Host_layout.unit_name n.sn_pool))) in
      if r.Remote.rc <> 0 then Error "the second restart failed"
      else if not (wait_up c n.sn ~timeout:60.) then Error "the node did not come back after the second restart"
      else Ok ()
    | _ -> Ok ()
  in
  let* () = remove "state.base-changed" in
  match stack_of c n.sn with
  | Some st when st.Cmd_deploy_hot.st_entries = 0 ->
    Ok (Printf.sprintf "%s: persisted patch stack cleared%s" n.sn.Hosts.name
          (match before with Some b when b > 0 -> Printf.sprintf " (was %d entr%s)" b (if b = 1 then "y" else "ies") | _ -> ""))
  | Some st -> Error (Printf.sprintf "%s still reports %d persisted entries" n.sn.Hosts.name st.st_entries)
  | None -> Error (Printf.sprintf "%s did not answer COMPACT after the restart" n.sn.Hosts.name)

let hr_strategy c = match c.proj.Project.hot_reload with Some hr -> hr.Project.hr_strategy | None -> "rolling"

(** Run [step] on a pool's nodes with forge.toml's strategy (rolling with
    the health gate, or simultaneous), or the canary flow. *)
let on_nodes c ~(opts : opts) ~canary (nodes : Reconcile.ssh_node list) (step : Reconcile.ssh_node -> (unit, string) result)
  : (unit, string) result =
  let by_host = List.map (fun (n : Reconcile.ssh_node) -> (n.sn.Hosts.name, n)) nodes in
  let hstep (h : Hosts.host) = step (List.assoc h.Hosts.name by_host) in
  let hosts = List.map (fun (n : Reconcile.ssh_node) -> n.sn) nodes in
  let failed rs = List.filter_map (fun ((h : Hosts.host), r) -> match r with Error m -> Some (h.Hosts.name ^ ": " ^ m) | Ok _ -> None) rs in
  let finish rs = match failed rs with [] -> Ok () | fs -> Error (String.concat "; " fs) in
  if canary > 0 && List.length hosts > canary then begin
    let first = List.filteri (fun i _ -> i < canary) hosts and rest = List.filteri (fun i _ -> i >= canary) hosts in
    let* () = finish (c.backend.run_on ~strategy:`All first hstep) in
    Printf.printf "  canary live on %d host(s); watching for %.0f s\n%!" canary (float_of_int opts.timeout_ms /. 1000.);
    let deadline = Unix.gettimeofday () +. float_of_int opts.timeout_ms /. 1000. in
    let rec watch () =
      if Unix.gettimeofday () >= deadline then Ok ()
      else match List.find_opt (fun h -> not (Reconcile.ping ~transport:c.transport h)) first with
        | Some h -> Error (Printf.sprintf "canary %s stopped responding; the other hosts are untouched" h.Hosts.name)
        | None -> Unix.sleepf (min 2.0 (max 0.0 (deadline -. Unix.gettimeofday ()))); watch ()
    in
    let* () = watch () in
    finish (c.backend.run_on ~strategy:`All rest hstep)
  end
  else if hr_strategy c = "simultaneous" then finish (c.backend.run_on ~strategy:`All hosts hstep)
  else finish (c.backend.run_on ~strategy:(`Rolling (health c ~opts)) hosts hstep)

(** Everything deployed is now the baseline of the next plan. *)
let record c ~(artifacts : artifact list) ~(restarted : string list) ~(derived : Deploy_plan.derived option) =
  Reconcile.mkdir_p (dir c);
  let seen = Hashtbl.create 4 in
  List.iter (fun a ->
      if not (Hashtbl.mem seen a.a_build) then begin
        Hashtbl.replace seen a.a_build ();
        copy_file a.a_manifest_path (manifest_file c a.a_build);
        if Sys.file_exists a.a_schemas then copy_file a.a_schemas (schemas_file c a.a_build)
        else (try Sys.remove (schemas_file c a.a_build) with Sys_error _ -> ());
        if List.mem a.a_build restarted || not (Sys.file_exists (base_file c a.a_build)) then
          Yojson.Safe.to_file (base_file c a.a_build)
            (`Assoc [ ("runtime", (match runtime_identity () with Some r -> `String r | None -> `Null));
                      ("target", `String a.a_target);
                      ("hcr_abi", (match a.a_manifest.hcr_abi with Some x -> `String x | None -> `Null));
                      ("cas_hash", `String a.a_manifest.cas_hash);
                      ("at", `Float (Unix.gettimeofday ())) ])
      end)
    artifacts;
  Option.iter (fun d -> Yojson.Safe.to_file (derived_file c) (derived_json d)) derived;
  Reconcile.record_deployed_topology ~root:c.root c.env c.t;
  let index = Topology.index_project ~root:c.root in
  let global = Filename.concat (Filename.concat c.root ".forge") "protocols" in
  List.iter (fun (p : Deploy_plan.proto) ->
      List.iter (fun d ->
          Reconcile.mkdir_p d;
          Yojson.Safe.to_file (Filename.concat d (p.p_name ^ ".json")) (Deploy_plan.proto_json p))
        [ protocols_dir c; global ])
    (Deploy_plan.protos_of_index index)

(** The manifest to activate for [build]: the whole new manifest, less the
    functions a pending D21 split holds back to deploy two. *)
let without (m : Cmd_deploy_hot.manifest) held =
  { m with functions = List.filter (fun (f : Cmd_deploy_hot.fn_manifest) -> not (List.mem f.fn_name held)) m.functions }

(** [forge deploy --env <env>]: plan, confirm, carry out, record. *)
let run ?transport ?service_ctl ?layout_prefix ~proj ~env ~(opts : opts) () : (string, string) result =
  let* c = setup ?transport ?service_ctl ?layout_prefix ~proj ~env () in
  Reconcile.with_lock ~root:c.root (fun () ->
      let* (plan, artifacts, derived) = make_plan c ~grant_caps:opts.grant_caps ~compact:opts.compact in
      (* Deploy two of a pending split: the same artifact, deployed again. *)
      let pending = read_split c in
      let two =
        List.filter (fun (b, h) ->
            List.exists (fun a -> a.a_build = b && a.a_manifest.Cmd_deploy_hot.cas_hash = h) artifacts)
          pending
      in
      if pending <> [] && two = [] then begin
        Printf.printf "note: the pending split's deploy two is superseded by a new build; planning afresh\n%!";
        clear_split c
      end;
      let plan =
        if two = [] then plan
        else
          { plan with
            pools = List.map (fun (pp : Deploy_plan.pool_plan) ->
                if List.mem_assoc pp.pp_build two && pp.pp_mechanism = Deploy_plan.Nothing then
                  { pp with pp_mechanism = Deploy_plan.Hot;
                            pp_why = [ "deploy two of the D21 split: the chooser's side" ] }
                else pp) plan.pools;
            splits = List.filter (fun (sp : Deploy_plan.split) -> not (List.mem_assoc sp.sp_build two)) plan.splits }
      in
      print_string (Deploy_plan.render plan);
      if Deploy_plan.blocked plan then
        Error "the deploy is blocked (see \"2. Mechanism and why\"); nothing was changed"
      else if List.for_all (fun (pp : Deploy_plan.pool_plan) -> pp.pp_mechanism = Deploy_plan.Nothing && not pp.pp_push) plan.pools
      then Ok "nothing to deploy"
      else if not (opts.yes || opts.confirm (Printf.sprintf "\ndeploy to %s? [y/N] " (Reconcile.env_key c.env))) then
        Error "not deployed"
      else begin
        let hot_nodes = List.concat_map (fun (pp : Deploy_plan.pool_plan) ->
            match pp.pp_mechanism with
            | Deploy_plan.Hot | Hot_migrate _ | Hot_drain _ -> nodes_of_pool c pp.pp_pool
            | _ -> []) plan.pools in
        let epoch = Reconcile.shared_epoch ~transport:c.transport (List.map (fun (n : Reconcile.ssh_node) -> n.sn) hot_nodes) in
        if epoch > 0 then Printf.printf "\n==> shared epoch %d\n%!" epoch;
        let entry_path = Result.value (Project.entry c.proj) ~default:"" in
        let restarted = ref [] in
        let artifact_for build target =
          match List.find_opt (fun a -> a.a_build = build && a.a_target = target) artifacts with
          | Some a -> Ok a
          | None -> Error (Printf.sprintf "no %s patch was built for %s" build target)
        in
        let held build =
          if List.mem_assoc build two then []
          else List.concat_map (fun (sp : Deploy_plan.split) -> if sp.sp_build = build then sp.sp_held else []) plan.splits
        in
        let step_pool (pp : Deploy_plan.pool_plan) : (unit, string) result =
          let nodes = nodes_of_pool c pp.pp_pool in
          match pp.pp_mechanism with
          | Deploy_plan.Nothing | Placement | Blocked _ -> Ok ()
          | Restart why ->
            Printf.printf "\n==> pool %s: restart (%s)\n%!" pp.pp_pool (String.concat "; " why);
            let pools = (List.assoc pp.pp_build (List.map (fun (b, ps) -> (b, ps)) (Topology_run.builds_of c.t))) in
            if nodes = [] then Printf.printf "  (pool %s has no hosts in this environment)\n%!" pp.pp_pool
            else restarted := pp.pp_build :: !restarted;
            let compacting = List.mem_assoc pp.pp_build plan.compact in
            let* () =
              on_nodes c ~opts ~canary:0 nodes (fun n ->
                  let* binary = build_base c ~build:pp.pp_build ~pools ~target:(Option.get n.sn_target) in
                  restart_node c ~binary n)
            in
            if not compacting then Ok ()
            else
              List.fold_left (fun acc (n : Reconcile.ssh_node) ->
                  let* () = acc in
                  let before = Option.bind (List.find_opt (fun (l : Deploy_plan.live) -> l.l_node = n.sn.Hosts.name) plan.live)
                      (fun l -> l.l_stack) in
                  let* msg = clear_stack c ~before n in
                  Printf.printf "  %s\n%!" msg;
                  Ok ())
                (Ok ()) nodes
          | Hot | Hot_migrate _ | Hot_drain _ ->
            Printf.printf "\n==> pool %s: %s\n%!" pp.pp_pool (Deploy_plan.mechanism_text pp.pp_mechanism);
            let held = held pp.pp_build in
            if held <> [] then Printf.printf "  deploy one of two: holding back %d function(s)\n%!" (List.length held);
            on_nodes c ~opts ~canary:opts.canary nodes (fun n ->
                let target = Option.get n.sn_target in
                let* a = artifact_for pp.pp_build target in
                let* () = Cmd_deploy_hot.check_host_target ~recorded:target ~manifest:a.a_manifest in
                let* _ =
                  Cmd_deploy_hot.deploy_one ~tunnel:c.transport.tunnel ~host:n.sn ~sk:c.sk
                    ~manifest:(without a.a_manifest held) ~so_path:a.a_so
                    ~old_schemas_path:(schemas_file c pp.pp_build) ~new_schemas_path:a.a_schemas ~entry_path
                    ~old_manifest_path:(manifest_file c pp.pp_build) ~provided_epoch:epoch ~grant_caps:opts.grant_caps ()
                in
                Ok ())
        in
        let rec pools = function
          | [] -> Ok ()
          | pp :: rest ->
            (match step_pool pp with
             | Ok () -> pools rest
             | Error m -> Error (Printf.sprintf "pool %s: %s (later pools were not touched)" pp.pp_pool m))
        in
        let* () = pools plan.pools in
        (* The topology last: no node offers a role before its code is there. *)
        let* () =
          if List.exists (fun (pp : Deploy_plan.pool_plan) -> pp.pp_push) plan.pools then begin
            Printf.printf "\n==> pushing the topology\n%!";
            let* r = c.backend.push_topology c.t in
            List.iter (fun (n, o) ->
                Printf.printf "  %s: %s\n%!" n (match o with
                    | Reconcile.Signalled -> "signalled"
                    | Not_running -> "not running"
                    | Not_reporting -> "persisted; not signalled (has not reported yet)"
                    | Push_failed m -> "FAILED: " ^ m))
              r.outcome;
            match List.filter_map (fun (n, o) -> match o with Reconcile.Push_failed m -> Some (n ^ ": " ^ m) | _ -> None) r.outcome with
            | [] -> Ok ()
            | fs -> Error ("the topology push failed on " ^ String.concat "; " fs)
          end else Ok ()
        in
        record c ~artifacts ~restarted:!restarted ~derived;
        if plan.splits <> [] then begin
          write_split c (List.sort_uniq compare (List.filter_map (fun (sp : Deploy_plan.split) ->
              Option.map (fun a -> (sp.sp_build, a.a_manifest.Cmd_deploy_hot.cas_hash))
                (List.find_opt (fun a -> a.a_build = sp.sp_build) artifacts)) plan.splits));
          Ok (Printf.sprintf "deploy one of two is done (D21). Once every host runs it, run `forge deploy%s` again \
                              for deploy two." (env_flag c.env))
        end else begin
          if two <> [] then clear_split c;
          Ok "deploy complete"
        end
      end)
