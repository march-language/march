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
    status_path = Reconcile.status_file ~root name; log = Filename.concat root (name ^ ".log") }

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

let () =
  Alcotest.run "reconcile" [
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
  ]
