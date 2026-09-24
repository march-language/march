(** The reconciler (distributed-deploys plan, build step 8: section 5,
    II.6 "The reconciler"; D16).

    At small scale the reconciler is forge itself: each [forge topology
    apply] (or [forge topology status]) is one reconciliation pass over a
    backend, with no daemon. A backend is four operations:

    - [hosts]: the nodes it runs, as [Hosts.host]s;
    - [run_on]: run a step on some of them, by the rolling or all-hosts
      drivers of [Hosts.run_on];
    - [push_topology]: make a new topology the nodes' desired state. The
      reconciler never opens or closes an offer itself (D16): every node
      re-reads the topology and decides its own offers
      ([stdlib/topology.march], [Topology.reload]);
    - [status]: what each node reports: alive, the topology it applied, the
      offers it holds, and, for a hot-reload build, its reload server's
      [VERSIONS_DETAIL] and [PINS].

    The [local] backend (this file) runs on the processes a
    [forge run --processes] started ([Procs]). That command records them in
    [.forge/run/state.json] (pids, cluster ports, reload sockets, node names,
    labels, and the file each node reports its status to), so a later forge
    invocation in the same project finds them. [push_topology] re-digests the
    TOML into [.forge/topology.json] (the file every node was started with,
    [MARCH_TOPOLOGY_FILE]) and sends SIGHUP to every node, which re-reads it.

    {1 Single writer}

    GitOps removes the need for a consensus store, not for a single writer
    (section 5): a pass holds [.forge/run/reconcile.lock] ([with_lock]), an
    exclusive, non-blocking lock ([Unix.lockf], a POSIX record lock: the
    closest thing OCaml's Unix exposes to flock(2), and like it released by
    the kernel when the holder dies). A second forge reports who holds it
    and stops instead of issuing conflicting actions. The ssh backend (step
    10) will use a lease on the cluster for the same purpose.

    {1 Node status files}

    A node writes [MARCH_TOPOLOGY_STATUS] (set by forge to
    [.forge/run/<node>.status]) whenever what it reports changes: one
    [key value] pair per line,

    {v
    node back-1
    topology 5d41402abc4b2a76b9719d911017c592...   (sha256 of the digest it applied; "compiled" before any reload)
    offers Echo.Server,Count.Counter
    draining 0
    running 2
    v}

    A node that has not written the file yet (starting, or built before
    topology reload existed) is never sent SIGHUP: without a watcher the
    signal's default action would kill it. *)

let ( let* ) = Result.bind

(* ── Paths ─────────────────────────────────────────────────────────────── *)

let run_dir ~root = Filename.concat (Filename.concat root ".forge") "run"
let state_file ~root = Filename.concat (run_dir ~root) "state.json"
let lock_file ~root = Filename.concat (run_dir ~root) "reconcile.lock"
let status_file ~root name = Filename.concat (run_dir ~root) (name ^ ".status")

let rec mkdir_p d =
  if not (Sys.file_exists d) then begin
    mkdir_p (Filename.dirname d);
    try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

(** A reload socket for node [name]. A Unix socket path is limited to about
    104 bytes (sun_path), which a project under a deep temporary directory
    can exceed, so a long one moves to a short directory under /tmp keyed by
    the project root. *)
let socket_path ~root name =
  let p = Filename.concat (run_dir ~root) (name ^ ".sock") in
  if String.length p <= 100 then p
  else begin
    let key = String.sub (Digest.to_hex (Digest.string root)) 0 12 in
    let d = Filename.concat "/tmp" ("march-forge-" ^ key) in
    mkdir_p d;
    Filename.concat d (name ^ ".sock")
  end

let sha256_file path =
  match In_channel.with_open_bin path In_channel.input_all with
  | s -> Some (Digestif.SHA256.to_hex (Digestif.SHA256.digest_string s))
  | exception Sys_error _ -> None

(** A pid is alive when signal 0 reaches it. Never judge by a kill's return
    value: a sandboxed kill can succeed and deliver nothing. *)
let alive pid =
  pid > 0 && (try Unix.kill pid 0; true with Unix.Unix_error (Unix.ESRCH, _, _) -> false
                                          | Unix.Unix_error (Unix.EPERM, _, _) -> true)

(* ── The run state: .forge/run/state.json ──────────────────────────────── *)

type node = {
  name        : string;          (** "back-1", MARCH_NODE_NAME *)
  pool        : string;
  pid         : int;
  port        : int;             (** cluster port *)
  socket      : string option;   (** reload socket, hot-reload builds only *)
  labels      : string list;
  status_path : string;          (** MARCH_TOPOLOGY_STATUS *)
  log         : string;
}

type state = {
  forge_pid  : int;              (** the [forge run --processes] that owns them *)
  env        : string option;    (** the overlay they were started with *)
  started_at : float;
  nodes      : node list;
}

let node_json n : Yojson.Safe.t =
  `Assoc [ ("name", `String n.name); ("pool", `String n.pool); ("pid", `Int n.pid);
           ("port", `Int n.port);
           ("socket", (match n.socket with Some s -> `String s | None -> `Null));
           ("labels", `List (List.map (fun l -> `String l) n.labels));
           ("status", `String n.status_path); ("log", `String n.log) ]

let state_json s : Yojson.Safe.t =
  `Assoc [ ("version", `Int 1); ("forge_pid", `Int s.forge_pid);
           ("env", (match s.env with Some e -> `String e | None -> `Null));
           ("started_at", `Float s.started_at);
           ("nodes", `List (List.map node_json s.nodes)) ]

let state_of_json (j : Yojson.Safe.t) : (state, string) result =
  let module U = Yojson.Safe.Util in
  try
    (match U.member "version" j with
     | `Int 1 -> ()
     | _ -> failwith "state.json: unknown version (expected 1)");
    let str_opt = function `String s -> Some s | _ -> None in
    let nodes =
      List.map (fun n ->
          { name = U.to_string (U.member "name" n); pool = U.to_string (U.member "pool" n);
            pid = U.to_int (U.member "pid" n); port = U.to_int (U.member "port" n);
            socket = str_opt (U.member "socket" n);
            labels = List.map U.to_string (U.to_list (U.member "labels" n));
            status_path = U.to_string (U.member "status" n); log = U.to_string (U.member "log" n) })
        (U.to_list (U.member "nodes" j))
    in
    Ok { forge_pid = U.to_int (U.member "forge_pid" j); env = str_opt (U.member "env" j);
         started_at = (match U.member "started_at" j with `Float f -> f | `Int n -> float_of_int n | _ -> 0.);
         nodes }
  with
  | Failure m -> Error m
  | U.Type_error (m, _) -> Error ("state.json: " ^ m)

(** Write atomically (temp file + rename): a concurrent reader sees the old
    state or the new, never half of one. *)
let write_state ~root s =
  mkdir_p (run_dir ~root);
  let path = state_file ~root in
  let tmp = path ^ ".tmp" in
  Out_channel.with_open_bin tmp (fun oc ->
      output_string oc (Yojson.Safe.pretty_to_string (state_json s));
      output_char oc '\n');
  Unix.rename tmp path

let remove_state ~root = try Sys.remove (state_file ~root) with Sys_error _ -> ()

(** The recorded run, if there is one. [Error] when the file is unreadable;
    [Ok None] when there is no run. A state whose forge and nodes are all
    gone is stale and reported as no run. *)
let read_state ~root : (state option, string) result =
  let path = state_file ~root in
  if not (Sys.file_exists path) then Ok None
  else
    match Yojson.Safe.from_file path with
    | exception Yojson.Json_error m -> Error (path ^ ": " ^ m)
    | exception Sys_error m -> Error m
    | j ->
      let* s = state_of_json j in
      if alive s.forge_pid || List.exists (fun n -> alive n.pid) s.nodes then Ok (Some s) else Ok None

(* ── Single writer ─────────────────────────────────────────────────────── *)

(** Run [f] holding the reconcile lock, or fail at once naming the holder. *)
let with_lock ~root (f : unit -> ('a, string) result) : ('a, string) result =
  mkdir_p (run_dir ~root);
  let path = lock_file ~root in
  let fd = Unix.openfile path [ Unix.O_RDWR; Unix.O_CREAT; Unix.O_CLOEXEC ] 0o644 in
  match Unix.lockf fd Unix.F_TLOCK 0 with
  | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EACCES), _, _) ->
    let holder =
      match In_channel.with_open_bin path In_channel.input_all with
      | s -> String.trim s
      | exception Sys_error _ -> ""
    in
    Unix.close fd;
    Error (Printf.sprintf "another forge is reconciling this project (%s holds %s); try again when it finishes"
             (if holder = "" then "a process" else "pid " ^ holder) path)
  | () ->
    Fun.protect
      ~finally:(fun () ->
          (try Unix.ftruncate fd 0 with Unix.Unix_error _ -> ());
          (try Unix.lockf fd Unix.F_ULOCK 0 with Unix.Unix_error _ -> ());
          Unix.close fd)
      (fun () ->
         Unix.ftruncate fd 0;
         let pid = string_of_int (Unix.getpid ()) ^ "\n" in
         ignore (Unix.write_substring fd pid 0 (String.length pid));
         f ())

(* ── What a node reports ───────────────────────────────────────────────── *)

type report = {
  r_topology : string;           (** sha256 of the applied digest, or "compiled" *)
  r_offers   : string list;
  r_draining : int;
  r_running  : int;
}

let parse_report (text : string) : report option =
  let kv =
    List.filter_map (fun line ->
        match String.index_opt line ' ' with
        | Some i -> Some (String.sub line 0 i, String.trim (String.sub line (i + 1) (String.length line - i - 1)))
        | None -> if String.trim line = "" then None else Some (String.trim line, ""))
      (String.split_on_char '\n' text)
  in
  match List.assoc_opt "topology" kv with
  | None -> None
  | Some topo ->
    let int k = Option.value ~default:0 (Option.bind (List.assoc_opt k kv) int_of_string_opt) in
    let offers =
      match List.assoc_opt "offers" kv with
      | None | Some "" -> []
      | Some s -> List.filter (fun x -> x <> "") (List.map String.trim (String.split_on_char ',' s))
    in
    Some { r_topology = topo; r_offers = offers; r_draining = int "draining"; r_running = int "running" }

let read_report path =
  match In_channel.with_open_bin path In_channel.input_all with
  | s -> parse_report s
  | exception Sys_error _ -> None

type reload_info = {
  versions : Cmd_deploy_hot.detail_slot list;
  pins     : string list;      (** the PINS answer: EPOCH ... and COUNTERS ... lines *)
}

type node_status = {
  node   : node;
  up     : bool;
  report : report option;      (** None: the node has not reported *)
  reload : (reload_info, string) result option;  (** None: not a hot-reload build *)
}

(** Ask a reload server for VERSIONS_DETAIL and PINS, with a timeout so a
    wedged node cannot hang the pass. *)
let query_reload ?(timeout = 3.0) socket : (reload_info, string) result =
  match Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 with
  | exception Unix.Unix_error (e, _, _) -> Error (Unix.error_message e)
  | fd ->
    Fun.protect ~finally:(fun () -> try Unix.close fd with Unix.Unix_error _ -> ())
      (fun () ->
         try
           Unix.setsockopt_float fd Unix.SO_RCVTIMEO timeout;
           Unix.setsockopt_float fd Unix.SO_SNDTIMEO timeout;
           Unix.connect fd (Unix.ADDR_UNIX socket);
           let conn = Cmd_deploy_hot.conn_of_fd fd in
           Cmd_deploy_hot.send_line conn "VERSIONS_DETAIL";
           let versions = Cmd_deploy_hot.parse_versions_detail conn in
           Cmd_deploy_hot.send_line conn "PINS";
           let pins = Cmd_deploy_hot.read_pins conn in
           Ok { versions; pins }
         with
         | Unix.Unix_error (e, _, _) -> Error (Unix.error_message e)
         | Failure m -> Error m)

(** The integer after [key:] in the PINS COUNTERS line, if present. *)
let pins_counter (pins : string list) (key : string) : int option =
  List.find_map (fun line ->
      if String.length line >= 9 && String.sub line 0 9 = "COUNTERS " then
        List.find_map (fun w ->
            match String.index_opt w ':' with
            | Some i when String.sub w 0 i = key -> int_of_string_opt (String.sub w (i + 1) (String.length w - i - 1))
            | _ -> None)
          (String.split_on_char ' ' line)
      else None)
    pins

(** The epochs PINS lists, each with its pin count and flags. *)
let pins_epochs (pins : string list) : (int * int * bool) list =
  List.filter_map (fun line ->
      match String.split_on_char ' ' line with
      | "EPOCH" :: e :: p :: rest ->
        (match int_of_string_opt e, String.index_opt p ':' with
         | Some e, Some i ->
           (match int_of_string_opt (String.sub p (i + 1) (String.length p - i - 1)) with
            | Some n -> Some (e, n, List.mem "current" rest)
            | None -> None)
         | _ -> None)
      | _ -> None)
    pins

let node_status (n : node) : node_status =
  let up = alive n.pid in
  { node = n; up;
    report = (if up then read_report n.status_path else None);
    reload = (match n.socket with
        | Some s when up -> Some (query_reload s)
        | _ -> None) }

(* ── The backend interface ─────────────────────────────────────────────── *)

(** What pushing a topology did on one node. *)
type push_outcome =
  | Signalled            (** sent SIGHUP; the node re-reads the topology *)
  | Not_running
  | Not_reporting        (** no status yet: not signalled (SIGHUP would kill it) *)

type push_result = {
  digest  : string;                      (** the digest file written *)
  sha     : string;                      (** its sha256, what nodes report once applied *)
  outcome : (string * push_outcome) list;
}

type backend = {
  kind : string;
  hosts : unit -> Hosts.host list;
  run_on : 'a. ?on_skip:(Hosts.host -> unit) -> strategy:Hosts.strategy ->
    Hosts.host list -> (Hosts.host -> ('a, string) result) -> (Hosts.host * ('a, string) result) list;
  push_topology : Topology.t -> (push_result, string) result;
  status : unit -> node_status list;
}

(** A local node as a [Hosts.host]: no ssh target; its reload socket when it
    has one. *)
let host_of_node (n : node) : Hosts.host =
  { Hosts.name = n.name; ssh = ""; socket = Option.value ~default:"" n.socket; pubkey = ""; labels = n.labels }

(** Write [t]'s digest and signal every node that reports. *)
let push_local ~root (st : state) (t : Topology.t) : (push_result, string) result =
  let digest = Topology.write_digest ~root t in
  match sha256_file digest with
  | None -> Error ("could not read back " ^ digest)
  | Some sha ->
    let outcome =
      List.map (fun n ->
          if not (alive n.pid) then (n.name, Not_running)
          else if read_report n.status_path = None then (n.name, Not_reporting)
          else begin
            (try Unix.kill n.pid Sys.sighup with Unix.Unix_error _ -> ());
            (n.name, Signalled)
          end)
        st.nodes
    in
    Ok { digest; sha; outcome }

(** The local backend over a recorded run. *)
let local ~root (st : state) : backend =
  { kind = "local";
    hosts = (fun () -> List.map host_of_node st.nodes);
    run_on = (fun ?on_skip ~strategy hosts step -> Hosts.run_on ?on_skip ~strategy hosts step);
    push_topology = push_local ~root st;
    status = (fun () -> List.map node_status st.nodes) }

(** The local backend for the project at [root]: the running
    [forge run --processes], or an error saying how to start one. *)
let local_backend ~root : (backend * state, string) result =
  let* st = read_state ~root in
  match st with
  | None ->
    Error "no local cluster is running for this project (start one with `forge run --processes`)"
  | Some st -> Ok (local ~root st, st)

(* ── Rendering ─────────────────────────────────────────────────────────── *)

let render_status (ss : node_status list) : string =
  let b = Buffer.create 512 in
  List.iter (fun s ->
      let n = s.node in
      Printf.bprintf b "%s (pool %s, pid %d, port %d)%s\n" n.name n.pool n.pid n.port
        (if s.up then "" else ": NOT RUNNING");
      if s.up then begin
        (match s.report with
         | None -> Buffer.add_string b "  has not reported its offers yet\n"
         | Some r ->
           Printf.bprintf b "  topology: %s\n"
             (if r.r_topology = "compiled" then "as built" else String.sub r.r_topology 0 (min 12 (String.length r.r_topology)));
           Printf.bprintf b "  offers: %s\n" (if r.r_offers = [] then "(none)" else String.concat ", " r.r_offers);
           if r.r_draining > 0 || r.r_running > 0 then
             Printf.bprintf b "  sessions running: %d; offers draining: %d\n" r.r_running r.r_draining);
        (match s.reload with
         | None -> ()
         | Some (Error m) -> Printf.bprintf b "  reload server: unreachable (%s)\n" m
         | Some (Ok ri) ->
           let patched = List.filter (fun d -> d.Cmd_deploy_hot.ds_activated_at <> 0L) ri.versions in
           Printf.bprintf b "  reload server: %d unit(s), %d hot-patched\n" (List.length ri.versions) (List.length patched);
           List.iter (fun l -> Printf.bprintf b "  %s\n" l) ri.pins)
      end)
    ss;
  Buffer.contents b

(* ── One reconciliation pass: diff, push, wait, report ─────────────────── *)

(** The digest the running nodes were last given: copied from
    [.forge/topology.json] when [forge run --processes] starts them and
    after every push. [.forge/topology.json] itself is not the observed
    state: [forge build] and [forge topology check] rewrite it without
    telling any node. *)
let applied_file ~root = Filename.concat (run_dir ~root) "applied.json"

let record_applied ~root =
  match In_channel.with_open_bin (Topology.digest_file ~root) In_channel.input_all with
  | text ->
    mkdir_p (run_dir ~root);
    Out_channel.with_open_bin (applied_file ~root) (fun oc -> output_string oc text)
  | exception Sys_error _ -> ()

(** What a difference between two topologies takes to apply. *)
type change_kind =
  | Placement              (** the nodes re-read it: no code change, no restart *)
  | Needs_restart          (** code or process layout: rebuild and restart *)

type change = { subject : string; detail : string; kind : change_kind }

let place_text (p : Topology.place option) =
  match p with
  | None -> "everywhere"
  | Some { Topology.on = None; count = None } -> "everywhere"
  | Some { on = Some l; count = None } -> "on " ^ l
  | Some { on = None; count = Some n } -> Printf.sprintf "count %d" n
  | Some { on = Some l; count = Some n } -> Printf.sprintf "count %d on %s" n l

let opt_text f = function None -> "(none)" | Some v -> f v

let hosts_text (hs : Topology.host list) =
  String.concat ", " (List.map (fun (h : Topology.host) ->
      if h.labels = [] then h.host else Printf.sprintf "%s [%s]" h.host (String.concat "," h.labels)) hs)

(** Every difference between [old_t] (what the nodes run) and [new_t],
    classified. Placement, capacity, a role a pool stops serving, a removed
    role, and drain deadlines are [Placement]: the nodes re-read them (D16).
    Anything the build or the process layout fixes is [Needs_restart]: a
    role's binding, a new role or a role newly served by a pool (its code is
    not in that pool's generated [main]), a pool's hook, caps, initiates,
    isolation, hosts and labels, pools added or removed. *)
let diff_topologies (old_t : Topology.t) (new_t : Topology.t) : change list =
  let out = ref [] in
  let add subject kind fmt = Printf.ksprintf (fun detail -> out := { subject; detail; kind } :: !out) fmt in
  let find_role (t : Topology.t) n = List.find_opt (fun (r : Topology.role) -> r.role_name = n) t.roles in
  let find_pool (t : Topology.t) n = List.find_opt (fun (p : Topology.pool) -> p.pool_name = n) t.pools in
  List.iter (fun (r : Topology.role) ->
      match find_role old_t r.role_name with
      | None -> add r.role_name Needs_restart "a new role: its code has to be built and started"
      | Some o ->
        if o.body <> r.body || o.actor <> r.actor then
          add r.role_name Needs_restart "bound to %s, was %s"
            (opt_text Fun.id (if r.body <> None then r.body else r.actor))
            (opt_text Fun.id (if o.body <> None then o.body else o.actor));
        if place_text o.place <> place_text r.place then
          add r.role_name Placement "placement %s -> %s" (place_text o.place) (place_text r.place);
        let cap (x : Topology.role) = Option.value ~default:64 x.capacity in
        if cap o <> cap r then add r.role_name Placement "capacity %d -> %d" (cap o) (cap r))
    new_t.roles;
  List.iter (fun (o : Topology.role) ->
      if find_role new_t o.role_name = None then
        add o.role_name Placement "removed: its offers close and drain")
    old_t.roles;
  List.iter (fun (p : Topology.pool) ->
      let subject = "pool " ^ p.pool_name in
      match find_pool old_t p.pool_name with
      | None -> add subject Needs_restart "a new pool: its processes have to be started"
      | Some o ->
        if o.start <> p.start then add subject Needs_restart "hook %s, was %s" (opt_text Fun.id p.start) (opt_text Fun.id o.start);
        if o.caps <> p.caps then add subject Needs_restart "caps changed (checked when the pool is built)";
        if o.initiates <> p.initiates then add subject Needs_restart "initiates changed (checked when the pool is built)";
        if o.isolate <> p.isolate then add subject Needs_restart "isolate %b -> %b (a different build)" o.isolate p.isolate;
        if o.hosts <> p.hosts then
          add subject Needs_restart "hosts [%s] -> [%s] (a node's labels are read when it starts)"
            (hosts_text o.hosts) (hosts_text p.hosts);
        List.iter (fun r ->
            if not (List.mem r o.serves) then
              add subject Needs_restart "now serves %s, which its build has no code for" r)
          p.serves;
        List.iter (fun r ->
            if not (List.mem r p.serves) && find_role new_t r <> None then
              add subject Placement "stops serving %s: its offers there close and drain" r)
          o.serves)
    new_t.pools;
  List.iter (fun (o : Topology.pool) ->
      if find_pool new_t o.pool_name = None then
        add ("pool " ^ o.pool_name) Needs_restart "removed: its processes are still running; stop and restart the cluster")
    old_t.pools;
  let drain_text (d : Topology.drain option) =
    match d with
    | None -> "default"
    | Some d -> Printf.sprintf "soft %s, hard %s" (opt_text string_of_int d.soft_ms) (opt_text string_of_int d.hard_ms)
  in
  if drain_text old_t.drain <> drain_text new_t.drain then
    add "drain" Placement "%s -> %s (offers closed from now on; a SIGTERM drain keeps the built deadlines until a restart)"
      (drain_text old_t.drain) (drain_text new_t.drain);
  List.rev !out

let render_change c =
  Printf.sprintf "  %s: %s%s" c.subject c.detail (match c.kind with Placement -> "" | Needs_restart -> "  [needs a rebuild and restart]")

(** Poll [status] until every node in [names] reports [sha], then until the
    reports stop changing (placement settles within a tick or two); gives
    up after [timeout] seconds and returns the last statuses. *)
let wait_applied ?(timeout = 30.) (b : backend) ~sha (names : string list) : node_status list * string list =
  let t0 = Unix.gettimeofday () in
  let pending ss =
    List.filter_map (fun s ->
        if List.mem s.node.name names && s.up
           && (match s.report with Some r -> r.r_topology <> sha | None -> true)
        then Some s.node.name else None)
      ss
  in
  let rec applied () =
    let ss = b.status () in
    let p = pending ss in
    if p = [] || Unix.gettimeofday () -. t0 > timeout then (ss, p) else (Unix.sleepf 0.2; applied ())
  in
  let (ss, p) = applied () in
  if p <> [] then (ss, p)
  else begin
    let offers ss = List.map (fun s -> Option.map (fun r -> r.r_offers) s.report) ss in
    let rec settle prev n =
      Unix.sleepf 0.5;
      let ss = b.status () in
      if offers ss = offers prev || n = 0 || Unix.gettimeofday () -. t0 > timeout then ss else settle ss (n - 1)
    in
    (settle ss 10, [])
  end

(** One reconciliation pass over the local backend ([forge topology apply]):
    load and check the topology (with [env], else the overlay the cluster
    was started with), diff it against what the nodes were given, refuse a
    change that needs a rebuild and restart, push the rest, wait until every
    node has applied it, and report each node's offers. Holds the reconcile
    lock throughout. *)
let apply ?env ~root () : (string, string) result =
  with_lock ~root (fun () ->
      let* (b, st) = local_backend ~root in
      let env = match env with Some e -> Some e | None -> st.env in
      let env = match env with
        | Some e when Sys.file_exists (Topology.overlay_file ~root e) -> Some e
        | _ -> None in
      let* desired =
        match Topology.load ~root ?env () with
        | Error ds -> Error (String.concat "\n" (List.map Topology.render_diag ds))
        | Ok t ->
          let ds = Topology.check ~index:(Topology.index_project ~root) t in
          List.iter (fun d -> prerr_endline (Topology.render_diag d)) ds;
          if Topology.has_errors ds then Error "topology check failed" else Ok t
      in
      let* observed =
        let path = applied_file ~root in
        if Sys.file_exists path then Topology.read_digest path
        else Error (Printf.sprintf "%s is missing: the cluster predates `forge topology apply`; restart it" path)
      in
      let changes = diff_topologies observed desired in
      let restart = List.filter (fun c -> c.kind = Needs_restart) changes in
      let buf = Buffer.create 512 in
      let say fmt = Printf.bprintf buf fmt in
      if restart <> [] then begin
        say "%d change(s):\n%s\n" (List.length changes) (String.concat "\n" (List.map render_change changes));
        Error (Buffer.contents buf
               ^ Printf.sprintf "%d of them need a rebuild and restart, so nothing was applied: stop the cluster and \
                                 run `forge run --processes%s` again"
                 (List.length restart) (match env with Some e -> " --env " ^ e | None -> ""))
      end else begin
        let ss = b.status () in
        let digest_sha = Digestif.SHA256.(to_hex (digest_string (Topology.digest_text desired))) in
        let behind =
          List.filter (fun s ->
              s.up && (match s.report with
                  | Some r -> r.r_topology <> digest_sha && not (r.r_topology = "compiled" && changes = [])
                  | None -> false))
            ss
        in
        if changes = [] && behind = [] then begin
          say "the running cluster already has this topology (no change)\n%s" (render_status ss);
          Ok (Buffer.contents buf)
        end else begin
          if changes = [] then say "no change to the topology; re-sending it to %d node(s) that have not applied it\n" (List.length behind)
          else say "%d change(s), none needs a restart:\n%s\n" (List.length changes) (String.concat "\n" (List.map render_change changes));
          let* r = b.push_topology desired in
          record_applied ~root;
          let signalled = List.filter_map (fun (n, o) -> if o = Signalled then Some n else None) r.outcome in
          say "pushed %s to %d node(s)\n" (String.sub r.sha 0 12) (List.length signalled);
          List.iter (fun (n, o) ->
              match o with
              | Signalled -> ()
              | Not_running -> say "  %s: not running\n" n
              | Not_reporting -> say "  %s: has not reported yet, so it was not signalled; apply again once it has\n" n)
            r.outcome;
          let (ss, pending) = wait_applied b ~sha:r.sha signalled in
          say "%s" (render_status ss);
          if pending <> [] then
            Error (Buffer.contents buf ^ Printf.sprintf "%s did not apply the topology within 30 s" (String.concat ", " pending))
          else Ok (Buffer.contents buf)
        end
      end)
