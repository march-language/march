(** Tests for forge/lib/reconcile.ml: the reconciler's local backend
    (distributed-deploys plan, build step 8). In-process with stand-in
    nodes (shell loops, a forked fake reload server): no toolchain. The
    real three-node cluster is test_topology_reconcile.ml.

    Liveness is judged by [Unix.kill pid 0], never by a kill's return value:
    a sandboxed kill can succeed and deliver nothing. *)

open March_forge

let tmp_root () =
  let d = Filename.temp_dir "reconcile_" "" in
  Reconcile.mkdir_p (Reconcile.run_dir ~root:d);
  d

let contains s sub =
  let n = String.length s and k = String.length sub in
  let rec go i = i + k <= n && (String.sub s i k = sub || go (i + 1)) in
  go 0

let read_file path = try In_channel.with_open_bin path In_channel.input_all with Sys_error _ -> ""

let write_file path s = Out_channel.with_open_bin path (fun oc -> output_string oc s)

let wait_until ?(timeout = 10.) f =
  let t0 = Unix.gettimeofday () in
  let rec go () = f () || (Unix.gettimeofday () -. t0 < timeout && (Unix.sleepf 0.05; go ())) in
  go ()

let node ~root ?socket ?(pid = 0) name : Reconcile.node =
  { Reconcile.name; pool = "p"; pid; port = 7000; socket; labels = [ "l" ];
    status_path = Reconcile.status_file ~root name; log = Filename.concat root (name ^ ".log"); host = "" }

let topology_text = {|
[roles]
"Echo.Server" = { body = "App.serve", capacity = 4, place = { count = 1 } }

[pool.a]
serves = ["Echo.Server"]
|}

let topology () =
  match Topology.of_strings [ ("topology.toml", topology_text) ] with
  | Ok t -> t
  | Error ds -> Alcotest.failf "fixture topology: %s" (String.concat "; " (List.map Topology.render_diag ds))

(* ── state.json ─────────────────────────────────────────────────────────── *)

let test_state_round_trip () =
  let root = tmp_root () in
  let st = { Reconcile.forge_pid = Unix.getpid (); env = Some "dev"; started_at = 12.5;
             nodes = [ node ~root ~socket:"/tmp/x.sock" ~pid:(Unix.getpid ()) "a-1"; node ~root "b-1" ] } in
  Reconcile.write_state ~root st;
  (match Reconcile.read_state ~root with
   | Ok (Some got) ->
     Alcotest.(check (list string)) "node names" [ "a-1"; "b-1" ] (List.map (fun n -> n.Reconcile.name) got.nodes);
     Alcotest.(check (option string)) "env" (Some "dev") got.env;
     Alcotest.(check (option string)) "socket" (Some "/tmp/x.sock") (List.hd got.nodes).socket;
     Alcotest.(check (option string)) "no socket" None (List.nth got.nodes 1).socket
   | Ok None -> Alcotest.fail "a live run read back as none"
   | Error m -> Alcotest.fail m);
  (* A run whose forge and nodes are all gone is stale: no run. *)
  let dead = match Unix.fork () with 0 -> Unix._exit 0 | p -> ignore (Unix.waitpid [] p); p in
  Reconcile.write_state ~root { st with forge_pid = dead; nodes = [ node ~root ~pid:dead "a-1" ] };
  (match Reconcile.read_state ~root with
   | Ok None -> ()
   | Ok (Some _) -> Alcotest.fail "a dead run was reported as running"
   | Error m -> Alcotest.fail m);
  Reconcile.remove_state ~root;
  Alcotest.(check bool) "removed" false (Sys.file_exists (Reconcile.state_file ~root))

let test_local_backend_needs_a_run () =
  let root = tmp_root () in
  match Reconcile.local_backend ~root with
  | Error m -> Alcotest.(check bool) "says how to start one" true
                 (contains m "forge run --processes")
  | Ok _ -> Alcotest.fail "a backend without a run"

(* ── the single-writer lock ─────────────────────────────────────────────── *)

let test_lock_single_writer () =
  let root = tmp_root () in
  let ready = Filename.concat root "held" in
  let release = Filename.concat root "release" in
  let child =
    match Unix.fork () with
    | 0 ->
      let r = Reconcile.with_lock ~root (fun () ->
          write_file ready "";
          while not (Sys.file_exists release) do Unix.sleepf 0.02 done;
          Ok ()) in
      Unix._exit (if Result.is_ok r then 0 else 3)
    | p -> p
  in
  if not (wait_until (fun () -> Sys.file_exists ready)) then Alcotest.fail "the child never took the lock";
  (match Reconcile.with_lock ~root (fun () -> Ok ()) with
   | Ok () -> Alcotest.fail "two writers held the lock at once"
   | Error m ->
     Alcotest.(check bool) "names the holder's pid" true (contains m ("pid " ^ string_of_int child)));
  write_file release "";
  (match Unix.waitpid [] child with
   | (_, Unix.WEXITED 0) -> ()
   | _ -> Alcotest.fail "the child's pass failed");
  (match Reconcile.with_lock ~root (fun () -> Ok 7) with
   | Ok 7 -> ()
   | _ -> Alcotest.fail "the lock was not released when its holder finished");
  (* A holder that dies without unlocking releases it too (kernel-held). *)
  let child2 = match Unix.fork () with
    | 0 -> ignore (Reconcile.with_lock ~root (fun () -> write_file ready "2"; Unix.sleepf 30.; Ok ())); Unix._exit 0
    | p -> p in
  if not (wait_until (fun () -> read_file ready = "2")) then Alcotest.fail "second child never took the lock";
  Unix.kill child2 Sys.sigkill;
  ignore (Unix.waitpid [] child2);
  Alcotest.(check bool) "a killed holder's lock is free" true (Result.is_ok (Reconcile.with_lock ~root (fun () -> Ok ())))

(* ── push_topology ──────────────────────────────────────────────────────── *)

(** A stand-in node: a shell that appends "hup" to [marks] on each SIGHUP. *)
let spawn_node ~root name marks =
  let log = { Procs.dir = root; follow = None } in
  Procs.spawn ~name ~env:[]
    ~argv:[| "sh"; "-c"; Printf.sprintf "trap 'echo hup >> %s' HUP; while :; do sleep 0.05; done" (Filename.quote marks) |]
    ~log

let test_push_signals_reporting_nodes () =
  let root = tmp_root () in
  let marks_a = Filename.concat root "a.marks" and marks_b = Filename.concat root "b.marks" in
  let pa = spawn_node ~root "a-1" marks_a and pb = spawn_node ~root "b-1" marks_b in
  Fun.protect ~finally:(fun () -> Procs.stop_all [ pa; pb ] ~grace_ms:500) (fun () ->
      Unix.sleepf 0.3;  (* let each shell install its trap *)
      let na = node ~root ~pid:(Procs.pid pa) "a-1" and nb = node ~root ~pid:(Procs.pid pb) "b-1" in
      let dead = match Unix.fork () with 0 -> Unix._exit 0 | p -> ignore (Unix.waitpid [] p); p in
      let nc = node ~root ~pid:dead "c-1" in
      (* a-1 has reported; b-1 has not (SIGHUP would kill a node with no watcher). *)
      write_file na.status_path "node a-1\ntopology compiled\noffers \n";
      let st = { Reconcile.forge_pid = Unix.getpid (); env = None; started_at = 0.; nodes = [ na; nb; nc ] } in
      let b = Reconcile.local ~root st in
      match b.push_topology (topology ()) with
      | Error m -> Alcotest.fail m
      | Ok r ->
        let outcome n = List.assoc n r.outcome in
        Alcotest.(check bool) "a-1 signalled" true (outcome "a-1" = Reconcile.Signalled);
        Alcotest.(check bool) "b-1 not reporting" true (outcome "b-1" = Reconcile.Not_reporting);
        Alcotest.(check bool) "c-1 not running" true (outcome "c-1" = Reconcile.Not_running);
        Alcotest.(check bool) "a-1 received SIGHUP" true (wait_until (fun () -> read_file marks_a = "hup\n"));
        Alcotest.(check string) "b-1 received nothing" "" (read_file marks_b);
        Alcotest.(check bool) "b-1 still alive" true (Reconcile.alive (Procs.pid pb));
        Alcotest.(check string) "the digest is .forge/topology.json" (Topology.digest_file ~root) r.digest;
        Alcotest.(check (option string)) "sha of what was written" (Reconcile.sha256_file r.digest) (Some r.sha);
        (match Topology.read_digest r.digest with
         | Ok t -> Alcotest.(check (list string)) "digest content" [ "Echo.Server" ]
                     (List.map (fun (r : Topology.role) -> r.role_name) t.roles)
         | Error m -> Alcotest.fail m))

(* ── status ─────────────────────────────────────────────────────────────── *)

(** A fake reload server on [path] answering VERSIONS_DETAIL and PINS for one
    connection, in a forked child. *)
let fake_reload_server path =
  (try Sys.remove path with Sys_error _ -> ());
  let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Unix.bind fd (Unix.ADDR_UNIX path);
  Unix.listen fd 1;
  match Unix.fork () with
  | 0 ->
    let (c, _) = Unix.accept fd in
    let ic = Unix.in_channel_of_descr c and oc = Unix.out_channel_of_descr c in
    (try
       while true do
         match input_line ic with
         | "VERSIONS_DETAIL" ->
           output_string oc "SLOT 0 App.f abc123 0 (none) 0\nSLOT 1 App.g def456 1700000000000 ab12 2\nEND\n"; flush oc
         | "PINS" ->
           output_string oc "EPOCH 1 pins:3 draining\nEPOCH 2 pins:1 current\n\
                             COUNTERS deferred:0 converted:4 dropped:2 killed:0 stopped:0 advances:5 early:1 forced:0 markers_live:0 markers_lost:0\nEND\n";
           flush oc
         | _ -> output_string oc "ERR unknown_command\n"; flush oc
       done
     with End_of_file -> ());
    Unix._exit 0
  | p -> Unix.close fd; p

let test_status_reads_reports_and_reload_server () =
  let root = tmp_root () in
  let sock = Reconcile.socket_path ~root "a-1" in
  let server = fake_reload_server sock in
  let na = node ~root ~socket:sock ~pid:(Unix.getpid ()) "a-1" in
  write_file na.status_path "node a-1\ntopology 0123456789abcdef\noffers Echo.Server,Count.Counter\ndraining 1\nrunning 2\n";
  let nb = node ~root ~pid:(Unix.getpid ()) "b-1" in
  let st = { Reconcile.forge_pid = Unix.getpid (); env = None; started_at = 0.; nodes = [ na; nb ] } in
  let ss = (Reconcile.local ~root st).status () in
  ignore (Unix.waitpid [] server);
  let a = List.hd ss and b = List.nth ss 1 in
  (match a.report with
   | Some r ->
     Alcotest.(check (list string)) "offers" [ "Echo.Server"; "Count.Counter" ] r.r_offers;
     Alcotest.(check string) "applied topology" "0123456789abcdef" r.r_topology;
     Alcotest.(check int) "running" 2 r.r_running;
     Alcotest.(check int) "draining" 1 r.r_draining
   | None -> Alcotest.fail "a-1's report was not read");
  (match a.reload with
   | Some (Ok ri) ->
     Alcotest.(check int) "two slots" 2 (List.length ri.versions);
     Alcotest.(check (option int)) "dropped counter" (Some 2) (Reconcile.pins_counter ri.pins "dropped");
     Alcotest.(check (option int)) "converted counter" (Some 4) (Reconcile.pins_counter ri.pins "converted");
     Alcotest.(check (list (triple int int bool))) "epochs" [ (1, 3, false); (2, 1, true) ] (Reconcile.pins_epochs ri.pins)
   | Some (Error m) -> Alcotest.failf "reload server: %s" m
   | None -> Alcotest.fail "a-1's reload server was not queried");
  Alcotest.(check bool) "b-1 has not reported" true (b.report = None);
  Alcotest.(check bool) "b-1 has no reload server" true (b.reload = None);
  let text = Reconcile.render_status ss in
  List.iter (fun s -> if not (contains text s) then Alcotest.failf "expected %S in:\n%s" s text)
    [ "a-1 (pool p"; "offers: Echo.Server, Count.Counter"; "1 hot-patched"; "b-1 (pool p"; "has not reported" ]

let test_parse_report () =
  Alcotest.(check bool) "no topology line: not a report" true (Reconcile.parse_report "node x\n" = None);
  match Reconcile.parse_report "node x\ntopology compiled\noffers\n" with
  | Some r -> Alcotest.(check (list string)) "no offers" [] r.r_offers
  | None -> Alcotest.fail "minimal report"

let test_socket_path_short () =
  let deep = String.concat "/" ("/tmp" :: List.init 12 (fun _ -> "deep_directory")) in
  let p = Reconcile.socket_path ~root:deep "back-1" in
  Alcotest.(check bool) "fits sun_path" true (String.length p <= 100);
  let q = Reconcile.socket_path ~root:"/tmp/p" "back-1" in
  Alcotest.(check string) "a short root keeps .forge/run" "/tmp/p/.forge/run/back-1.sock" q

(* ── the diff: what a change takes to apply ─────────────────────────────── *)

let topo text =
  match Topology.of_strings [ ("topology.toml", text) ] with
  | Ok t -> t
  | Error ds -> Alcotest.failf "fixture: %s" (String.concat "; " (List.map Topology.render_diag ds))

let base_text = {|
[roles]
"Echo.Server" = { body = "App.serve", capacity = 4, place = { count = 1 } }
"Log.Sink" = { body = "App.sink" }

[pool.a]
start = "App.start"
serves = ["Echo.Server", "Log.Sink"]
hosts = [{ host = "h1", labels = ["x"] }]

[pool.b]
serves = ["Echo.Server"]
|}

let kinds changes =
  List.map (fun (c : Reconcile.change) ->
      (c.subject, (match c.kind with Reconcile.Placement -> "placement" | Reconcile.Needs_restart -> "restart"))) changes

let replace ~sub ~by s = Str.global_replace (Str.regexp_string sub) by s

let test_diff_placement_only () =
  let old_t = topo base_text in
  Alcotest.(check (list (pair string string))) "no change" [] (kinds (Reconcile.diff_topologies old_t old_t));
  let new_t = topo (base_text
                    |> replace ~sub:{|place = { count = 1 }|} ~by:{|place = { on = "x", count = 1 }|}
                    |> replace ~sub:"capacity = 4" ~by:"capacity = 8"
                    |> replace ~sub:{|[pool.b]
serves = ["Echo.Server"]|} ~by:{|[pool.b]
serves = []|}) in
  let cs = Reconcile.diff_topologies old_t new_t in
  Alcotest.(check (list (pair string string))) "all placement"
    [ ("Echo.Server", "placement"); ("Echo.Server", "placement"); ("pool b", "placement") ] (kinds cs);
  Alcotest.(check (list string)) "details"
    [ "placement count 1 -> count 1 on x"; "capacity 4 -> 8"; "stops serving Echo.Server: its offers there close and drain" ]
    (List.map (fun (c : Reconcile.change) -> c.detail) cs)

let test_diff_needs_restart () =
  let old_t = topo base_text in
  let check_restart what text subject =
    let cs = Reconcile.diff_topologies old_t (topo text) in
    if not (List.exists (fun (c : Reconcile.change) -> c.subject = subject && c.kind = Reconcile.Needs_restart) cs) then
      Alcotest.failf "%s: expected a restart for %s, got [%s]" what subject
        (String.concat "; " (List.map Reconcile.render_change cs))
  in
  check_restart "rebinding" (replace ~sub:"App.serve" ~by:"App.serve2" base_text) "Echo.Server";
  check_restart "a new served role" (replace ~sub:{|serves = ["Echo.Server"]
|} ~by:{|serves = ["Echo.Server", "Log.Sink"]
|} base_text) "pool b";
  check_restart "a hook" (replace ~sub:"App.start" ~by:"App.boot" base_text) "pool a";
  check_restart "labels" (replace ~sub:{|labels = ["x"]|} ~by:{|labels = ["x", "y"]|} base_text) "pool a";
  check_restart "a new pool" (base_text ^ "\n[pool.c]\nserves = []\n") "pool c";
  check_restart "a new role"
    (replace ~sub:{|"Log.Sink" = { body = "App.sink" }|} ~by:{|"Log.Sink" = { body = "App.sink" }
"Log.Tail" = { body = "App.tail" }|} base_text) "Log.Tail"

(* ── the ssh backend (build step 10b), over the local transport ─────────── *)

let ssh_topology_text = {|
[roles]
"Echo.Server" = { body = "App.serve", capacity = 4 }

[pool.a]
serves = ["Echo.Server"]
hosts = [{ host = "root@web-1", labels = ["edge", "x"] }]

[pool.b]
serves = ["Echo.Server"]
hosts = ["root@web-2"]

[backend]
kind = "ssh"
port = 7950
|}

let ssh_topology ?(text = ssh_topology_text) () =
  match Topology.of_strings [ ("topology.toml", text) ] with
  | Ok t -> t
  | Error ds -> Alcotest.failf "ssh topology: %s" (String.concat "; " (List.map Topology.render_diag ds))

let record ~host ~pool target =
  { Reconcile.hr_host = host; hr_pool = pool; hr_node = pool ^ "-x"; hr_target = target;
    hr_triple = "t"; hr_uname = "u"; hr_at = 0. }

let test_ssh_nodes_from_overlay () =
  let layout = Host_layout.make ~prefix:"/srv" "app" in
  let records = [ record ~host:"root@web-1" ~pool:"a" "linux/arm64" ] in
  match Reconcile.ssh_nodes ~layout ~pubkey:"PK" ~records (ssh_topology ()) with
  | Error m -> Alcotest.fail m
  | Ok [ a; b ] ->
    Alcotest.(check string) "node name" "a-web-1" a.sn.Hosts.name;
    Alcotest.(check string) "ssh target" "root@web-1" a.sn.Hosts.ssh;
    Alcotest.(check (list string)) "labels from the overlay" [ "edge"; "x" ] a.sn.Hosts.labels;
    Alcotest.(check string) "socket from the layout" "/srv/var/lib/march/app/run/a.sock" a.sn.Hosts.socket;
    Alcotest.(check string) "pubkey" "PK" a.sn.Hosts.pubkey;
    Alcotest.(check int) "cluster port" 7950 a.sn_port;
    Alcotest.(check (option string)) "recorded target" (Some "linux/arm64") a.sn_target;
    Alcotest.(check (option string)) "not initialised" None b.sn_target;
    Alcotest.(check (list string)) "a bare host has no labels" [] b.sn.Hosts.labels
  | Ok ns -> Alcotest.failf "expected 2 nodes, got %d" (List.length ns)

let test_ssh_nodes_refuses_shared_host () =
  let text = replace ~sub:{|hosts = ["root@web-2"]|} ~by:{|hosts = ["root@web-1"]|} ssh_topology_text in
  let layout = Host_layout.make "app" in
  (match Reconcile.ssh_nodes ~layout ~pubkey:"" ~records:[] (ssh_topology ~text ()) with
   | Error m -> Alcotest.(check bool) ("names both pools: " ^ m) true (contains m "pools a and b")
   | Ok _ -> Alcotest.fail "two pools on one host must be refused");
  let text = {|
[roles]
"Echo.Server" = { body = "App.serve" }
[pool.a]
serves = ["Echo.Server"]
|} in
  match Reconcile.ssh_nodes ~layout ~pubkey:"" ~records:[] (ssh_topology ~text ()) with
  | Error m -> Alcotest.(check bool) m true (contains m "no hosts")
  | Ok _ -> Alcotest.fail "a topology without hosts has no ssh nodes"

let test_host_records_round_trip () =
  let root = tmp_root () in
  let rs = [ record ~host:"root@web-1" ~pool:"a" "linux/amd64"; record ~host:"root@web-2" ~pool:"b" "linux/arm64" ] in
  Reconcile.write_host_records ~root (Some "prod") rs;
  (match Reconcile.read_host_records ~root (Some "prod") with
   | Ok back -> Alcotest.(check (list string)) "targets" [ "linux/amd64"; "linux/arm64" ]
                  (List.map (fun r -> r.Reconcile.hr_target) back)
   | Error m -> Alcotest.fail m);
  Alcotest.(check bool) "another env has none" true (Reconcile.read_host_records ~root (Some "dev") = Ok [])

(** A fake current reload server (HCR_INFO, VERSIONS_DETAIL with RESTORED,
    PINS, COMPACT, GET_EPOCH, PING and the signed TOPOLOGY verb, which it
    checks against [pk] like the real one). Serves [conns] connections;
    appends every command line, and each accepted topology body, to [log]. *)
let fake_hcr_server ?(conns = 1) ~pk ~log path =
  (try Sys.remove path with Sys_error _ -> ());
  let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Unix.bind fd (Unix.ADDR_UNIX path);
  Unix.listen fd 4;
  match Unix.fork () with
  | 0 ->
    let note s = Out_channel.with_open_gen [ Open_append; Open_creat; Open_wronly ] 0o644 log
        (fun oc -> output_string oc (s ^ "\n")) in
    for _ = 1 to conns do
      let (c, _) = Unix.accept fd in
      let ic = Unix.in_channel_of_descr c and oc = Unix.out_channel_of_descr c in
      let say s = output_string oc s; flush oc in
      (try
         while true do
           let line = input_line ic in
           note line;
           match String.split_on_char ' ' line with
           | [ "HCR_INFO" ] ->
             say "HCR_INFO target:linux/arm64 abi:march-hcr-v2;triple=aarch64-unknown-linux-gnu;ptr=8 prefix:App key:00\n"
           | [ "VERSIONS_DETAIL" ] ->
             say "SLOT 0 App.f abc123 0 (none) 0\nSLOT 1 App.g def456 1700000000000 ab12 2\n\
                  RESTORED entries:2 skipped:1 mode:replayed stack:2 manifest:aaaa topology:-\nEND\n"
           | [ "PINS" ] -> say "EPOCH 2 pins:1 current\nCOUNTERS deferred:0 converted:0 dropped:0 killed:0\nEND\n"
           | [ "COMPACT" ] -> say "STACK entries:2 functions:2 deploys:1 artifacts:1 cas_bytes:2048\n"
           | [ "GET_EPOCH" ] -> say "EPOCH 7\n"
           | [ "PING" ] -> say "PONG\n"
           | [ "VERSIONS" ] | [ "ABI_QUERY" ] -> say "END\n"
           | [ "TOPOLOGY"; digest; sig64; size ] ->
             let signed = "TOPOLOGY " ^ digest in
             let ok_sig =
               match Cmd_hot_reload.b64_decode_raw sig64 with
               | Some sg when Bytes.length sg >= 64 ->
                 March_ed25519.Ed25519.verify (Bytes.of_string signed) (Bytes.sub sg 0 64) pk
               | _ -> false
             in
             if not ok_sig then say "ERR bad_signature\n"
             else begin
               say "READY\n";
               let body = really_input_string ic (int_of_string size) in
               if March_cas.Blake3.hash_string body <> digest then say "ERR digest_mismatch\n"
               else (note ("BODY " ^ string_of_int (String.length body)); say ("OK " ^ digest ^ "\n"))
             end
           | _ -> say "ERR unknown_command\n"
         done
       with End_of_file -> ());
      Unix.close c
    done;
    Unix._exit 0
  | p -> Unix.close fd; p

(** Kill [pids] (fake servers) when [f] returns or fails: a failed check
    must not leave a server blocked in accept, holding the test's stdout. *)
let reaping pids f =
  Fun.protect f ~finally:(fun () ->
      List.iter (fun p ->
          (try Unix.kill p Sys.sigkill with Unix.Unix_error _ -> ());
          (try ignore (Unix.waitpid [] p) with Unix.Unix_error _ -> ()))
        pids)

(** A stand-in for systemctl: logs its arguments; [is-active] says active. *)
let fake_service_ctl dir =
  let path = Filename.concat dir "fake-systemctl" in
  write_file path (Printf.sprintf "#!/bin/sh\necho \"$@\" >> %s/systemctl.log\n\
                                   case \"$1\" in is-active) echo active ;; esac\nexit 0\n" dir);
  Unix.chmod path 0o755;
  path

let short_tmp () =
  let d = Printf.sprintf "/tmp/frs%d_%d" (Unix.getpid ()) (Random.int 100000) in
  Unix.mkdir d 0o755; d

let test_ssh_push_and_status () =
  let dir = short_tmp () in
  let layout = Host_layout.make ~prefix:dir "app" in
  Reconcile.mkdir_p (Host_layout.run_dir layout);
  Reconcile.mkdir_p (Host_layout.etc_dir layout);
  let (pk, sk) = March_ed25519.Ed25519.keygen () in
  let t = ssh_topology () in
  let nodes = match Reconcile.ssh_nodes ~layout ~pubkey:"" ~records:[] t with
    | Ok ns -> ns | Error m -> Alcotest.fail m in
  let log_a = Filename.concat dir "a.log" and log_b = Filename.concat dir "b.log" in
  (* a reports; b has not reported yet. *)
  write_file (Host_layout.status_file layout "a") "node a-web-1\ntopology compiled\noffers Echo.Server\ndraining 0\nrunning 3\n";
  let sa = fake_hcr_server ~conns:3 ~pk ~log:log_a (Host_layout.socket layout "a") in
  let sb = fake_hcr_server ~conns:1 ~pk ~log:log_b (Host_layout.socket layout "b") in
  let sctl = fake_service_ctl dir in
  reaping [ sa; sb ] @@ fun () ->
  let b = Reconcile.ssh ~transport:Remote.local ~service_ctl:sctl ~layout ~sk nodes in
  (match b.push_topology t with
   | Error m -> Alcotest.fail m
   | Ok r ->
     Alcotest.(check bool) "a signalled" true (List.assoc "a-web-1" r.outcome = Reconcile.Signalled);
     Alcotest.(check bool) "b not reporting: not signalled" true (List.assoc "b-web-2" r.outcome = Reconcile.Not_reporting);
     Alcotest.(check string) "the digest file is the topology" (Topology.digest_text t)
       (read_file (Host_layout.topology_file layout));
     Alcotest.(check string) "sha of what nodes will report"
       Digestif.SHA256.(to_hex (digest_string (Topology.digest_text t))) r.sha);
  let calls = read_file (Filename.concat dir "systemctl.log") in
  Alcotest.(check bool) ("SIGHUP to a's unit: " ^ calls) true (contains calls "kill --signal=HUP march-a.service");
  Alcotest.(check bool) "no SIGHUP to b" false (contains calls "march-b.service");
  Alcotest.(check bool) "a's server verified and stored the body" true (contains (read_file log_a) "BODY ");
  Alcotest.(check bool) "b's server got the signed push too" true (contains (read_file log_b) "BODY ");
  (* A push signed with another key is refused by the server: the digest file
     is not rewritten and nothing is signalled. *)
  let (_, other_sk) = March_ed25519.Ed25519.keygen () in
  write_file (Host_layout.topology_file layout) "old\n";
  let bad = Reconcile.ssh ~transport:Remote.local ~service_ctl:sctl ~layout ~sk:other_sk [ List.hd nodes ] in
  (match bad.push_topology t with
   | Ok r ->
     (match List.assoc "a-web-1" r.outcome with
      | Reconcile.Push_failed m -> Alcotest.(check bool) m true (contains m "bad_signature")
      | _ -> Alcotest.fail "a push with the wrong key must fail")
   | Error m -> Alcotest.fail m);
  Alcotest.(check string) "digest file untouched" "old\n" (read_file (Host_layout.topology_file layout));
  (* status: liveness from the unit, the report, and the reload server. *)
  let ss = (Reconcile.ssh ~transport:Remote.local ~service_ctl:sctl ~layout ~sk [ List.hd nodes ]).status () in
  (match ss with
   | [ s ] ->
     Alcotest.(check bool) "up" true s.up;
     Alcotest.(check (option int)) "running sessions" (Some 3) (Option.map (fun r -> r.Reconcile.r_running) s.report);
     (match s.reload with
      | Some (Ok ri) ->
        Alcotest.(check int) "slots" 2 (List.length ri.versions);
        Alcotest.(check (option string)) "restored mode" (Some "replayed")
          (Option.map (fun r -> r.Reconcile.rs_mode) ri.restored);
        Alcotest.(check (option int)) "stack" (Some 2)
          (Option.map (fun st -> st.Cmd_deploy_hot.st_entries) ri.compact);
        Alcotest.(check (option string)) "target" (Some "linux/arm64")
          (Option.map (fun h -> h.Cmd_deploy_hot.target) ri.hcr);
        let text = Reconcile.render_status ss in
        List.iter (fun w -> if not (contains text w) then Alcotest.failf "expected %S in:\n%s" w text)
          [ "a-web-1 (pool a, host root@web-1, port 7950)"; "restored at start: 2 patch entries (1 skipped), mode replayed";
            "patch stack: 2 persisted patches"; "(target linux/arm64)" ]
      | Some (Error m) -> Alcotest.failf "reload: %s" m
      | None -> Alcotest.fail "no reload info")
   | _ -> Alcotest.fail "one status expected")

let test_shared_epoch_and_ping () =
  let dir = short_tmp () in
  let (pk, _) = March_ed25519.Ed25519.keygen () in
  let sock = Filename.concat dir "e.sock" in
  let server = fake_hcr_server ~conns:2 ~pk ~log:(Filename.concat dir "e.log") sock in
  reaping [ server ] @@ fun () ->
  let h = { Hosts.name = "n"; ssh = ""; socket = sock; pubkey = ""; labels = [] } in
  Alcotest.(check int) "one host: no shared epoch" 0 (Reconcile.shared_epoch ~transport:Remote.local [ h ]);
  Alcotest.(check int) "fetched once from the first host" 7 (Reconcile.shared_epoch ~transport:Remote.local [ h; h ]);
  Alcotest.(check bool) "PING" true (Reconcile.ping ~transport:Remote.local h);
  (try ignore (Unix.waitpid [] server) with Unix.Unix_error _ -> ());
  Alcotest.(check bool) "no server: not alive" false (Reconcile.ping ~transport:Remote.local h)

(** A reload socket whose peer closes at once (what an ssh tunnel does
    while the remote server is not listening yet): the health gate's PING
    must see "not up", not die of SIGPIPE (CI, a restarted node). *)
let test_ping_closed_peer () =
  let dir = short_tmp () in
  let sock = Filename.concat dir "c.sock" in
  let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Unix.bind fd (Unix.ADDR_UNIX sock);
  Unix.listen fd 4;
  let server = match Unix.fork () with
    | 0 -> for _ = 1 to 3 do let (c, _) = Unix.accept fd in Unix.close c done; Unix._exit 0
    | p -> Unix.close fd; p in
  reaping [ server ] @@ fun () ->
  let h = { Hosts.name = "n"; ssh = ""; socket = sock; pubkey = ""; labels = [] } in
  Alcotest.(check bool) "a closed peer is not up" false (Reconcile.ping ~transport:Remote.local h);
  (* The write after the peer has gone: EPIPE, an Error, not a dead forge. *)
  for _ = 1 to 2 do
    match Remote.local.with_socket h (fun conn ->
        Unix.sleepf 0.3;
        Cmd_deploy_hot.send_line conn "PING";
        Cmd_deploy_hot.send_line conn "PING";
        Ok (Cmd_deploy_hot.recv_line conn)) with
    | Error _ -> ()
    | Ok r -> Alcotest.failf "a closed peer answered %S" r
  done

let test_drift () =
  let fm name h = { Cmd_deploy_hot.fn_name = name; fn_impl_hash = h; fn_sig_hash = ""; fn_callers = [];
                    fn_caps = []; fn_has_caps = true } in
  let desired = { Cmd_deploy_hot.version = 2; cas_hash = "c"; target = None; hcr_abi = None; module_prefix = None;
                  functions = [ fm "App.f" "abc123"; fm "App.g" "zzz"; fm "App.new" "n" ]; roles = [] } in
  let slot name h = { Cmd_deploy_hot.ds_id = 0; ds_name = name; ds_impl_hash = h; ds_activated_at = 0L;
                      ds_signer = ""; ds_epoch = 0 } in
  Alcotest.(check (list string)) "only App.g differs"
    [ "App.g" ] (Reconcile.drift ~desired [ slot "App.f" "abc123"; slot "App.g" "def456"; slot "App.other" "q" ])

(** [forge topology apply --env prod] over the ssh backend, on a small
    project: refused before anything was deployed; a capacity change is
    pushed (signed) and applied by the nodes (a fake systemctl plays the
    node: on SIGHUP it reports the sha of the digest file); a label change
    needs a restart and is refused, naming `forge deploy`. *)
let test_ssh_apply () =
  let dir = short_tmp () in
  let root = Filename.concat dir "proj" in
  Reconcile.mkdir_p (Filename.concat root "src");
  write_file (Filename.concat root "forge.toml") "[package]\nname = \"app\"\nversion = \"0.1.0\"\n";
  write_file (Filename.concat root "src/app.march")
    "mod App do\n  protocol Echo do\n    ask: Client -> Server : Int\n    answer: Server -> Client : Int\n  end\n\
    \  fn serve(x) do x end\nend\n";
  let base cap = Printf.sprintf "[roles]\n\"Echo.Server\" = { body = \"App.serve\", capacity = %d }\n\n[pool.a]\nserves = [\"Echo.Server\"]\n" cap in
  write_file (Filename.concat root "topology.toml") (base 4);
  let overlay labels =
    Printf.sprintf "[pool.a]\nhosts = [{ host = \"root@web-1\", labels = [%s] }]\n\n[backend]\nkind = \"ssh\"\n" labels in
  write_file (Filename.concat root "topology.prod.toml") (overlay "\"x\"");
  let home = Filename.concat dir "home" in
  Reconcile.mkdir_p home;
  let old_home = Sys.getenv_opt "HOME" in
  Unix.putenv "HOME" home;
  Fun.protect ~finally:(fun () -> Option.iter (Unix.putenv "HOME") old_home) @@ fun () ->
  let (pk, sk) = March_ed25519.Ed25519.keygen () in
  (match Cmd_hot_reload.save_sk sk with Ok () -> () | Error m -> Alcotest.fail m);
  let layout = Host_layout.make ~prefix:dir "app" in
  Reconcile.mkdir_p (Host_layout.run_dir layout);
  Reconcile.mkdir_p (Host_layout.etc_dir layout);
  let status = Host_layout.status_file layout "a" in
  write_file status "node a-web-1\ntopology compiled\noffers Echo.Server\ndraining 0\nrunning 0\n";
  let sctl = Filename.concat dir "fake-systemctl" in
  write_file sctl (Printf.sprintf
                     "#!/bin/sh\necho \"$@\" >> %s/systemctl.log\n\
                      case \"$1\" in\n  is-active) echo active ;;\n\
                     \  kill) sha=$(sha256sum < %s | cut -d' ' -f1)\n\
                     \        printf 'node a-web-1\\ntopology %%s\\noffers Echo.Server\\ndraining 0\\nrunning 0\\n' \"$sha\" > %s ;;\n\
                      esac\nexit 0\n" dir (Host_layout.topology_file layout) status);
  Unix.chmod sctl 0o755;
  let server = fake_hcr_server ~conns:1000 ~pk ~log:(Filename.concat dir "a.log") (Host_layout.socket layout "a") in
  reaping [ server ] @@ fun () ->
  let apply () = Reconcile.apply ~transport:Remote.local ~service_ctl:sctl ~layout_prefix:dir ~env:"prod" ~root () in
  (match apply () with
   | Error m -> Alcotest.(check bool) ("nothing deployed yet: " ^ m) true (contains m "run `forge deploy --env prod` first")
   | Ok r -> Alcotest.failf "apply before any deploy succeeded:\n%s" r);
  (* What the last deploy pushed: capacity 4. *)
  (match Topology.load ~root ~env:"prod" () with
   | Ok t -> Reconcile.record_deployed_topology ~root (Some "prod") t
   | Error _ -> Alcotest.fail "fixture topology");
  write_file (Filename.concat root "topology.toml") (base 2);
  (match apply () with
   | Ok r ->
     List.iter (fun w -> if not (contains r w) then Alcotest.failf "expected %S in:\n%s" w r)
       [ "capacity 4 -> 2"; "pushed "; "to 1 node(s)"; "a-web-1 (pool a, host root@web-1" ]
   | Error m -> Alcotest.failf "apply failed:\n%s" m);
  Alcotest.(check bool) "the server received the signed topology" true
    (contains (read_file (Filename.concat dir "a.log")) "BODY ");
  (match Topology.read_digest (Reconcile.deployed_topology_file ~root (Some "prod")) with
   | Ok t -> Alcotest.(check (option int)) "recorded as deployed" (Some 2)
               (List.hd t.Topology.roles).Topology.capacity
   | Error m -> Alcotest.fail m);
  (match apply () with
   | Ok r -> Alcotest.(check bool) r true (contains r "already has this topology")
   | Error m -> Alcotest.failf "second apply: %s" m);
  write_file (Filename.concat root "topology.prod.toml") (overlay "\"x\", \"y\"");
  match apply () with
  | Error m -> Alcotest.(check bool) m true (contains m "run `forge deploy --env prod`, which rebuilds and restarts")
  | Ok r -> Alcotest.failf "a label change was applied without a restart:\n%s" r

(* ── target identity (#606) ─────────────────────────────────────────────── *)

let v2 ?(target = "linux/arm64") ?(abi = "march-hcr-v2;triple=aarch64-unknown-linux-gnu;ptr=8") ?(prefix = "App") () =
  { Cmd_deploy_hot.version = 2; cas_hash = "c"; target = Some target; hcr_abi = Some abi;
    module_prefix = Some prefix; functions = []; roles = [] }

let info = { Cmd_deploy_hot.target = "linux/arm64"; abi = "march-hcr-v2;triple=aarch64-unknown-linux-gnu;ptr=8";
             prefix = "App"; key_hex = "00" }

let test_identity_checks () =
  let ok r = Alcotest.(check bool) "accepted" true (Result.is_ok r) in
  let bad what r = match r with
    | Error m -> Alcotest.(check bool) (what ^ ": " ^ m) true (contains m what)
    | Ok () -> Alcotest.failf "%s mismatch accepted" what in
  ok (Cmd_deploy_hot.check_identity ~manifest:(v2 ()) ~info);
  (* what a real server answers: the triple quoted (march_reload.c) *)
  ok (Cmd_deploy_hot.check_identity ~manifest:(v2 ())
        ~info:{ info with abi = "march-hcr-v2;triple=\"aarch64-unknown-linux-gnu\";ptr=8" });
  bad "target" (Cmd_deploy_hot.check_identity ~manifest:(v2 ~target:"linux/amd64" ()) ~info);
  bad "HCR ABI" (Cmd_deploy_hot.check_identity ~manifest:(v2 ~abi:"march-hcr-v3;triple=x;ptr=8" ()) ~info);
  bad "module prefix" (Cmd_deploy_hot.check_identity ~manifest:(v2 ~prefix:"Other" ()) ~info);
  ok (Cmd_deploy_hot.check_identity ~manifest:{ (v2 ~target:"x" ()) with version = 1 } ~info);
  ok (Cmd_deploy_hot.check_host_target ~recorded:"linux/arm64" ~manifest:(v2 ()));
  bad "linux/amd64" (Cmd_deploy_hot.check_host_target ~recorded:"linux/arm64" ~manifest:(v2 ~target:"linux/amd64" ()));
  ok (Cmd_deploy_hot.check_host_target ~recorded:"linux/arm64"
        ~manifest:(v2 ~target:"native" ~abi:"march-hcr-v2;triple=aarch64-unknown-linux-gnu;ptr=8" ()));
  bad "built for this machine" (Cmd_deploy_hot.check_host_target ~recorded:"linux/amd64"
        ~manifest:(v2 ~target:"native" ~abi:"march-hcr-v2;triple=arm64-apple-macosx15.0.0;ptr=8" ()));
  Alcotest.(check (option string)) "uname" (Some "linux/amd64") (Cmd_deploy_hot.canonical_of_triple "Linux x86_64");
  Alcotest.(check (option string)) "triple" (Some "linux/arm64") (Cmd_deploy_hot.canonical_of_triple "aarch64-unknown-linux-gnu");
  Alcotest.(check (option string)) "unknown" None (Cmd_deploy_hot.canonical_of_triple "riscv64 Linux")

let test_manifest_reads_hcr_abi () =
  let root = tmp_root () in
  let path = Filename.concat root "m" in
  write_file path "# march-hcr-manifest v2\n# cas_hash cc\n# target linux/arm64\n\
                   # hcr_abi march-hcr-v2;triple=aarch64-unknown-linux-gnu;ptr=8\n# module_prefix App\nApp.f aa bb caps=\n";
  match Cmd_deploy_hot.parse_manifest path with
  | Ok m ->
    Alcotest.(check (option string)) "hcr_abi (was never read)" (Some "march-hcr-v2;triple=aarch64-unknown-linux-gnu;ptr=8") m.hcr_abi;
    Alcotest.(check (option string)) "target" (Some "linux/arm64") m.target;
    Alcotest.(check (option string)) "prefix" (Some "App") m.module_prefix
  | Error e -> Alcotest.fail e

(** [forge deploy hot]'s [run] refuses a patch for another target before it
    uploads anything: the server sees HCR_INFO and nothing else. *)
let test_run_preflights_identity () =
  let dir = short_tmp () in
  let (pk, sk) = March_ed25519.Ed25519.keygen () in
  let sock = Filename.concat dir "r.sock" and log = Filename.concat dir "r.log" in
  let server = fake_hcr_server ~pk ~log sock in
  reaping [ server ] @@ fun () ->
  let r = Cmd_deploy_hot.run ~tunnel:false ~ssh_host:"n" ~remote_socket:sock ~signing_pubkey:"" ~sk
      ~manifest:(v2 ~target:"linux/amd64" ~abi:"march-hcr-v2;triple=x86_64-unknown-linux-gnu;ptr=8" ())
      ~so_path:"/nonexistent.so" () in
  (try ignore (Unix.waitpid [] server) with Unix.Unix_error _ -> ());
  (match r with
   | Error m -> Alcotest.(check bool) m true (contains m "target (linux/amd64) is not the running server's (linux/arm64)")
   | Ok _ -> Alcotest.fail "a patch for another target was deployed");
  Alcotest.(check string) "only HCR_INFO reached the server" "HCR_INFO\n" (read_file log)

let () =
  Alcotest.run "reconcile" [
    ("diff", [
        Alcotest.test_case "placement, capacity and a dropped role apply without a restart" `Quick test_diff_placement_only;
        Alcotest.test_case "bindings, served roles, hooks, labels, pools and roles need a restart" `Quick test_diff_needs_restart;
      ]);
    ("state", [
        Alcotest.test_case "state.json round trip; a dead run is no run" `Quick test_state_round_trip;
        Alcotest.test_case "the local backend needs a running cluster" `Quick test_local_backend_needs_a_run;
      ]);
    ("lock", [ Alcotest.test_case "one writer at a time; released on exit or death" `Quick test_lock_single_writer ]);
    ("push", [ Alcotest.test_case "writes the digest, SIGHUPs reporting nodes only" `Quick test_push_signals_reporting_nodes ]);
    ("status", [
        Alcotest.test_case "reports and the reload server's VERSIONS_DETAIL/PINS" `Quick test_status_reads_reports_and_reload_server;
        Alcotest.test_case "report parsing" `Quick test_parse_report;
        Alcotest.test_case "reload socket paths fit sun_path" `Quick test_socket_path_short;
      ]);
    ("ssh backend", [
        Alcotest.test_case "nodes from the overlay: names, labels, sockets, recorded targets" `Quick test_ssh_nodes_from_overlay;
        Alcotest.test_case "one pool per host; hosts required" `Quick test_ssh_nodes_refuses_shared_host;
        Alcotest.test_case "host records round trip per env" `Quick test_host_records_round_trip;
        Alcotest.test_case "push: signed TOPOLOGY, digest file, SIGHUP to reporting units; wrong key refused" `Quick test_ssh_push_and_status;
        Alcotest.test_case "shared epoch fetched once; PING" `Quick test_shared_epoch_and_ping;
        Alcotest.test_case "drift against the deployed manifest" `Quick test_drift;
        Alcotest.test_case "PING to a peer that closes: not up, no SIGPIPE" `Quick test_ping_closed_peer;
        Alcotest.test_case "topology apply over ssh: refuses before a deploy, pushes, refuses restarts" `Quick test_ssh_apply;
      ]);
    ("identity (#606)", [
        Alcotest.test_case "manifest vs HCR_INFO, host target vs manifest" `Quick test_identity_checks;
        Alcotest.test_case "# hcr_abi is parsed" `Quick test_manifest_reads_hcr_abi;
        Alcotest.test_case "deploy hot refuses another target before uploading" `Quick test_run_preflights_identity;
      ]);
  ]
