(** [forge host init --env <env>]: prepare each host of an ssh topology
    once (distributed-deploys plan, section 5 "Host setup"; build step 10b).

    For every host of every pool in the overlay, one shell script over ssh
    ([Remote.transport]) converges the host on the layout [Host_layout]
    describes:

    - the [march] system user and the directories: code
      ([/opt/march/<project>]), the service's HOME
      ([/var/lib/march/<project>], whose [.march/cas] is the CAS root and
      holds the persisted patch stack), run state, configuration;
    - the systemd unit, from the step-7 template ([Topology.Gen.systemd_unit])
      with this host's [Environment=]: node name, labels, cluster port and
      advertised address, seeds (every other node), the reload socket, the
      status file, the topology file, [MARCH_DEPLOY_POLICY], HOME, and in
      certificate mode the certificate files;
    - the deploy public key ([deploy.pub]; the binary embeds its own copy);
    - cluster authentication: with an operator key (step 11a,
      [forge cluster keygen]; [--operator-key], else
      [.forge/cluster/operator.key]) a node certificate per node, issued
      here and reused while it has more than 30 days left, plus the
      operator public key; without one, a cluster secret generated once per
      environment ([.forge/hosts/<env>/cluster.secret]) in the pool's env
      file (0640, root:march);
    - the node's capability policy ([<pool>.policy], MARCH_DEPLOY_POLICY):
      the pool's written [caps], else the compiler's derived ones (the
      export's); none when neither is known (the gate is then permissive,
      and forge says so);
    - the firewall: the pool's [ufw] rules from the connectivity graph
      ([Topology.Gen.ufw]), applied when [ufw] is installed (ssh stays
      open), else written and reported; the [do-firewall] JSON is written
      locally ([.forge/hosts/<env>/do-firewalls.json]) for [doctl];
    - the digest ([topology.json]) the node starts with.

    Every step is idempotent: a file whose content is unchanged is left
    alone ([ok <path>]), a changed one is replaced atomically
    ([changed <path>]); the user, directories, [daemon-reload] and
    [enable] run only when needed. A second run reports no change.

    The script also answers [uname -sm]; forge records each host's target
    ([linux/amd64], [linux/arm64]) and triple in [.forge/hosts/<env>.json]
    ([Reconcile.write_host_records]): [forge deploy] builds for it and
    refuses a patch built for another target before it leaves this machine
    (#606's identity). *)

let ( let* ) = Result.bind

type opts = {
  env          : string option;
  operator_key : string option;  (** None: [.forge/cluster/operator.key] when it exists *)
  trust_domain : string;
  firewall     : bool;           (** apply ufw rules when ufw is installed *)
  cert_days    : int;
}

let default_opts env = { env; operator_key = None; trust_domain = "cluster.local"; firewall = true; cert_days = 90 }

let local_dir ~root env = Filename.concat (Filename.concat (Filename.concat root ".forge") "hosts") (Reconcile.env_key env)

let triple_of_canonical = function
  | "linux/amd64" -> Some "x86_64-unknown-linux-gnu"
  | "linux/arm64" -> Some "aarch64-unknown-linux-gnu"
  | _ -> None

let read_file path = In_channel.with_open_bin path In_channel.input_all

let write_private path content =
  Reconcile.mkdir_p (Filename.dirname path);
  Out_channel.with_open_gen [ Open_wronly; Open_creat; Open_trunc; Open_binary ] 0o600 path
    (fun oc -> output_string oc content)

let random_hex n =
  let ic = open_in_bin "/dev/urandom" in
  let s = Fun.protect ~finally:(fun () -> close_in ic) (fun () -> really_input_string ic n) in
  String.concat "" (List.init n (fun i -> Printf.sprintf "%02x" (Char.code s.[i])))

(* ── Cluster authentication ───────────────────────────────────────────── *)

(** The environment's cluster secret, generated once. *)
let cluster_secret ~root env =
  let path = Filename.concat (local_dir ~root env) "cluster.secret" in
  if Sys.file_exists path then String.trim (read_file path)
  else begin
    let s = random_hex 32 in
    write_private path (s ^ "\n");
    s
  end

type auth =
  | Secret of string
  | Certs of { op_key : string; op_pub_hex : string }

let find_operator_key ~root (opts : opts) : string option =
  match opts.operator_key with
  | Some k -> Some k
  | None ->
    let p = Filename.concat (Filename.concat (Filename.concat root ".forge") "cluster") "operator.key" in
    if Sys.file_exists p then Some p else None

let auth_of ~root (opts : opts) : (auth, string) result =
  match find_operator_key ~root opts with
  | None -> Ok (Secret (cluster_secret ~root opts.env))
  | Some op_key ->
    let* sk = Cmd_cluster.load_secret_key op_key in
    Ok (Certs { op_key; op_pub_hex = Cmd_cluster.to_hex (Cmd_cluster.pubkey_of sk) })

(** A node's certificate and key (text), issued with [forge cluster cert]'s
    code into [.forge/hosts/<env>/certs/]; reused while it has more than
    30 days left and names the same roles, so a second init changes
    nothing. *)
let node_cert ~root ~(opts : opts) ~op_key ~pool ~roles node : (string * string, string) result =
  let dir = Filename.concat (local_dir ~root opts.env) "certs" in
  Reconcile.mkdir_p dir;
  let cert = Filename.concat dir (node ^ ".cert") and key = Filename.concat dir (node ^ ".key") in
  let meta = Filename.concat dir (node ^ ".meta") in
  let roles_csv = String.concat "," roles in
  let fresh () =
    Sys.file_exists cert && Sys.file_exists key && Sys.file_exists meta
    && (match String.split_on_char '\n' (read_file meta) with
        | na :: rs :: _ ->
          (match int_of_string_opt na with
           | Some not_after -> float_of_int not_after > Unix.time () +. 30. *. 86400. && rs = roles_csv
           | None -> false)
        | _ -> false)
  in
  let* () =
    if fresh () then Ok ()
    else begin
      let* msg =
        Cmd_cluster.run_cert ~name:node ~roles:roles_csv ~flags:"" ~days:opts.cert_days ~seconds:None
          ~trust_domain:opts.trust_domain ~pool ~operator_key:op_key
          ~node_key:(if Sys.file_exists key then Some key else None) ~out_dir:dir ()
      in
      let not_after =
        List.find_map (fun l ->
            match String.split_on_char ' ' l with
            | "not_after" :: n :: _ -> Some n
            | _ -> None)
          (String.split_on_char '\n' msg)
      in
      write_private meta (Option.value ~default:"0" not_after ^ "\n" ^ roles_csv ^ "\n");
      Ok ()
    end
  in
  Ok (String.trim (read_file cert), String.trim (read_file key))

(* ── What each host should look like ──────────────────────────────────── *)

type file = { f_path : string; f_mode : int; f_owner : string; f_content : string; f_on_change : string }

type host_plan = {
  hp_node     : Reconcile.ssh_node;
  hp_dirs     : (string * int * string) list;   (** path, mode, owner *)
  hp_files    : file list;
  hp_unit     : string;                         (** the unit's path *)
  hp_firewall : string option;                  (** the ufw script's path, when rules were generated *)
  hp_notes    : string list;                    (** said locally, before the host runs anything *)
}

let advertise (n : Reconcile.ssh_node) = Printf.sprintf "%s:%d" (Hosts.host_name n.sn.Hosts.ssh) n.sn_port

(** The unit's [Environment=] for one node (secrets excluded: they go in
    the env file). *)
let node_environment ~(layout : Host_layout.t) ~project ~(policy : bool) ~(auth : auth)
    ~(all : Reconcile.ssh_node list) (n : Reconcile.ssh_node) : (string * string) list =
  let pool = n.sn_pool in
  let unrelocated = Host_layout.make project in
  (* The unit names the paths as the host sees them, whatever the prefix a
     test relocates the files under. *)
  ignore layout;
  let l = unrelocated in
  [ ("MARCH_POOLS", pool);
    ("MARCH_NODE_NAME", n.sn.Hosts.name);
    ("MARCH_NODE_PORT", string_of_int n.sn_port);
    ("MARCH_NODE_ADVERTISE", advertise n);
    ("MARCH_CLUSTER_NODES",
     String.concat "," (List.filter_map (fun (m : Reconcile.ssh_node) ->
         if m.sn.Hosts.name = n.sn.Hosts.name then None else Some (advertise m)) all));
    ("MARCH_NODE_LABELS", String.concat "," n.sn.Hosts.labels);
    ("MARCH_TOPOLOGY_FILE", Host_layout.topology_file l);
    ("MARCH_TOPOLOGY_STATUS", Host_layout.status_file l pool);
    ("MARCH_HOT_RELOAD_SOCKET", Host_layout.socket l pool);
    ("HOME", Host_layout.state_dir l) ]
  @ (if policy then [ ("MARCH_DEPLOY_POLICY", Host_layout.policy_file l pool) ] else [])
  @ (match auth with
      | Secret _ -> []
      | Certs _ ->
        [ ("MARCH_NODE_CERT", Host_layout.cert_file l n.sn.Hosts.name);
          ("MARCH_NODE_KEY", Host_layout.key_file l n.sn.Hosts.name);
          ("MARCH_CLUSTER_OPERATOR_PUBKEY", Host_layout.operator_pub l) ])

(** The policy lines for a pool: its written [caps], else [derived]. *)
let pool_policy ~(derived : (string * (string list * string list)) list option) (p : Topology.pool)
  : string list option =
  match p.caps with
  | Some cs -> Some (List.sort_uniq String.compare cs)
  | None ->
    Option.map (fun (caps, _) -> List.sort_uniq String.compare caps)
      (Option.bind derived (List.assoc_opt p.pool_name))

(** The caps a pool's role closures reach only through the stdlib's
    topology runner: the generated code wraps each role body in
    [Topology.hook] (the hook watchdog), whose clock, spawn, process and
    vault authority is charged to every role closure (the manifest's [ROLE]
    lines, [via=] chains [body>Topology.hook>...]). The user did not write
    them in the pool's [caps] and cannot remove them, so a node policy of
    the written caps alone would refuse every hot patch of the pool
    ([ERR role_cap_policy]). A cap the user's own code reaches is not a
    runner cap: it still has to be in the pool's caps. *)
let runner_caps (m : Cmd_deploy_hot.manifest) (p : Topology.pool) : string list =
  let is_runner frame = String.length frame >= 9 && String.sub frame 0 9 = "Topology." in
  List.concat_map (fun (r : Cmd_deploy_hot.role_manifest) ->
      if not (List.mem r.role_name p.serves) then []
      else
        List.filter_map (fun (cap, chain) ->
            match chain with
            | _body :: frame :: _ when is_runner frame -> Some cap
            | _ -> None)
          r.role_chains)
    m.roles
  |> List.sort_uniq String.compare

(** The policy file's text for a pool: its caps ([pool_policy]) plus, when
    the manifest being installed is known, its runner's ([runner_caps]).
    None: no policy (the pool's caps are unknown). *)
let policy_text ~derived ?manifest (p : Topology.pool) : string option =
  Option.map (fun caps ->
      let runner = match manifest with Some m -> runner_caps m p | None -> [] in
      String.concat "" (List.map (fun c -> c ^ "\n") (List.sort_uniq String.compare (caps @ runner))))
    (pool_policy ~derived p)

(** Everything [forge host init] wants on each host. Pure apart from the
    credentials ([auth], certificates issued into [.forge/hosts/]). *)
let plan ~root ~(opts : opts) ~(proj : Project.project) ~(layout : Host_layout.t) ~(t : Topology.t)
    ~(index : Topology.index) ~(derived : (string * (string list * string list)) list option)
    ~(auth : auth) ~pubkey (nodes : Reconcile.ssh_node list) : (host_plan list, string) result =
  let project = proj.Project.name in
  let relocated = layout.Host_layout.prefix <> "" in
  let own o = if relocated then "" else o in
  let ex =
    Topology.export_of_json (Topology.export_json ?compiler:derived ~index t)
  in
  let ufw_files = match ex with Ok ex -> Topology.Gen.ufw ex | Error _ -> [] in
  let digest = Topology.digest_text t in
  List.fold_left (fun acc (n : Reconcile.ssh_node) ->
      let* acc = acc in
      let pool = n.sn_pool in
      let p = List.find (fun (p : Topology.pool) -> p.pool_name = pool) t.pools in
      (* The runner's caps come from the manifest last deployed to this
         environment, when there is one, so host init and forge deploy
         write the same policy. *)
      let deployed =
        Result.to_option (Cmd_deploy_hot.parse_manifest
                            (Reconcile.deployed_manifest_file ~root opts.env (Reconcile.build_of_pool t pool))) in
      let policy = policy_text ~derived ?manifest:deployed p in
      let notes =
        if policy = None then
          [ Printf.sprintf "pool %s has no written caps and the compiler could not derive them: no capability \
                            policy is installed (the node's admission gate is permissive)" pool ]
        else []
      in
      let env = node_environment ~layout ~project ~policy:(policy <> None) ~auth ~all:nodes n in
      let unit_text =
        Topology.Gen.systemd_unit ~generator:"forge host init" ~project ~topo:t ~environment:env p in
      let* cert_files =
        match auth with
        | Secret _ -> Ok []
        | Certs { op_key; op_pub_hex } ->
          let roles =
            List.map (fun r -> r ^ ":offer") p.serves
            @ List.map (fun r -> r ^ ":initiate") (Topology.pool_initiates index t p)
          in
          let* (cert, key) = node_cert ~root ~opts ~op_key ~pool ~roles n.sn.Hosts.name in
          Ok [ { f_path = Host_layout.cert_file layout n.sn.Hosts.name; f_mode = 0o640; f_owner = own "root:march";
                 f_content = cert ^ "\n"; f_on_change = "RESTART_NEEDED=1" };
               { f_path = Host_layout.key_file layout n.sn.Hosts.name; f_mode = 0o640; f_owner = own "root:march";
                 f_content = key ^ "\n"; f_on_change = "RESTART_NEEDED=1" };
               { f_path = Host_layout.operator_pub layout; f_mode = 0o644; f_owner = "";
                 f_content = op_pub_hex ^ "\n"; f_on_change = "RESTART_NEEDED=1" } ]
      in
      let env_file =
        match auth with
        | Secret s -> Printf.sprintf "MARCH_CLUSTER_SECRET=%s\n" s
        | Certs _ -> "# certificate mode: the credentials are MARCH_NODE_CERT/MARCH_NODE_KEY (see the unit)\n"
      in
      let hostname = Hosts.host_name n.sn.Hosts.ssh in
      let firewall =
        List.assoc_opt (Printf.sprintf "ufw-%s.sh" hostname) ufw_files
      in
      let files =
        [ { f_path = Host_layout.unit_file layout pool; f_mode = 0o644; f_owner = ""; f_content = unit_text;
            f_on_change = "UNIT_CHANGED=1" };
          { f_path = Host_layout.env_file layout pool; f_mode = 0o640; f_owner = own "root:march";
            f_content = env_file; f_on_change = "RESTART_NEEDED=1" };
          { f_path = Host_layout.deploy_pub layout; f_mode = 0o644; f_owner = ""; f_content = pubkey ^ "\n";
            f_on_change = "" };
          { f_path = Host_layout.topology_file layout; f_mode = 0o644; f_owner = ""; f_content = digest;
            f_on_change = "" } ]
        @ (match policy with
            | Some text ->
              [ { f_path = Host_layout.policy_file layout pool; f_mode = 0o644; f_owner = "";
                  f_content = text; f_on_change = "RESTART_NEEDED=1" } ]
            | None -> [])
        @ cert_files
        @ (match firewall with
            | Some text ->
              [ { f_path = Host_layout.firewall_file layout pool; f_mode = 0o755; f_owner = ""; f_content = text;
                  f_on_change = "FIREWALL_CHANGED=1" } ]
            | None -> [])
      in
      let dirs =
        [ (Host_layout.code_dir layout, 0o755, own "root:root");
          (Host_layout.state_dir layout, 0o750, own "march:march");
          (Host_layout.run_dir layout, 0o750, own "march:march");
          (Host_layout.etc_dir layout, 0o750, own "root:march");
          (Filename.dirname (Host_layout.unit_file layout pool), 0o755, "") ]
        @ (match auth with Certs _ -> [ (Host_layout.cert_dir layout, 0o750, own "root:march") ] | Secret _ -> [])
      in
      Ok (acc @ [ { hp_node = n; hp_dirs = dirs; hp_files = files; hp_unit = Host_layout.unit_file layout pool;
                    hp_firewall = Option.map (fun _ -> Host_layout.firewall_file layout pool) firewall;
                    hp_notes = notes } ]))
    (Ok []) nodes

(** The script that converges one host. [service_ctl] is [systemctl]; the
    enable step runs only where systemd is PID 1 ([/run/systemd/system]). *)
let script ~(layout : Host_layout.t) ~service_ctl ~(opts : opts) (hp : host_plan) : string =
  let relocated = layout.Host_layout.prefix <> "" in
  let b = Buffer.create 8192 in
  let add s = Buffer.add_string b s in
  let line s = add s; add "\n" in
  add (Reconcile.sudo_prelude layout);
  line "UNIT_CHANGED=; RESTART_NEEDED=; FIREWALL_CHANGED=";
  line "echo \"UNAME $(uname -sm)\"";
  if relocated then line "echo 'skip user march (relocated layout)'"
  else begin
    line "if id march >/dev/null 2>&1; then echo 'ok user march'";
    line (Printf.sprintf
            "elif command -v useradd >/dev/null 2>&1; then $SUDO useradd --system --home-dir %s --no-create-home \
             --shell /usr/sbin/nologin march && echo 'changed user march'"
            "/var/lib/march");
    line (Printf.sprintf
            "elif command -v adduser >/dev/null 2>&1; then $SUDO addgroup -S march 2>/dev/null || true; \
             $SUDO adduser -S -D -H -h %s -s /sbin/nologin -G march march && echo 'changed user march'"
            "/var/lib/march");
    line "else echo 'error: neither useradd nor adduser on this host' >&2; exit 1; fi"
  end;
  line "mkd() {";
  line "  if [ -d \"$1\" ]; then echo \"ok $1\"; else $SUDO mkdir -p \"$1\" && echo \"changed $1\"; fi";
  line "  $SUDO chmod \"$2\" \"$1\"";
  line "  if [ -n \"$3\" ]; then $SUDO chown \"$3\" \"$1\"; fi";
  line "}";
  List.iter (fun (d, mode, owner) ->
      line (Printf.sprintf "mkd %s %o %s" (Remote.sh_quote d) mode (Remote.sh_quote owner)))
    hp.hp_dirs;
  List.iter (fun f ->
      add (Reconcile.put_file_script ~path:f.f_path ~mode:f.f_mode ~owner:f.f_owner ~on_change:f.f_on_change f.f_content))
    hp.hp_files;
  let unit = Host_layout.unit_name hp.hp_node.sn_pool in
  (* A relocated layout (a test's scratch directory) never touches the
     machine's own service manager, even where systemd runs. *)
  line (Printf.sprintf "if %s command -v %s >/dev/null 2>&1 && [ -d /run/systemd/system ]; then"
          (if relocated then "false &&" else "") service_ctl);
  line (Printf.sprintf "  if [ -n \"$UNIT_CHANGED\" ]; then $SUDO %s daemon-reload && echo 'changed systemd daemon-reload'; fi" service_ctl);
  line (Printf.sprintf "  if %s is-enabled --quiet %s 2>/dev/null; then echo 'ok enabled %s'; \
                         else $SUDO %s enable %s >/dev/null 2>&1 && echo 'changed enabled %s'; fi"
          service_ctl unit unit service_ctl unit unit);
  line "else";
  line (if relocated then Printf.sprintf "  echo 'note relocated layout: %s was written, not enabled'" unit
        else Printf.sprintf "  echo 'note systemd is not running here: %s was written, not enabled'" unit);
  line "fi";
  line "if [ -n \"$UNIT_CHANGED$RESTART_NEEDED\" ]; then echo 'note the unit or its credentials changed: \
        the next `forge deploy` restarts it'; fi";
  (match hp.hp_firewall with
   | None -> line "echo 'note no firewall rules for this host (it is in no pool the connectivity graph names)'"
   | Some fw ->
     if opts.firewall && not relocated then begin
       line "if command -v ufw >/dev/null 2>&1; then";
       line (Printf.sprintf "  if [ -n \"$FIREWALL_CHANGED\" ] || ! $SUDO ufw status | grep -q '^Status: active'; then \
                             $SUDO sh %s >/dev/null && echo 'changed firewall (ufw)'; else echo 'ok firewall (ufw)'; fi"
               (Remote.sh_quote fw));
       line "else";
       line (Printf.sprintf "  echo 'note ufw is not installed: the rules are in %s, not applied'" fw);
       line "fi"
     end else
       line (Printf.sprintf "echo 'note firewall not applied (--no-firewall or relocated): the rules are in %s'" fw));
  Buffer.contents b

type host_result = {
  res_node    : Reconcile.ssh_node;
  res_changed : string list;
  res_ok      : int;
  res_notes   : string list;
  res_uname   : string;
}

let parse_output (n : Reconcile.ssh_node) (out : string) : host_result =
  let lines = List.filter (fun l -> l <> "") (List.map String.trim (String.split_on_char '\n' out)) in
  let after p l =
    let k = String.length p in
    if String.length l > k && String.sub l 0 k = p then Some (String.sub l k (String.length l - k)) else None
  in
  { res_node = n;
    res_changed = List.filter_map (after "changed ") lines;
    res_ok = List.length (List.filter_map (after "ok ") lines);
    res_notes = List.filter_map (after "note ") lines;
    res_uname = Option.value ~default:"" (List.find_map (after "UNAME ") lines) }

(** Run [forge host init] for the project: every host of the overlay, each
    reported; records the targets. [Ok report] when every host converged. *)
let run ?(transport = Remote.ssh) ?(service_ctl = "systemctl") ?(layout_prefix = "")
    ?(derived : (string * (string list * string list)) list option) ~(proj : Project.project) ~(opts : opts) ()
  : (string, string) result =
  let root = proj.Project.root in
  let env = Reconcile.existing_overlay ~root opts.env in
  let* t = Reconcile.load_checked ~root env in
  let* () =
    if Reconcile.is_ssh t then Ok ()
    else Error (Printf.sprintf "the topology%s does not say `[backend] kind = \"ssh\"`: `forge host init` prepares ssh hosts"
                  (match env with Some e -> Printf.sprintf " (with topology.%s.toml)" e | None -> ""))
  in
  let* sk = Cmd_hot_reload.read_sk_raw () in
  let pubkey = Reconcile.deploy_pubkey ~proj sk in
  let* records = Reconcile.read_host_records ~root env in
  let layout = Host_layout.make ~prefix:layout_prefix proj.Project.name in
  let* nodes = Reconcile.ssh_nodes ~layout ~pubkey ~records t in
  let index = Topology.index_project ~root in
  ignore (Topology.write_digest ~root t);
  let derived =
    match derived with
    | Some d -> Some d
    | None ->
      if List.for_all (fun (p : Topology.pool) -> p.caps <> None) t.pools then None
      else
        match Topology_run.compiler_derived proj with
        | Ok d -> Some d
        | Error m ->
          Printf.eprintf "warning: derived caps unavailable: %s\n%!" m;
          None
  in
  let* auth = auth_of ~root { opts with env } in
  let* plans = plan ~root ~opts:{ opts with env } ~proj ~layout ~t ~index ~derived ~auth ~pubkey nodes in
  (match Topology.export_of_json (Topology.export_json ?compiler:derived ~index t) with
   | Ok ex ->
     let dir = local_dir ~root env in
     Reconcile.mkdir_p dir;
     List.iter (fun (name, content) ->
         Out_channel.with_open_bin (Filename.concat dir name) (fun oc -> output_string oc content))
       (Topology.Gen.do_firewall ex)
   | Error _ -> ());
  let buf = Buffer.create 2048 in
  let say fmt = Printf.bprintf buf fmt in
  say "forge host init: %d host(s), %s mode\n" (List.length plans)
    (match auth with Secret _ -> "shared-secret" | Certs _ -> "certificate");
  let results =
    Hosts.run_on ~strategy:`All (List.map (fun hp -> hp.hp_node.sn) plans) (fun h ->
        let hp = List.find (fun hp -> hp.hp_node.sn.Hosts.name = h.Hosts.name) plans in
        List.iter (fun m -> say "%s: note: %s\n" h.Hosts.name m) hp.hp_notes;
        let r = transport.Remote.exec h (script ~layout ~service_ctl ~opts hp) in
        if r.Remote.rc <> 0 then
          Error (Printf.sprintf "exit %d: %s" r.rc (String.trim (r.err ^ "\n" ^ r.out)))
        else Ok (parse_output hp.hp_node r.out))
  in
  let failed = ref [] in
  let new_records =
    List.filter_map (fun ((h : Hosts.host), r) ->
        match r with
        | Error m -> failed := h.Hosts.name :: !failed; say "%s (%s): FAILED: %s\n" h.Hosts.name h.Hosts.ssh m; None
        | Ok res ->
          let target = Cmd_deploy_hot.canonical_of_triple res.res_uname in
          say "%s (%s, pool %s): %s, %d unchanged; target %s\n" h.Hosts.name h.Hosts.ssh res.res_node.sn_pool
            (match res.res_changed with
             | [] -> "no change"
             | cs -> Printf.sprintf "%d changed (%s)" (List.length cs) (String.concat ", " cs))
            res.res_ok (Option.value ~default:("unknown: " ^ res.res_uname) target);
          List.iter (fun n -> say "  note: %s\n" n) res.res_notes;
          Some { Reconcile.hr_host = h.Hosts.ssh; hr_pool = res.res_node.sn_pool; hr_node = h.Hosts.name;
                 hr_target = Option.value ~default:"unknown" target;
                 hr_triple = Option.value ~default:"" (Option.bind target triple_of_canonical);
                 hr_uname = res.res_uname; hr_at = Unix.gettimeofday () })
      results
  in
  let kept = List.filter (fun (r : Reconcile.host_record) ->
      not (List.exists (fun (n : Reconcile.host_record) -> n.hr_host = r.hr_host && n.hr_pool = r.hr_pool) new_records))
      records in
  Reconcile.write_host_records ~root env (kept @ new_records);
  say "recorded in %s\n" (Reconcile.hosts_file ~root env);
  if !failed = [] then Ok (Buffer.contents buf)
  else Error (Buffer.contents buf ^ Printf.sprintf "%d host(s) failed: %s" (List.length !failed) (String.concat ", " (List.rev !failed)))
