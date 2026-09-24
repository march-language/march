(** Running a topology app locally (distributed-deploys plan, build step 3:
    II.3 "forge run"; D9).

    - [run_level0]: [forge run] on a project with a topology.toml. Always
      compiled (the cluster runner is compiled-only; an interpreted run is
      not available to a topology app, and forge says so), with
      [--topology .forge/topology.json], so the compiler generates [main].
      The one process runs every pool (D9).
    - [run_processes]: [forge run --processes]. One build per distinct
      build (the shared one for every non-isolated pool, and one per isolated
      pool, each restricted with [--topology-pools]), then one process per
      pool replica through [Procs]: [MARCH_POOLS=<pool>],
      [MARCH_NODE_NAME=<pool>-<n>], a [Procs.free_port] cluster port, seeds
      pointing at every other process, [MARCH_NODE_LABELS] from the overlay's
      hosts. forge's own SIGINT/SIGTERM stops them all (each drains), and
      [--fail-fast] stops them all when one exits.
    - [compiler_derived]: each pool's derived caps and initiated roles, as
      the compiler computes them ([march --topology ... --emit-core-ast]'s
      [topology] object), for [forge topology export]. *)

let ( let* ) = Result.bind

(** Run [cmd] through the shell and return its stdout; stderr passes through. *)
let capture_stdout cmd : int * string =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 65536 in
  (try
     while true do
       Buffer.add_channel buf ic 1
     done
   with End_of_file -> ());
  let rc = match Unix.close_process_in ic with
    | Unix.WEXITED n -> n
    | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> 255
  in
  (rc, Buffer.contents buf)

(** The pools' derived caps and initiated roles from the compiler. Requires
    the digest to have been written ([Topology.gate] or [topology check]). *)
let compiler_derived (proj : Project.project)
  : ((string * (string list * string list)) list, string) result =
  let root = proj.Project.root in
  let* entry = Project.entry proj in
  let digest = Topology.digest_file ~root in
  let cmd =
    Printf.sprintf "%smarch --topology %s --emit-core-ast %s"
      (Cmd_build.lib_path_env proj) (Filename.quote digest) (Filename.quote entry)
  in
  let (rc, out) = capture_stdout cmd in
  match (try Ok (Yojson.Safe.from_string out) with Yojson.Json_error m -> Error m) with
  | Error m ->
    Error (Printf.sprintf "the compiler did not produce its analysis (exit %d): %s" rc m)
  | Ok json ->
    let module U = Yojson.Safe.Util in
    (match U.member "topology" json with
     | `Assoc _ as topo ->
       (match U.member "pools" topo with
        | `Assoc pools ->
          let strs j = List.map U.to_string (U.to_list j) in
          Ok (List.map (fun (name, p) ->
              (name, (strs (U.member "caps" p), strs (U.member "initiates" p)))) pools)
        | _ -> Error "the compiler's topology object has no pools")
     | _ ->
       if rc <> 0 then Error "the program does not typecheck, so its capabilities cannot be derived"
       else Error "this compiler does not report a topology object (it predates build step 3)")

(** Every `place.on` label the topology names: a level-0 process carries them
    all, so every role is offered somewhere when every pool shares one node. *)
let all_place_labels (t : Topology.t) =
  List.sort_uniq String.compare
    (List.filter_map (fun (r : Topology.role) -> Option.bind r.place (fun p -> p.Topology.on)) t.roles)

let drain_hard_ms (t : Topology.t) =
  match t.drain with Some { hard_ms = Some n; _ } -> n | _ -> 120000

let interpreted_notice =
  "forge run: this is a topology app (topology.toml), so it runs compiled: \
   the cluster runner that serves its roles is compiled-only\n"

(** Start [argv] in the foreground with [env] added, forge ignoring SIGINT
    while it runs so a Ctrl-C reaches the program (which drains) and forge
    reports how it ended. *)
let run_foreground ~env argv : (unit, string) result =
  let environment =
    Array.append
      (Array.of_list (List.map (fun (k, v) -> k ^ "=" ^ v) env))
      (Array.of_list
         (List.filter (fun kv ->
              not (List.exists (fun (k, _) ->
                  let p = k ^ "=" in
                  String.length kv >= String.length p && String.sub kv 0 (String.length p) = p) env))
             (Array.to_list (Unix.environment ()))))
  in
  let old_int = Sys.signal Sys.sigint Sys.Signal_ignore in
  let old_term = Sys.signal Sys.sigterm Sys.Signal_ignore in
  Fun.protect
    ~finally:(fun () -> Sys.set_signal Sys.sigint old_int; Sys.set_signal Sys.sigterm old_term)
    (fun () ->
       match Unix.create_process_env argv.(0) argv environment Unix.stdin Unix.stdout Unix.stderr with
       | exception Unix.Unix_error (e, _, _) -> Error (Unix.error_message e)
       | pid ->
         let rec wait () =
           match Unix.waitpid [] pid with
           | exception Unix.Unix_error (Unix.EINTR, _, _) -> wait ()
           | (_, st) -> st
         in
         (match wait () with
          | Unix.WEXITED 0 -> Ok ()
          | st -> Error (Printf.sprintf "program %s" (Procs.string_of_status st))))

(** [forge run] on a topology app: one process, every pool. *)
let run_level0 ?env ~(proj : Project.project) ~compiled ~dump_phases ~args () : (unit, string) result =
  if not compiled then prerr_string interpreted_notice;
  let root = proj.Project.root in
  let* t = match Topology.load ~root ?env () with
    | Ok t -> Ok t
    | Error ds ->
      List.iter (fun d -> prerr_endline (Topology.render_diag d)) ds;
      Error "topology check failed"
  in
  let* output = Cmd_build.build ~release:false ~dump_phases ?topology_env:env () in
  let defaults =
    List.filter (fun (k, _) -> Sys.getenv_opt k = None)
      [ ("MARCH_NODE_NAME", "local-1");
        ("MARCH_NODE_PORT", string_of_int (Procs.free_port ()));
        ("MARCH_NODE_LABELS", String.concat "," (all_place_labels t)) ]
  in
  run_foreground ~env:defaults (Array.of_list (output :: args))

(** One process to start: its name, pool, labels and which build it runs. *)
type slot = { s_name : string; s_pool : string; s_labels : string list; s_build : string }

(** The distinct builds: ("shared", non-isolated pools) and (pool, [pool])
    per isolated pool. *)
let builds_of (t : Topology.t) : (string * string list) list =
  let shared = List.filter (fun (p : Topology.pool) -> not p.isolate) t.pools in
  (if shared = [] then [] else [ ("shared", List.map (fun (p : Topology.pool) -> p.pool_name) shared) ])
  @ List.filter_map (fun (p : Topology.pool) -> if p.isolate then Some (p.pool_name, [ p.pool_name ]) else None) t.pools

(** One slot per host of each pool in the overlay, or one when it lists none. *)
let slots_of (t : Topology.t) : slot list =
  List.concat_map (fun (p : Topology.pool) ->
      let build = if p.isolate then p.pool_name else "shared" in
      let hosts = if p.hosts = [] then [ { Topology.host = ""; labels = [] } ] else p.hosts in
      List.mapi (fun i (h : Topology.host) ->
          { s_name = Printf.sprintf "%s-%d" p.pool_name (i + 1); s_pool = p.pool_name;
            s_labels = h.labels; s_build = build })
        hosts)
    t.pools

(** The environment of each slot: its pool, name, port and the others as seeds. *)
let slot_envs ~secret (slots : slot list) (ports : int list) : (slot * (string * string) list) list =
  let addrs = List.map (fun p -> "127.0.0.1:" ^ string_of_int p) ports in
  List.map2 (fun (s, port) addr ->
      let seeds = List.filter (fun a -> a <> addr) addrs in
      (s, [ ("MARCH_POOLS", s.s_pool);
            ("MARCH_NODE_NAME", s.s_name);
            ("MARCH_NODE_PORT", string_of_int port);
            ("MARCH_NODE_ADVERTISE", addr);
            ("MARCH_CLUSTER_NODES", String.concat "," seeds);
            ("MARCH_NODE_LABELS", String.concat "," s.s_labels);
            ("MARCH_CLUSTER_SECRET", secret) ]))
    (List.combine slots ports) addrs

(** [forge run --processes]: one process per pool replica. *)
let run_processes ?env ~(proj : Project.project) ~compiled ~dump_phases ~fail_fast ~args () : (unit, string) result =
  if not compiled then prerr_string interpreted_notice;
  let root = proj.Project.root in
  let* t = match Topology.load ~root ?env () with
    | Ok t -> Ok t
    | Error ds ->
      List.iter (fun d -> prerr_endline (Topology.render_diag d)) ds;
      Error "topology check failed"
  in
  let* outputs =
    List.fold_left (fun acc (build, pools) ->
        let* acc = acc in
        let* out =
          Cmd_build.build ~release:false ~dump_phases ~topology_pools:pools ~output_suffix:("-" ^ build)
            ?topology_env:env ()
        in
        Ok ((build, out) :: acc))
      (Ok []) (builds_of t)
  in
  let slots = slots_of t in
  let ports = List.map (fun _ -> Procs.free_port ()) slots in
  let secret = Sys.getenv_opt "MARCH_CLUSTER_SECRET" |> Option.value ~default:("forge-run-" ^ proj.Project.name) in
  let log = { (Procs.default_log_sink ~root) with Procs.follow = Some (fun line -> print_string line; flush stdout) } in
  let procs =
    List.map (fun (s, env) ->
        let binary = List.assoc s.s_build outputs in
        Printf.printf "forge run: starting %s (pool %s, port %s)\n%!" s.s_name s.s_pool (List.assoc "MARCH_NODE_PORT" env);
        Procs.spawn ~name:s.s_name ~env ~argv:(Array.of_list (binary :: args)) ~log)
      (slot_envs ~secret slots ports)
  in
  let results = Procs.supervise ~fail_fast ~grace_ms:(drain_hard_ms t + 2000) procs in
  let bad =
    List.filter (fun (_, st) -> match st with Unix.WEXITED 0 -> false | _ -> true) results
  in
  List.iter (fun (n, st) -> Printf.printf "forge run: %s %s\n%!" n (Procs.string_of_status st)) results;
  if bad = [] then Ok ()
  else Error (Printf.sprintf "%d of %d processes did not exit cleanly (logs in %s)"
                (List.length bad) (List.length results) (Filename.concat root ".forge/run"))
