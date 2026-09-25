(** [forge test --upgrade-from <ref>] (distributed-deploys plan, 6.6 and
    II.8; build step 8): upgrade testing as a normal test.

    1. [git worktree add] the project at [<ref>] under
       [.forge/upgrade/<ref>] (the directory ignores itself).
    2. Build the working tree's hot-reload patch, and the old version's
       (only for its actor handler signatures, [.so.schemas.json], which is
       how a deploy detects a message-type change).
    3. Start the old version under [Procs] with [forge run --processes]
       semantics ([Topology_run.start_processes]): one process per pool
       replica, hot-reload builds signed by a key minted for this run, a
       reload socket per process ([MARCH_HOT_RELOAD_SOCKET]).
    4. Compile and start each [test/upgrade_*.march] of the working tree,
       as one more cluster node. It is given the sockets and two files:
       [MARCH_UPGRADE_READY], which it creates once its pre-upgrade traffic
       runs, and [MARCH_UPGRADE_DEPLOYED], which forge creates once the new
       code is live. It exits 0 when its own checks pass.
    5. Deploy the working tree into every process through
       [Cmd_deploy_hot.run] on its local socket (no tunnel).
    6. Wait for the tests to exit and for the drain: every actor has reached
       its marker ([PINS]' [markers_live] is 0; the soft deadline forces the
       unheld ones). An actor holding an epoch (a session endpoint whose
       session has not finished) or parked in a nested receive keeps its
       marker until a hard deadline, which is off by default, as do units
       that are not actors (tasks: a pool hook's feeder, the placement loop):
       both are reported, and fail the test only under
       [MARCH_UPGRADE_STRICT_DRAIN=1].
    7. Pass when every test exited 0, every process is still running, and
       each reload server's counters show nothing dropped, nothing killed
       by a hard deadline and no marker lost. A dropped message is the
       typical broken upgrade: an actor whose message type changed with no
       [migrate_msg] for what old code still sends it.

    Limits: a topology app only, and no isolated pools (one shared build is
    patched). *)

let ( let* ) = Result.bind

let say fmt = Printf.ksprintf (fun s -> print_string ("upgrade: " ^ s ^ "\n"); flush stdout) fmt

let sanitize r = String.map (fun c -> match c with 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' -> c | _ -> '_') r

(** Run [argv] (no shell) in [cwd]; its exit code and stdout+stderr. *)
let capture ?cwd (argv : string list) : int * string =
  let tmp = Filename.temp_file "forge_upgrade_" ".out" in
  let fd = Unix.openfile tmp [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
  let pid =
    match Unix.fork () with
    | 0 ->
      (try
         Option.iter Unix.chdir cwd;
         Unix.dup2 fd Unix.stdout;
         Unix.dup2 fd Unix.stderr;
         Unix.execvp (List.hd argv) (Array.of_list argv)
       with _ -> Unix._exit 127)
    | p -> p
  in
  Unix.close fd;
  let rec wait () = match Unix.waitpid [] pid with
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> wait ()
    | (_, st) -> st in
  let rc = match wait () with Unix.WEXITED n -> n | _ -> 255 in
  let out = try In_channel.with_open_bin tmp In_channel.input_all with Sys_error _ -> "" in
  (try Sys.remove tmp with Sys_error _ -> ());
  (rc, out)

let git ~cwd args =
  match capture ~cwd ("git" :: args) with
  | (0, out) -> Ok (String.trim out)
  | (rc, out) -> Error (Printf.sprintf "git %s failed (exit %d): %s" (String.concat " " args) rc (String.trim out))

let realpath p = try Unix.realpath p with Unix.Unix_error _ -> p

let with_cwd dir f =
  let old = Sys.getcwd () in
  Sys.chdir dir;
  Fun.protect ~finally:(fun () -> Sys.chdir old) f

(** Check out [ref_] into [.forge/upgrade/<ref>]; the old project's root
    (the same path inside the checkout as [root] inside its repository) and
    a cleanup that removes the worktree. *)
let worktree_add ~root ~ref_ : (string * (unit -> unit), string) result =
  let* top = git ~cwd:root [ "rev-parse"; "--show-toplevel" ] in
  let* _ = git ~cwd:root [ "rev-parse"; "--verify"; "--quiet"; ref_ ^ "^{commit}" ] in
  let top = realpath top and root_r = realpath root in
  let rel =
    if root_r = top then ""
    else
      let n = String.length top in
      if String.length root_r > n && String.sub root_r 0 (n + 1) = top ^ "/" then
        String.sub root_r (n + 1) (String.length root_r - n - 1)
      else ""
  in
  let up = Filename.concat (Filename.concat root ".forge") "upgrade" in
  Reconcile.mkdir_p up;
  Out_channel.with_open_bin (Filename.concat up ".gitignore") (fun oc -> output_string oc "*\n");
  let dir = Filename.concat up (sanitize ref_) in
  if Sys.file_exists dir then begin
    ignore (git ~cwd:top [ "worktree"; "remove"; "--force"; dir ]);
    ignore (Sys.command ("rm -rf " ^ Filename.quote dir))
  end;
  ignore (git ~cwd:top [ "worktree"; "prune" ]);
  let* _ = git ~cwd:top [ "worktree"; "add"; "--detach"; dir; ref_ ] in
  let cleanup () =
    ignore (git ~cwd:top [ "worktree"; "remove"; "--force"; dir ]);
    ignore (git ~cwd:top [ "worktree"; "prune" ])
  in
  Ok ((if rel = "" then dir else Filename.concat dir rel), cleanup)

(** Compile [proj]'s hot-reload patch to [out].so (with its manifest and
    actor schemas), with the same boundary and topology as its base build.
    Run from a fresh working directory: the compiler's artifact cache lives
    under the working directory's .march/cas, and a cache hit copies the
    .so alone, without its .hcr_manifest and .schemas.json sidecars, which
    this needs (todo: 2026-09-24-cas-hit-skips-so-sidecars). *)
let build_patch ~(proj : Project.project) ~out ~log : (string * string * string, string) result =
  let* entry = Project.entry proj in
  let entry = if Filename.is_relative entry then Filename.concat proj.Project.root entry else entry in
  let* prefix = Topology_run.entry_module proj in
  let so = out ^ ".so" in
  let cwd = out ^ ".build" in
  Reconcile.mkdir_p cwd;
  let cmd =
    Printf.sprintf "cd %s && %smarch --compile --compile-so --hot-reload %s --topology %s%s -o %s %s > %s 2>&1"
      (Filename.quote cwd) (Cmd_build.lib_path_env proj) (Filename.quote prefix)
      (Filename.quote (Topology.digest_file ~root:proj.Project.root))
      (Cmd_build.ffi_flags_of ~root:proj.Project.root proj)
      (Filename.quote so) (Filename.quote entry) (Filename.quote log)
  in
  let rc = Sys.command cmd in
  if rc <> 0 then Error (Printf.sprintf "building the hot-reload patch failed (exit %d); see %s" rc log)
  else if not (Sys.file_exists (so ^ ".hcr_manifest")) then Error (Printf.sprintf "no manifest next to %s" so)
  else Ok (so, so ^ ".hcr_manifest", so ^ ".schemas.json")

(** Compile an upgrade test file against the working tree's lib/ and
    dependencies (the project's MARCH_LIB_PATH). The entry module is not on
    it: a topology app's entry has no [main] of its own, so a test file
    declares the protocols it drives itself (a protocol's wire fingerprint is
    its name, roles and steps, so a copy interoperates). *)
let build_test ~(proj : Project.project) ~file ~out ~log : (string, string) result =
  let cmd = Printf.sprintf "%smarch --compile -o %s %s > %s 2>&1"
      (Cmd_build.lib_path_env proj) (Filename.quote out) (Filename.quote file) (Filename.quote log) in
  let rc = Sys.command cmd in
  if rc <> 0 then Error (Printf.sprintf "compiling %s failed (exit %d); see %s" file rc log) else Ok out

let find_tests ~root =
  let dir = Filename.concat root "test" in
  match Sys.readdir dir with
  | exception Sys_error _ -> []
  | names ->
    Array.to_list names
    |> List.filter (fun n ->
        String.length n > 13 && String.sub n 0 8 = "upgrade_" && Filename.check_suffix n ".march")
    |> List.sort compare
    |> List.map (Filename.concat dir)

let wait_until ~timeout f =
  let t0 = Unix.gettimeofday () in
  let rec go () = f () || (Unix.gettimeofday () -. t0 < timeout && (Unix.sleepf 0.1; go ())) in
  go ()

let pins_of socket = match Reconcile.query_reload socket with Ok ri -> Some ri.pins | Error _ -> None

(** Epochs other than the current one that still pin units. *)
let pinned_old pins =
  List.filter_map (fun (e, n, current) -> if not current && n > 0 then Some (e, n) else None) (Reconcile.pins_epochs pins)

let env_float name default =
  match Option.bind (Sys.getenv_opt name) float_of_string_opt with Some f -> f | None -> default

(** The whole test. [Ok summary] when the upgrade passed. *)
let run ~ref_ () : (string, string) result =
  let* proj = Project.load () in
  let root = proj.Project.root in
  if not (Topology.exists ~root) then
    Error "--upgrade-from tests a topology app (a project with topology.toml): it starts the old version's pools as processes"
  else
  let tests = find_tests ~root in
  if tests = [] then Error "--upgrade-from needs at least one test/upgrade_*.march: the traffic to drive across the upgrade"
  else
  let* t_new = match Topology.load ~root () with
    | Ok t -> Ok t | Error ds -> Error (String.concat "\n" (List.map Topology.render_diag ds)) in
  if List.exists (fun (p : Topology.pool) -> p.isolate) t_new.pools then
    Error "--upgrade-from does not support isolated pools yet (only the shared build is patched)"
  else
  let* () = Topology.gate ~proj () in
  let up = Filename.concat (Filename.concat root ".forge") "upgrade" in
  let work = Filename.concat up "run" in
  ignore (Sys.command ("rm -rf " ^ Filename.quote work));
  Reconcile.mkdir_p work;
  say "checking out %s" ref_;
  let* (old_root, cleanup) = worktree_add ~root ~ref_ in
  Fun.protect ~finally:cleanup (fun () ->
      let (pk, sk) = March_ed25519.Ed25519.keygen () in
      let pk_b64 = March_ed25519.Ed25519.pk_to_base64 pk in
      say "building the working tree's patch";
      let* (new_so, new_manifest_path, new_schemas) =
        build_patch ~proj ~out:(Filename.concat work "new") ~log:(Filename.concat work "build-new.log") in
      let* manifest = Cmd_deploy_hot.parse_manifest new_manifest_path in
      let* old_proj = with_cwd old_root (fun () -> Project.load ()) in
      let* () = with_cwd old_root (fun () -> Topology.gate ~proj:old_proj ()) in
      say "building %s" ref_;
      let* (_, old_manifest, old_schemas) =
        with_cwd old_root (fun () ->
            build_patch ~proj:old_proj ~out:(Filename.concat work "old") ~log:(Filename.concat work "build-old.log")) in
      let* test_bins =
        List.fold_left (fun acc file ->
            let* acc = acc in
            let name = Filename.chop_suffix (Filename.basename file) ".march" in
            let* bin = build_test ~proj ~file ~out:(Filename.concat work name)
                ~log:(Filename.concat work ("build-" ^ name ^ ".log")) in
            Ok ((name, bin) :: acc))
          (Ok []) tests
        |> Result.map List.rev
      in
      let log = { Procs.dir = work; follow = Some (fun line -> print_string line; flush stdout) } in
      say "starting %s" ref_;
      let* started =
        with_cwd old_root (fun () ->
            Topology_run.start_processes ~hot_reload:true ~pubkey:pk_b64 ~log ~proj:old_proj
              ~compiled:true ~dump_phases:false ~args:[] ())
      in
      let app = started.Topology_run.procs in
      let nodes = started.state.Reconcile.nodes in
      let test_procs = ref [] in
      Fun.protect
        ~finally:(fun () ->
            Procs.stop_all !test_procs ~grace_ms:2000;
            Procs.stop_all app ~grace_ms:(Topology_run.drain_hard_ms started.topology + 2000);
            Reconcile.remove_state ~root:old_root)
        (fun () ->
           let sockets = List.filter_map (fun n -> n.Reconcile.socket) nodes in
           if not (wait_until ~timeout:120. (fun () -> List.for_all (fun s -> pins_of s <> None) sockets)) then
             Error "the old version's reload servers never answered"
           else begin
             let secret = Option.value ~default:("forge-run-" ^ old_proj.Project.name) (Sys.getenv_opt "MARCH_CLUSTER_SECRET") in
             let seeds = String.concat "," (List.map (fun n -> "127.0.0.1:" ^ string_of_int n.Reconcile.port) nodes) in
             let deployed = Filename.concat work "deployed" in
             let tp =
               List.map (fun (name, bin) ->
                   let port = Procs.free_port () in
                   let ready = Filename.concat work (name ^ ".ready") in
                   let env = [ ("MARCH_NODE_NAME", name); ("MARCH_NODE_PORT", string_of_int port);
                               ("MARCH_NODE_ADVERTISE", "127.0.0.1:" ^ string_of_int port);
                               ("MARCH_CLUSTER_NODES", seeds); ("MARCH_CLUSTER_SECRET", secret);
                               ("MARCH_UPGRADE_SOCKETS", String.concat "," sockets);
                               ("MARCH_UPGRADE_READY", ready); ("MARCH_UPGRADE_DEPLOYED", deployed) ] in
                   (Procs.spawn ~name ~env ~argv:[| bin |] ~log, ready))
                 test_bins
             in
             test_procs := List.map fst tp;
             say "driving %s" (String.concat ", " (List.map fst test_bins));
             let ready () = List.for_all (fun (p, r) -> Sys.file_exists r || Procs.status p <> None) tp in
             if not (wait_until ~timeout:(env_float "MARCH_UPGRADE_READY_S" 180.) ready) then
               Error "the upgrade test never signalled MARCH_UPGRADE_READY"
             else match List.find_opt (fun (p, r) -> not (Sys.file_exists r) && Procs.status p <> None) tp with
               | Some (p, _) ->
                 Error (Printf.sprintf "%s %s before the upgrade (log: %s)" (Procs.name p)
                          (Procs.string_of_status (Option.get (Procs.status p))) (Procs.log_path p))
               | None ->
                 say "deploying the working tree into %d process(es)" (List.length nodes);
                 let deploys =
                   List.map (fun n ->
                       match n.Reconcile.socket with
                       | None -> (n.Reconcile.name, Error "no reload socket")
                       | Some sock ->
                         let r =
                           try
                             Cmd_deploy_hot.run ~tunnel:false ~ssh_host:n.Reconcile.name ~remote_socket:sock
                               ~signing_pubkey:pk_b64 ~sk ~manifest ~so_path:new_so
                               ~old_schemas_path:old_schemas ~new_schemas_path:new_schemas
                               ~entry_path:(Result.value ~default:"" (Project.entry proj))
                               ~old_manifest_path:old_manifest ()
                           with Failure m -> Error m | Unix.Unix_error (e, _, _) -> Error (Unix.error_message e)
                         in
                         (n.Reconcile.name, Result.map ignore r))
                     nodes
                 in
                 Out_channel.with_open_bin deployed (fun oc -> output_string oc "deployed\n");
                 let failed_deploys = List.filter_map (fun (n, r) -> match r with Error m -> Some (n ^ ": " ^ m) | Ok () -> None) deploys in
                 if failed_deploys <> [] then
                   Error ("the deploy failed: " ^ String.concat "; " failed_deploys)
                 else begin
                   say "deployed; waiting for the tests and the drains";
                   let tests_done = Procs.wait_all ~timeout:(env_float "MARCH_UPGRADE_TEST_S" 180.) !test_procs in
                   let drain_s = env_float "MARCH_UPGRADE_DRAIN_S" 60. in
                   let markers_live pins = Option.value ~default:0 (Reconcile.pins_counter pins "markers_live") in
                   let drained = wait_until ~timeout:drain_s (fun () ->
                       List.for_all (fun s -> match pins_of s with Some p -> markers_live p = 0 | None -> false) sockets) in
                   let problems = ref [] in
                   let problem fmt = Printf.ksprintf (fun s -> problems := s :: !problems) fmt in
                   if not tests_done then problem "the upgrade test did not finish";
                   List.iter (fun p ->
                       match Procs.status p with
                       | Some (Unix.WEXITED 0) -> ()
                       | Some st -> problem "%s %s (log: %s)" (Procs.name p) (Procs.string_of_status st) (Procs.log_path p)
                       | None -> ())
                     !test_procs;
                   List.iter (fun p ->
                       match Procs.status p with
                       | None -> ()
                       | Some st -> problem "%s (the old version's process) %s during the upgrade (log: %s)"
                                      (Procs.name p) (Procs.string_of_status st) (Procs.log_path p))
                     app;
                   let lines = ref [] in
                   List.iter (fun n ->
                       match n.Reconcile.socket with
                       | None -> ()
                       | Some sock ->
                         match pins_of sock with
                         | None -> problem "%s: its reload server stopped answering" n.Reconcile.name
                         | Some pins ->
                           let c k = Option.value ~default:0 (Reconcile.pins_counter pins k) in
                           lines := Printf.sprintf "%s: converted %d, dropped %d, killed %d, deferred %d, markers lost %d"
                               n.Reconcile.name (c "converted") (c "dropped") (c "killed") (c "deferred") (c "markers_lost")
                                    :: !lines;
                           if c "dropped" > 0 then
                             problem "%s dropped %d message(s): an actor's message type changed and old code still sent it \
                                      the old format, with no migrate_msg for it (write one: forge hot-reload migrate-msg-stub <Actor>)"
                               n.Reconcile.name (c "dropped");
                           if c "killed" > 0 then
                             problem "%s: a hard drain deadline killed %d actor(s)" n.Reconcile.name (c "killed");
                           if c "markers_lost" > 0 then
                             problem "%s lost %d epoch marker(s)" n.Reconcile.name (c "markers_lost");
                           if not drained && markers_live pins > 0 then begin
                             let msg = Printf.sprintf
                                 "%s: %d actor(s) still on an old epoch %.0f s after the deploy (holding it for an unfinished session, or in a nested receive); a hard drain deadline (MARCH_HCR_HARD_DRAIN_MS) would stop them"
                                 n.Reconcile.name (markers_live pins) drain_s in
                             if Sys.getenv_opt "MARCH_UPGRADE_STRICT_DRAIN" = Some "1" then problem "%s" msg
                             else lines := msg :: !lines
                           end;
                           (match pinned_old pins with
                            | [] -> ()
                            | l ->
                              lines := Printf.sprintf "%s: %s still pinned by units that are not actors (tasks); only a hard drain deadline (MARCH_HCR_HARD_DRAIN_MS) stops those"
                                  n.Reconcile.name
                                  (String.concat ", " (List.map (fun (e, k) -> Printf.sprintf "epoch %d (%d unit(s))" e k) l)) :: !lines))
                     nodes;
                   List.iter (fun l -> say "%s" l) (List.rev !lines);
                   match List.rev !problems with
                   | [] -> Ok (Printf.sprintf "upgrade from %s passed: %d test(s), %d process(es), nothing dropped"
                                 ref_ (List.length test_bins) (List.length nodes))
                   | ps -> Error (Printf.sprintf "upgrade from %s FAILED:\n  %s" ref_ (String.concat "\n  " ps))
                 end
           end))
