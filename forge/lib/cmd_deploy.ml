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
    caps and initiated roles); [protocols/<P>.json], the deploy baselines:
    each protocol's version as the environment runs it, in the compiler's
    baseline format, passed to every deploy build as [--protocol-baseline]
    (so a patch's [<P>_Msg.compat()] table is computed against what is
    running) and advanced only by a deploy that completes (and, for a D21
    split, only by its contract); [pending_split.json] while a D21 split's
    expand waits for its contract. [.forge/protocols/] belongs to the
    compiler (build step 9's baselines of the last BUILD,
    [--emit-protocols]); a deploy neither reads nor writes it.

    {1 Protocol changes (D21)}

    Before building, a [march --check] of the entry against the deploy
    baselines emits this version of every protocol into the work directory
    ([protocol_versions]). [Deploy_plan.splits_of] ([Protocol_split.plan])
    decides from the two versions whether a build both chooses and receives
    a changed choice; if so this deploy is the expand, and every patch and
    base build gets [--protocol-expand <P>:<label>]. The next [forge deploy]
    of the same version is the contract: the plain build. *)

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
(* where this deploy's check emits the new protocol versions *)
let new_protocols_dir c = Filename.concat (work_dir c) "protocols"

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

(** The [--target] flag for a host's recorded target. A Linux host always
    gets the cross target ([--target linux/<arch>]: zig with the bookworm
    sysroot, glibc 2.36), even from a Linux machine of the same arch: a
    native build links against this machine's newer glibc, which an older
    host cannot load (CI: an Ubuntu 24.04 build on a Debian bookworm host
    never came up). Another target is built natively only when it is this
    machine's own. FORGE_DEPLOY_NATIVE=1 builds a host of this machine's own
    target natively after all: for hosts that are this machine, or share its
    glibc (a local cluster, a test). *)
let target_flag (target : string) : (string, string) result =
  match target with
  | t when Sys.getenv_opt "FORGE_DEPLOY_NATIVE" = Some "1" && t = local_target () -> Ok ""
  | "linux/amd64" | "linux/arm64" -> Ok (" --target " ^ target)
  | t when t = local_target () -> Ok ""
  | t -> Error (Printf.sprintf "forge cannot build for %s from this machine (%s)" t (local_target ()))

(** The target [Cmd_build.build] takes: None for a native build. *)
let build_target (target : string) : string option =
  match target with
  | "linux/amd64" | "linux/arm64" -> Some target
  | _ -> None

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
let build_patch c ~pflags ~build ~pools ~target : (artifact, string) result =
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
    Printf.sprintf "cd %s && %smarch --compile --compile-so --hot-reload %s --signing-pubkey %s%s --topology %s%s%s%s -o %s %s > %s 2>&1"
      (Filename.quote out) (Cmd_build.lib_path_env c.proj) (Filename.quote c.prefix) (Filename.quote c.pubkey) tflag
      (Filename.quote (Topology.digest_file ~root:c.root)) pools_flag
      (Cmd_build.ffi_flags_of ~root:c.root c.proj) pflags (Filename.quote so) (Filename.quote entry) (Filename.quote log)
  in
  Printf.printf "building the %s patch for %s...\n%!" build target;
  if Sys.command cmd <> 0 then Error (Printf.sprintf "building build %s for %s failed; see %s" build target log)
  else
    let mpath = so ^ ".hcr_manifest" in
    let* m = Cmd_deploy_hot.parse_manifest mpath in
    Ok { a_build = build; a_target = target; a_so = so; a_manifest = m; a_manifest_path = mpath; a_schemas = so ^ ".schemas.json" }

(** Build every (build, target) patch the hosts need. *)
let build_patches c ~pflags : (artifact list, string) result =
  List.fold_left (fun acc (build, pools, targets) ->
      let* acc = acc in
      List.fold_left (fun acc target ->
          let* acc = acc in
          let* a = build_patch c ~pflags ~build ~pools ~target in
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

(* ── Protocol versions (D21) ──────────────────────────────────────────── *)

(** [--protocol-baseline] for every deploy baseline that reads (a file an
    older forge wrote there, in its own format, is left out: the compiler
    would refuse it). *)
let baseline_flags_of_dir (deployed : string) =
  String.concat ""
    (List.map (fun (path, _) -> " --protocol-baseline " ^ Filename.quote path)
       (Protocol_split.baselines_of_dir deployed))

(** The protocol flags of every build of a deploy: the deploy baselines in
    [deployed], and the expand of each split whose expand has not gone out. *)
let protocol_flags_of_dir (deployed : string) (splits : Deploy_plan.split list) =
  baseline_flags_of_dir deployed ^ String.concat "" (List.map (fun f -> " " ^ f) (Deploy_plan.expand_flags splits))

let protocol_build_flags c splits = protocol_flags_of_dir (protocols_dir c) splits

(** This version of every protocol [entry] declares: [march --check] (in
    [cwd], with [flags]) against the deploy baselines in [deployed],
    emitting into [out], emptied first. Each file there is the next deploy
    baseline: [current] this version, [previous] what runs when it changed. *)
let check_protocols ?(env = "") ?(flags = "") ~cwd ~deployed ~out ~log (entry : string)
  : ((string * March_desugar.Desugar_endpoints.version) list, string) result =
  (try ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote out))) with _ -> ());
  Reconcile.mkdir_p out;
  Reconcile.mkdir_p (Filename.dirname log);
  let cmd =
    Printf.sprintf "cd %s && %smarch --check%s%s --emit-protocols %s %s > %s 2>&1"
      (Filename.quote cwd) env flags (baseline_flags_of_dir deployed) (Filename.quote out) (Filename.quote entry)
      (Filename.quote log)
  in
  if Sys.command cmd <> 0 then Error (Printf.sprintf "checking the program's protocols failed; see %s" log)
  else Ok (Protocol_split.versions_of_dir out)

let protocol_versions c : ((string * March_desugar.Desugar_endpoints.version) list, string) result =
  let* entry = Project.entry c.proj in
  let entry = if Filename.is_relative entry then Filename.concat c.root entry else entry in
  check_protocols ~env:(Cmd_build.lib_path_env c.proj)
    ~flags:(" --topology " ^ Filename.quote (Topology.digest_file ~root:c.root) ^ Cmd_build.ffi_flags_of ~root:c.root c.proj)
    ~cwd:c.root ~deployed:(protocols_dir c) ~out:(new_protocols_dir c)
    ~log:(Filename.concat (work_dir c) "protocols.log") entry

(** After a deploy: every protocol's deploy baseline in [deployed] becomes
    the one this build emitted into [now], except a protocol whose expand
    this deploy ran ([expanding]: what runs is not yet that version's
    chooser). A protocol the program no longer declares (or an older
    forge's file) loses its baseline: nothing running is of it. *)
let advance_baselines ~(deployed : string) ~(now : string) ~(expanding : string list) =
  Reconcile.mkdir_p deployed;
  let emitted = Protocol_split.baselines_of_dir now in
  let names = List.map (fun (_, (b : March_desugar.Desugar_endpoints.baseline)) -> b.current.v_proto) emitted in
  List.iter (fun (path, (b : March_desugar.Desugar_endpoints.baseline)) ->
      if not (List.mem b.current.v_proto expanding) then
        copy_file path (Filename.concat deployed (b.current.v_proto ^ ".json")))
    emitted;
  Array.iter (fun f ->
      let name = Filename.remove_extension f in
      if Filename.check_suffix f ".json" && not (List.mem name names) && not (List.mem name expanding) then
        (try Sys.remove (Filename.concat deployed f) with Sys_error _ -> ()))
    (try Sys.readdir deployed with Sys_error _ -> [||])

(** Every protocol either side has: (name, deployed, now). *)
let protocol_pairs ~deployed ~now =
  let names = List.sort_uniq String.compare (List.map fst deployed @ List.map fst now) in
  List.map (fun n -> (n, List.assoc_opt n deployed, List.assoc_opt n now)) names

(** The expands waiting for their contract. *)
let read_pending c : Deploy_plan.pending list =
  match read_json (split_file c) with
  | Some j ->
    (match Deploy_plan.pending_of_json j with
     | Some ps -> ps
     | None ->
       Printf.printf "note: %s is from an older forge (it held back functions, not a protocol expand); ignoring it\n%!"
         (split_file c);
       [])
  | None -> []

let write_pending c (ps : Deploy_plan.pending list) =
  if ps = [] then (try Sys.remove (split_file c) with Sys_error _ -> ())
  else begin
    Reconcile.mkdir_p (dir c);
    Yojson.Safe.to_file (split_file c) (Deploy_plan.pending_json ps)
  end

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
    ~(status : Reconcile.node_status list) ~protocols ~pending : Deploy_plan.input =
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
  let compact_after =
    match c.proj.Project.hot_reload with
    | Some hr -> hr.Project.hr_compact_after
    | None -> None
  in
  { Deploy_plan.i_env = c.env; i_old_topology = old_t; i_new_topology = c.t; i_builds = builds; i_protocols = protocols;
    i_pending = pending;
    i_old_derived = Option.bind (read_json (derived_file c)) derived_of_json; i_new_derived = derived;
    i_grant_caps = grant_caps; i_live = live_of_status status; i_compact = compact; i_compact_after = compact_after }

(** Check, decide the split, build, gather and classify: the plan, the
    patches it is for, and the protocol flags every build of it takes.
    [status] is what the nodes report; by default the backend's (ssh). *)
let make_plan ?status c ~grant_caps ~compact
  : (Deploy_plan.plan * artifact list * Deploy_plan.derived option * string, string) result =
  let derived =
    match Topology_run.compiler_derived c.proj with
    | Ok d -> Some d
    | Error m -> Printf.eprintf "warning: derived caps unavailable: %s\n%!" m; None
  in
  let* now = protocol_versions c in
  let protocols = protocol_pairs ~deployed:(Protocol_split.versions_of_dir (protocols_dir c)) ~now in
  let pending = read_pending c in
  let (_, splits) =
    Deploy_plan.splits_of ~derived c.t ~builds:(List.map (fun (b, ps, _) -> (b, ps)) (builds c)) ~protocols ~pending
  in
  let pflags = protocol_build_flags c splits in
  let* artifacts = build_patches c ~pflags in
  let status = match status with Some f -> f () | None -> c.backend.status () in
  let input = gather c ~grant_caps ~compact ~artifacts ~derived ~status ~protocols ~pending in
  Ok (Deploy_plan.classify input, artifacts, derived, pflags)

(* ── Carrying a plan out (item 4) ─────────────────────────────────────── *)

type opts = {
  yes        : bool;                    (** skip the confirmation *)
  grant_caps : string list;
  compact    : bool;                    (** [--compact] *)
  canary     : int;                     (** hot pools: this many hosts first, then a PING window *)
  timeout_ms : int;                     (** the canary window *)
  up_timeout : float;                   (** seconds a restarted node has to answer PING *)
  follow_s   : float;                   (** cluster backend: how long to follow a release *)
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
                     follow_s = 1800.; confirm = ask_stdin }

let pool_of c name = List.find (fun (p : Topology.pool) -> p.pool_name = name) c.t.pools

let nodes_of_pool c pool = List.filter (fun (n : Reconcile.ssh_node) -> n.sn_pool = pool) c.nodes

(** A base image for [build] and [target], built once per run. *)
let base_images : (string * string * string, string) Hashtbl.t = Hashtbl.create 4

let build_base c ~pflags ~build ~pools ~target : (string, string) result =
  match Hashtbl.find_opt base_images (build, target, pflags) with
  | Some path -> Ok path
  | None ->
    let* flags = Topology_run.hot_reload_flags ~pubkey:c.pubkey c.proj in
    let target_opt = build_target target in
    Printf.printf "building the %s base image for %s...\n%!" build target;
    let* out =
      Cmd_build.build ~release:false ?target:target_opt ~topology_pools:pools ~output_suffix:("-" ^ build)
        ?topology_env:c.env ~extra_flags:flags ~protocol_flags:pflags ()
    in
    Hashtbl.replace base_images (build, target, pflags) out;
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
let restart_node c ?policy ~binary (n : Reconcile.ssh_node) : (unit, string) result =
  let p = pool_of c n.sn_pool in
  let remote = Host_layout.binary c.layout ~binary_name:(Topology.Gen.binary_name ~project:c.proj.Project.name p) in
  Printf.printf "  %s: uploading %s\n%!" n.sn.Hosts.name (Filename.basename binary);
  let* () = Remote.upload c.transport n.sn ~sudo:(c.layout.Host_layout.prefix = "") ~local:binary ~remote ~mode:0o755 in
  let script =
    Reconcile.sudo_prelude c.layout
    ^ Reconcile.put_file_script ~path:(Host_layout.topology_file c.layout) ~mode:0o644 (Topology.digest_text c.t)
    (* The node policy for the build being installed: the pool's caps plus
       its runner's (Host_init.runner_caps). Read by the node at start. *)
    ^ (match policy with
        | Some text -> Reconcile.put_file_script ~path:(Host_layout.policy_file c.layout n.sn_pool) ~mode:0o644 text
        | None -> "")
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

(** Everything deployed is now the baseline of the next plan; a protocol
    this deploy expanded keeps its deploy baseline until its contract. *)
let record c ~(artifacts : artifact list) ~(restarted : string list) ~(derived : Deploy_plan.derived option)
    ~(expanding : string list) =
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
  advance_baselines ~deployed:(protocols_dir c) ~now:(new_protocols_dir c) ~expanding

(** A restart-class pool, over the process backend (ssh): build the base
    image, upload it, restart each node onto it (rolling, with the health
    gate), and clear its patch stack when the plan compacts it. *)
let restart_pool c ~(opts : opts) ~(plan : Deploy_plan.plan) ~pflags ~(artifacts : artifact list) ~derived
    ~(restarted : string list ref) ~why (pp : Deploy_plan.pool_plan) : (unit, string) result =
  let nodes = nodes_of_pool c pp.pp_pool in
  Printf.printf "\n==> pool %s: restart (%s)\n%!" pp.pp_pool (String.concat "; " why);
  let pools = (List.assoc pp.pp_build (List.map (fun (b, ps) -> (b, ps)) (Topology_run.builds_of c.t))) in
  if nodes = [] then Printf.printf "  (pool %s has no hosts in this environment)\n%!" pp.pp_pool
  else restarted := pp.pp_build :: !restarted;
  let compacting = List.mem_assoc pp.pp_build plan.compact in
  let* () =
    on_nodes c ~opts ~canary:0 nodes (fun n ->
        let target = Option.get n.sn_target in
        let* binary = build_base c ~pflags ~build:pp.pp_build ~pools ~target in
        let manifest = Option.map (fun a -> a.a_manifest)
            (List.find_opt (fun a -> a.a_build = pp.pp_build && a.a_target = target) artifacts) in
        let policy = Host_init.policy_text ~derived ?manifest (pool_of c n.sn_pool) in
        restart_node c ?policy ~binary n)
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

(** [forge deploy --env <env>] on the ssh backend: plan, confirm, carry out, record. *)
let run_ssh c ~(opts : opts) : (string, string) result =
  Reconcile.with_lock ~root:c.root (fun () ->
      let* (plan, artifacts, derived, pflags) = make_plan c ~grant_caps:opts.grant_caps ~compact:opts.compact in
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
        let step_pool (pp : Deploy_plan.pool_plan) : (unit, string) result =
          let nodes = nodes_of_pool c pp.pp_pool in
          match pp.pp_mechanism with
          | Deploy_plan.Nothing | Placement | Blocked _ -> Ok ()
          | Restart why -> restart_pool c ~opts ~plan ~pflags ~artifacts ~derived ~restarted ~why pp
          | Hot | Hot_migrate _ | Hot_drain _ ->
            Printf.printf "\n==> pool %s: %s\n%!" pp.pp_pool (Deploy_plan.mechanism_text pp.pp_mechanism);
            on_nodes c ~opts ~canary:opts.canary nodes (fun n ->
                let target = Option.get n.sn_target in
                let* a = artifact_for pp.pp_build target in
                let* () = Cmd_deploy_hot.check_host_target ~recorded:target ~manifest:a.a_manifest in
                let* _ =
                  Cmd_deploy_hot.deploy_one ~tunnel:c.transport.tunnel ~host:n.sn ~sk:c.sk
                    ~manifest:a.a_manifest ~so_path:a.a_so
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
        let expanding = List.filter_map (fun (sp : Deploy_plan.split) ->
            if sp.sp_phase = `Expand then Some sp.sp_protocol else None) plan.splits in
        record c ~artifacts ~restarted:!restarted ~derived ~expanding;
        write_pending c (Deploy_plan.pending_after plan.splits);
        if expanding <> [] then
          Ok (Printf.sprintf "deploy one of two (the expand of %s) is done (D21). Every host runs it now; run \
                              `forge deploy%s` again for deploy two (the contract)."
                (String.concat ", " expanding) (env_flag c.env))
        else Ok "deploy complete"
      end)

(* ── The cluster backend (distributed-deploys step 12a; design section 9) ── *)

(** Which backend carries a deploy. [`Auto]: the cluster backend when the
    environment's topology has a [[control]] section, else ssh. The topology
    is what says how the environment runs: a node with the control plane
    takes its hot changes as sequenced releases from the leader, so forge
    sends it releases by default. [`Ssh] is the break-glass path (design 12,
    open question): the ssh deploy still works on such a node, which then
    holds a release the leader did not order (its next pass reports itself
    behind until a newer release is sent). *)
type via = [ `Auto | `Ssh | `Cluster ]

let choose_backend ~(via : via) (t : Topology.t) : ([ `Ssh | `Cluster ], string) result =
  match via, t.Topology.control with
  | `Ssh, _ -> Ok `Ssh
  | `Cluster, None -> Error "--via cluster needs the topology's [control] section (the control plane's candidates)"
  | (`Auto | `Cluster), Some _ -> Ok `Cluster
  | `Auto, None -> Ok `Ssh

let control_endpoints (t : Topology.t) = Cluster_deploy.endpoints_of_topology ?override:(Sys.getenv_opt "FORGE_CONTROL_ENDPOINTS") t

(** The nodes as the leader sees them, for the plan: a node is up when it
    reports in STATUS. The leader does not relay a node's sessions, hot slots
    or patch stack, so the plan's drain counts, its slot check and automatic
    compaction (compact_after) work from what forge recorded; [--compact]
    still forces a compaction. *)
let cluster_node_status c (s : Cluster_deploy.status) : Reconcile.node_status list =
  List.map (fun (n : Reconcile.ssh_node) ->
      let seen = List.exists (fun (x : Cluster_deploy.node_state) -> x.n_name = n.sn.Hosts.name) s.nodes in
      { Reconcile.node = { Reconcile.name = n.sn.Hosts.name; pool = n.sn_pool; pid = 0; port = n.sn_port; socket = None;
                           labels = n.sn.Hosts.labels; status_path = ""; log = ""; host = n.sn.Hosts.ssh };
        up = seen; report = None; reload = None })
    c.nodes

(** One part of a deploy on the cluster backend, in the plan's order: a
    release (hot pools, and the topology at the end), or a restart-class pool
    run over the process backend (D38). *)
type segment =
  | Release of { pools : Deploy_plan.pool_plan list; topology : bool }
  | Process of Deploy_plan.pool_plan * string list

let is_hot (m : Deploy_plan.mechanism) = match m with Deploy_plan.Hot | Hot_migrate _ | Hot_drain _ -> true | _ -> false

(** The plan's pools as segments: consecutive hot pools share a release; a
    restart closes the release before it (the order is the plan's: receivers
    of a choice before its chooser); the topology goes last. *)
let segments (plan : Deploy_plan.plan) : segment list =
  let push = List.exists (fun (pp : Deploy_plan.pool_plan) -> pp.pp_push) plan.pools in
  let rec go acc hot = function
    | [] ->
      List.rev (if hot <> [] || push then Release { pools = List.rev hot; topology = push } :: acc else acc)
    | (pp : Deploy_plan.pool_plan) :: rest ->
      (match pp.pp_mechanism with
       | m when is_hot m -> go acc (pp :: hot) rest
       | Deploy_plan.Restart why ->
         let acc = if hot <> [] then Release { pools = List.rev hot; topology = false } :: acc else acc in
         go (Process (pp, why) :: acc) [] rest
       | _ -> go acc hot rest)
  in
  go [] [] plan.pools

(** A release's scratch directory: short, because the recorder listens on a
    Unix socket in it, and a socket path under a project's [.forge/] easily
    passes the 104-byte [sun_path] limit (macOS). *)
let release_scratch n =
  let base = if Sys.file_exists "/tmp" then "/tmp" else Filename.get_temp_dir_name () in
  Filename.concat base (Printf.sprintf "forge-release-%d-%d" (Unix.getpid ()) n)

let remove_scratch n = ignore (Sys.command ("rm -rf " ^ Filename.quote (release_scratch n)))

(** The release spec for a segment's hot pools: one build per build name,
    its patch, and what forge last deployed of it (the recorder's baseline). *)
let release_spec c ~(opts : opts) ~eps ~(artifacts : artifact list) ~n (pools : Deploy_plan.pool_plan list) ~topology
  : (Cluster_deploy.spec, string) result =
  let builds = List.sort_uniq String.compare (List.map (fun (pp : Deploy_plan.pool_plan) -> pp.pp_build) pools) in
  let* hot =
    List.fold_left (fun acc build ->
        let* acc = acc in
        match List.filter (fun a -> a.a_build = build) artifacts with
        | [] -> Error (Printf.sprintf "no %s patch was built" build)
        | _ :: _ :: _ ->
          Error (Printf.sprintf "build %s runs on hosts of more than one target, and a release names one patch per \
                                 build: deploy it with --via ssh" build)
        | [ a ] ->
          Ok (acc @ [ { Cluster_deploy.hb_name = build;
                        hb_pools = List.filter_map (fun (pp : Deploy_plan.pool_plan) ->
                            if pp.pp_build = build then Some pp.pp_pool else None) pools;
                        hb_manifest = a.a_manifest; hb_so = a.a_so; hb_old_manifest = manifest_file c build;
                        hb_old_schemas = schemas_file c build; hb_new_schemas = a.a_schemas } ]))
      (Ok []) builds
  in
  Ok { Cluster_deploy.env = Reconcile.env_key c.env; endpoints = eps; sk = c.sk; pubkey = c.pubkey; hot;
       topology_body = Topology.digest_text c.t; push_topology = topology; canary = opts.canary;
       canary_window_ms = opts.timeout_ms; rest_window_ms = 0;
       work_dir = release_scratch n;
       entry_path = Result.value (Project.entry c.proj) ~default:""; grant_caps = opts.grant_caps; follow_s = opts.follow_s }

(** How the deploy is carried out on the cluster backend, for the plan. *)
let render_segments c (segs : segment list) : string =
  let b = Buffer.create 256 in
  Buffer.add_string b "\n6. Through the control plane\n";
  List.iteri (fun i seg ->
      match seg with
      | Release { pools; topology } ->
        Printf.bprintf b "  %d. a release (no ssh): %s%s\n" (i + 1)
          (if pools = [] then "" else "hot patch of pool(s) " ^ String.concat ", " (List.map (fun (pp : Deploy_plan.pool_plan) -> pp.pp_pool) pools))
          (if topology then (if pools = [] then "" else ", then ") ^ "the topology" else "")
      | Process (pp, why) ->
        Printf.bprintf b "  %d. NEEDS SSH (the process backend, D38): restart pool %s on %s (%s)\n" (i + 1) pp.pp_pool
          (match nodes_of_pool c pp.pp_pool with
           | [] -> "(no hosts)"
           | ns -> String.concat ", " (List.map (fun (n : Reconcile.ssh_node) -> n.sn.Hosts.ssh) ns))
          (String.concat "; " why))
    segs;
  if List.for_all (function Release _ -> true | Process _ -> false) segs then
    Buffer.add_string b "  every step goes through the control plane; nothing needs ssh\n";
  Buffer.contents b

(** The plan and the cluster's view, for both [--plan] and a deploy. A
    control plane that does not answer (nothing runs yet: the first deploy,
    all restarts over ssh) is planned as no node running; a release then
    waits for it to answer ([Cluster_deploy.prepare]). *)
let cluster_plan c ~(opts : opts) =
  let* eps = control_endpoints c.t in
  let head =
    match Cluster_deploy.status eps with
    | Ok s -> s
    | Error m ->
      Printf.eprintf "note: %s; planning as if no node runs\n%!" m;
      Cluster_deploy.no_status
  in
  let* (plan, artifacts, derived, pflags) =
    make_plan ~status:(fun () -> cluster_node_status c head) c ~grant_caps:opts.grant_caps ~compact:opts.compact in
  Ok (eps, head, plan, artifacts, derived, pflags)

(** [forge deploy --plan] on the cluster backend: the plan, then each release
    it would sign, in full (each saved under the work directory). A release's
    seq and parent are taken again when it is sent (the clock, the leader's
    head then), and its signature with them. *)
let plan_cluster c ~(opts : opts) : (string, string) result =
  let* (eps, head, plan, artifacts, _, _) = cluster_plan c ~opts in
  let b = Buffer.create 4096 in
  Buffer.add_string b (Deploy_plan.render plan);
  let segs = segments plan in
  Buffer.add_string b (render_segments c segs);
  if head.Cluster_deploy.leader = "" then Buffer.add_string b "  control plane: no candidate answered\n"
  else Printf.bprintf b "  control plane: leader %s, head release %d (%s)\n" head.leader head.head_seq head.state;
  let* _ =
    List.fold_left (fun acc seg ->
        let* (head, n) = acc in
        match seg with
        | Process _ -> Ok (head, n)
        | Release { pools; topology } ->
          let* sp = release_spec c ~opts ~eps ~artifacts ~n pools ~topology in
          let r = Cluster_deploy.build_release sp ~head in
          remove_scratch n;
          let* r = r in
          let text = Control_release.serialize r in
          let file = Filename.concat (work_dir c) (Printf.sprintf "release-%d.txt" n) in
          Reconcile.mkdir_p (work_dir c);
          Out_channel.with_open_bin file (fun oc -> output_string oc text);
          Printf.bprintf b "\n7.%d The release it would sign (%s)\n%s" n file text;
          Ok ({ head with Cluster_deploy.head_seq = r.Control_release.seq; head_digest = Control_release.digest r }, n + 1))
      (Ok (head, 1)) segs
  in
  Ok (Buffer.contents b)

(** [forge deploy --env <env>] on the cluster backend: plan, confirm, then
    each segment in order (a release sent and followed to its end; a restart
    over ssh), then record. A halted release stops the deploy with the
    leader's reason; nothing is rolled back. *)
let run_cluster c ~(opts : opts) : (string, string) result =
  let* (eps, _, plan, artifacts, derived, pflags) = cluster_plan c ~opts in
  print_string (Deploy_plan.render plan);
  let segs = segments plan in
  print_string (render_segments c segs);
  if Deploy_plan.blocked plan then
    Error "the deploy is blocked (see \"2. Mechanism and why\"); nothing was changed"
  else if segs = [] then Ok "nothing to deploy"
  else if not (opts.yes || opts.confirm (Printf.sprintf "\ndeploy to %s? [y/N] " (Reconcile.env_key c.env))) then
    Error "not deployed"
  else begin
    let restarted = ref [] in
    let total = List.length segs in
    let rec run_segs i = function
      | [] -> Ok ()
      | seg :: rest ->
        let r =
          match seg with
          | Process (pp, why) ->
            Printf.printf "\n==> %d of %d: pool %s over ssh (restart-class steps go through the process backend)\n%!" i total pp.pp_pool;
            restart_pool c ~opts ~plan ~pflags ~artifacts ~derived ~restarted ~why pp
          | Release { pools; topology } ->
            Printf.printf "\n==> %d of %d: a release through the control plane\n%!" i total;
            let* sp = release_spec c ~opts ~eps ~artifacts ~n:i pools ~topology in
            Fun.protect ~finally:(fun () -> remove_scratch i) (fun () ->
                let* (_, release) = Cluster_deploy.prepare sp in
                List.iter (fun st -> Printf.printf "  %s\n%!" (Control_release.show_step st)) release.Control_release.steps;
                let* () = Cluster_deploy.upload_artifacts sp release in
                let* report = Cluster_deploy.send_and_follow sp release in
                print_string report;
                Ok ())
        in
        match r with
        | Ok () -> run_segs (i + 1) rest
        | Error m ->
          Error (Printf.sprintf "%s\n(%d of %d; %s)" m i total
                   (if rest = [] then "this was the last part" else "the later parts were not started"))
    in
    let* () = run_segs 1 segs in
    let expanding = List.filter_map (fun (sp : Deploy_plan.split) ->
        if sp.sp_phase = `Expand then Some sp.sp_protocol else None) plan.splits in
    record c ~artifacts ~restarted:!restarted ~derived ~expanding;
    write_pending c (Deploy_plan.pending_after plan.splits);
    if expanding <> [] then
      Ok (Printf.sprintf "deploy one of two (the expand of %s) is done (D21). Every node runs it now; run \
                          `forge deploy%s` again for deploy two (the contract)."
            (String.concat ", " expanding) (env_flag c.env))
    else Ok "deploy complete"
  end

(** [forge deploy --plan]: print the plan; change nothing. *)
let plan_only ?transport ?service_ctl ?layout_prefix ?(via = `Auto) ?(opts = default_opts) ~proj ~env ~grant_caps ~compact ()
  : (string, string) result =
  let* c = setup ?transport ?service_ctl ?layout_prefix ~proj ~env () in
  let opts = { opts with grant_caps; compact } in
  let* backend = choose_backend ~via c.t in
  match backend with
  | `Cluster -> plan_cluster c ~opts
  | `Ssh ->
    let* (plan, _, _, _) = make_plan c ~grant_caps ~compact in
    Ok (Deploy_plan.render plan)

(** [forge deploy --env <env>]: plan, confirm, carry out, record. *)
let run ?transport ?service_ctl ?layout_prefix ?(via = `Auto) ~proj ~env ~(opts : opts) () : (string, string) result =
  let* c = setup ?transport ?service_ctl ?layout_prefix ~proj ~env () in
  let* backend = choose_backend ~via c.t in
  match backend with
  | `Cluster -> run_cluster c ~opts
  | `Ssh -> run_ssh c ~opts

(** The control plane's endpoints for [env], without the ssh setup (no key,
    no host records): what [--status] and [--audit] need. *)
let endpoints_for ~(proj : Project.project) ~env : (Cluster_deploy.endpoint list, string) result =
  let root = proj.Project.root in
  if not (Topology.exists ~root) then Error "the control plane belongs to a topology app (topology.toml)"
  else
    let env = Reconcile.existing_overlay ~root env in
    let* t = Reconcile.load_checked ~root env in
    control_endpoints t

(** [forge deploy --status]: the leader's view of the newest release. *)
let status_text ~proj ~env : (string, string) result =
  let* eps = endpoints_for ~proj ~env in
  let* s = Cluster_deploy.status eps in
  Ok (Cluster_deploy.render_status s)

(** [forge deploy --audit]: the leader's audit log, from every candidate. *)
let audit_text ~proj ~env ~n : (string, string) result =
  let* eps = endpoints_for ~proj ~env in
  let* lines = Cluster_deploy.audit ~n eps in
  Ok (if lines = [] then "the audit log is empty\n" else String.concat "" (List.map (fun l -> l ^ "\n") lines))
