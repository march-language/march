(** A three-node local cluster under the reconciler (distributed-deploys
    plan, build step 8; D16, D19): forge/test/fixtures/reconcile_app, three
    pools each serving Echo.Server with `place = { count = 1 }`, started by
    `forge run --processes --env dev` (one process per pool, labels a, b, c).

    - SIGKILL the node holding the role: once SWIM declares it dead, another
      node takes it (placement is every node's own decision, no reconciler
      involved).
    - Push a topology that pins the role to a label (`on = "<label>"`): the
      node carrying it opens the offer and the holder drains it, with no
      restart; every live node reports the new digest; the dead node is
      reported as not running. Then a capacity change reopens the offer.
    - `forge topology apply --env dev`: the same through the CLI (one
      reconciliation pass: diff, push, wait, report); a change that needs
      code is refused.

    Hermetic like test_topology_run.ml. Liveness is judged by
    [Unix.kill pid 0] ([Reconcile.alive]), never by a kill's return value. *)

open March_forge

let getenv_abs v =
  match Sys.getenv_opt v with
  | None | Some "" ->
    Printf.eprintf "test_topology_reconcile: %s is not set (see forge/test/dune)\n" v;
    exit 2
  | Some p -> if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p

let read_file path = try In_channel.with_open_bin path In_channel.input_all with Sys_error _ -> ""
let write_file path s = Out_channel.with_open_bin path (fun oc -> output_string oc s)

let contains s sub =
  let n = String.length s and k = String.length sub in
  let rec go i = i + k <= n && (String.sub s i k = sub || go (i + 1)) in
  go 0

let hermetic_env = lazy (
  let march = getenv_abs "MARCH_TEST_BIN" and forge = getenv_abs "FORGE_TEST_BIN" in
  let bin = Filename.temp_dir "reconcile_bin_" "" in
  Unix.symlink march (Filename.concat bin "march");
  Unix.symlink forge (Filename.concat bin "forge");
  [ ("PATH", bin ^ ":" ^ Option.value ~default:"/usr/bin:/bin" (Sys.getenv_opt "PATH"));
    ("MARCH_HOME", Filename.temp_dir "reconcile_mh_" "");
    ("HOME", Filename.temp_dir "reconcile_home_" "");
    ("MARCH_RUNTIME_DIR", getenv_abs "MARCH_TEST_RUNTIME_DIR");
    ("MARCH_STDLIB", getenv_abs "MARCH_TEST_STDLIB_DIR") ])

let environment extra =
  let env = Lazy.force hermetic_env @ extra in
  let keep kv = not (List.exists (fun (k, _) -> String.length kv > String.length k
                                                 && String.sub kv 0 (String.length k + 1) = k ^ "=") env) in
  Array.append (Array.of_list (List.map (fun (k, v) -> k ^ "=" ^ v) env))
    (Array.of_list (List.filter keep (Array.to_list (Unix.environment ()))))

let forge_path () = Filename.concat (List.hd (String.split_on_char ':' (List.assoc "PATH" (Lazy.force hermetic_env)))) "forge"

let fresh_project () =
  let src = getenv_abs "RECONCILE_APP_DIR" in
  let dir = Filename.temp_dir "reconcile_app_" "" in
  let rc = Sys.command (Printf.sprintf "cp -R %s/. %s && rm -rf %s/.forge %s/.march"
                          (Filename.quote src) (Filename.quote dir) (Filename.quote dir) (Filename.quote dir)) in
  if rc <> 0 then Alcotest.failf "could not copy %s" src;
  dir

(** Start forge in [dir], its own process group leader, output to [out]. *)
let spawn_forge ~dir ~out args =
  let env = environment [] in
  match Unix.fork () with
  | 0 ->
    (try
       ignore (Unix.setsid ());
       Unix.chdir dir;
       let fd = Unix.openfile out [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 in
       Unix.dup2 fd Unix.stdout;
       Unix.dup2 fd Unix.stderr;
       Unix.execve (forge_path ()) (Array.of_list ("forge" :: args)) env
     with _ -> Unix._exit 127)
  | pid -> pid

(** Run forge [args] in [dir] to completion; its exit code and output. *)
let run_forge ~dir args =
  let out = Filename.concat dir (Printf.sprintf "forge-%d.out" (Random.bits ())) in
  let pid = spawn_forge ~dir ~out args in
  let (_, st) = Unix.waitpid [] pid in
  ((match st with Unix.WEXITED n -> n | _ -> 255), read_file out)

let wait_exit pid timeout =
  let t0 = Unix.gettimeofday () in
  let rec go () =
    match Unix.waitpid [ Unix.WNOHANG ] pid with
    | (0, _) -> if Unix.gettimeofday () -. t0 > timeout then None else (Unix.sleepf 0.1; go ())
    | (_, st) -> Some st
  in
  go ()

let wait_until ?(timeout = 60.) f =
  let t0 = Unix.gettimeofday () in
  let rec go () = f () || (Unix.gettimeofday () -. t0 < timeout && (Unix.sleepf 0.2; go ())) in
  go ()

let leftovers dir =
  let ic = Unix.open_process_args_in "pgrep" [| "pgrep"; "-f"; dir |] in
  let s = String.trim (In_channel.input_all ic) in
  ignore (Unix.close_process_in ic);
  if s = "" then [] else String.split_on_char '\n' s

(** The recorded run, once every node has reported. *)
let running_state dir =
  let st = ref None in
  let ok = wait_until ~timeout:300. (fun () ->
      match Reconcile.read_state ~root:dir with
      | Ok (Some s) when List.length s.nodes = 3
                        && List.for_all (fun n -> Reconcile.read_report n.Reconcile.status_path <> None) s.nodes ->
        st := Some s; true
      | _ -> false) in
  match !st with
  | Some s when ok -> s
  | _ -> Alcotest.fail "the three nodes never all reported (see forge.out)"

let offers (n : Reconcile.node) =
  match Reconcile.read_report n.status_path with Some r -> r.r_offers | None -> []

let applied (n : Reconcile.node) =
  match Reconcile.read_report n.status_path with Some r -> r.r_topology | None -> ""

(** The live nodes offering Echo.Server. *)
let holders (st : Reconcile.state) =
  List.filter (fun n -> Reconcile.alive n.Reconcile.pid && List.mem "Echo.Server" (offers n)) st.nodes

let exactly_one_holder st =
  let h = ref None in
  if not (wait_until (fun () -> match holders st with [ n ] -> h := Some n; true | _ -> false)) then
    Alcotest.failf "expected exactly one node offering Echo.Server, got [%s]"
      (String.concat ", " (List.map (fun n -> n.Reconcile.name) (holders st)));
  Option.get !h

let set_place dir place =
  let path = Filename.concat dir "topology.toml" in
  let text = read_file path in
  let re = Str.regexp "place = {[^}]*}" in
  write_file path (Str.global_replace re ("place = " ^ place) text)

let set_capacity dir n =
  let path = Filename.concat dir "topology.toml" in
  write_file path (Str.global_replace (Str.regexp "capacity = [0-9]+") (Printf.sprintf "capacity = %d" n) (read_file path))

let label_of (n : Reconcile.node) = n.pool

(** Start the cluster and run [f dir forge_pid out]; always stop it, then
    check forge exited 0 and left nothing running. *)
let with_cluster f =
  let dir = fresh_project () in
  let out = Filename.concat dir "forge.out" in
  let pid = spawn_forge ~dir ~out [ "run"; "--processes"; "--env"; "dev" ] in
  let stop () =
    (try Unix.kill pid Sys.sigint with Unix.Unix_error _ -> ());
    match wait_exit pid 60. with
    | Some st -> st
    | None -> (try Unix.kill (- pid) Sys.sigkill with Unix.Unix_error _ -> ()); ignore (wait_exit pid 5.);
      Alcotest.failf "forge did not exit after SIGINT:\n%s" (read_file out)
  in
  (match f dir out with
   | () -> ()
   | exception e ->
     ignore (stop ());
     Printf.eprintf "--- forge.out ---\n%s\n" (read_file out);
     raise e);
  let _st = stop () in
  Alcotest.(check bool) "state.json removed when forge run ends" false
    (Sys.file_exists (Reconcile.state_file ~root:dir));
  Alcotest.(check (list string)) "no process left running" [] (leftovers dir);
  read_file out

let test_kill_then_push () =
  let out = with_cluster (fun dir out ->
      let st = running_state dir in
      Alcotest.(check (list string)) "state.json names the three nodes" [ "a-1"; "b-1"; "c-1" ]
        (List.map (fun n -> n.Reconcile.name) st.nodes);
      (* count = 1: exactly one node offers. *)
      let x = exactly_one_holder st in
      (* SIGKILL the holder's process group; SWIM declares it dead after its
         suspect timeout, and the next node in the ranking takes the role. *)
      (try Unix.kill (- x.pid) Sys.sigkill with Unix.Unix_error _ -> ());
      if not (wait_until ~timeout:10. (fun () -> not (Reconcile.alive x.pid))) then
        Alcotest.failf "%s survived SIGKILL" x.name;
      let z = exactly_one_holder st in
      Alcotest.(check bool) "the role moved off the killed node" true (z.name <> x.name);
      (* Pin the role to the third node's label and push it: it opens there
         and drains on z, with no restart. *)
      let w = List.find (fun n -> n.Reconcile.name <> x.name && n.Reconcile.name <> z.name) st.nodes in
      set_place dir (Printf.sprintf "{ on = %S, count = 1 }" (label_of w));
      let t = match Topology.load ~root:dir ~env:"dev" () with
        | Ok t -> t
        | Error ds -> Alcotest.failf "reload topology: %s" (String.concat "; " (List.map Topology.render_diag ds)) in
      let (b, _) = match Reconcile.local_backend ~root:dir with Ok b -> b | Error m -> Alcotest.fail m in
      let r = match b.push_topology t with Ok r -> r | Error m -> Alcotest.fail m in
      Alcotest.(check bool) "the killed node is reported not running" true
        (List.assoc x.name r.outcome = Reconcile.Not_running);
      Alcotest.(check bool) "the live nodes were signalled" true
        (List.for_all (fun n -> List.assoc n.Reconcile.name r.outcome = Reconcile.Signalled) [ z; w ]);
      if not (wait_until (fun () -> applied z = r.sha && applied w = r.sha)) then
        Alcotest.failf "the live nodes never reported the pushed digest %s" r.sha;
      let h = exactly_one_holder st in
      Alcotest.(check string) "the role is on the labelled node" w.name h.name;
      List.iter (fun n -> Alcotest.(check bool) (n.Reconcile.name ^ " was not restarted") true (Reconcile.alive n.pid)) [ z; w ];
      (* A capacity change reopens the offer at the new size. *)
      set_capacity dir 2;
      let t2 = match Topology.load ~root:dir ~env:"dev" () with Ok t -> t | Error _ -> Alcotest.fail "reload topology" in
      let r2 = match b.push_topology t2 with Ok r -> r | Error m -> Alcotest.fail m in
      if not (wait_until (fun () -> applied w = r2.sha)) then Alcotest.fail "capacity push never applied";
      if not (wait_until (fun () -> contains (read_file out) (Printf.sprintf "[%s] topology: Echo.Server: capacity 4 -> 2" w.name))) then
        Alcotest.fail "the capacity change was not applied";
      ignore (exactly_one_holder st))
  in
  List.iter (fun s -> if not (contains out s) then Alcotest.failf "expected %S in forge's output:\n%s" s out)
    [ "topology: Echo.Server: placement count 1 -> count 1 on "; "; draining its offer" ]

let test_apply () =
  ignore (with_cluster (fun dir _out ->
      let st = running_state dir in
      let x = exactly_one_holder st in
      let pids = List.map (fun n -> n.Reconcile.pid) st.nodes in
      let y = List.find (fun n -> n.Reconcile.name <> x.name) st.nodes in
      let expect out s = if not (contains out s) then Alcotest.failf "expected %S in:\n%s" s out in
      (* A placement change: one pass pushes it, waits, and reports. *)
      set_place dir (Printf.sprintf "{ on = %S, count = 1 }" (label_of y));
      let (rc, out) = run_forge ~dir [ "topology"; "apply" ] in
      if rc <> 0 then Alcotest.failf "apply failed (%d):\n%s" rc out;
      expect out "1 change(s), none needs a restart:";
      expect out (Printf.sprintf "Echo.Server: placement count 1 -> count 1 on %s" (label_of y));
      expect out "pushed ";
      expect out "to 3 node(s)";
      expect out (Printf.sprintf "%s (pool %s" y.name y.pool);
      let h = exactly_one_holder st in
      Alcotest.(check string) "the role moved to the labelled node" y.name h.name;
      Alcotest.(check (list int)) "no node was restarted" pids
        (List.filter_map (fun n -> if Reconcile.alive n.Reconcile.pid then Some n.Reconcile.pid else None) st.nodes);
      (* The same topology again: nothing to do. *)
      let (rc, out) = run_forge ~dir [ "topology"; "apply" ] in
      if rc <> 0 then Alcotest.failf "second apply failed (%d):\n%s" rc out;
      expect out "already has this topology (no change)";
      (* A change that needs a restart is refused and nothing is pushed. *)
      let before = applied y in
      let overlay = Filename.concat dir "topology.dev.toml" in
      write_file overlay (Str.global_replace (Str.regexp_string {|labels = ["a"]|}) {|labels = ["a", "gpu"]|} (read_file overlay));
      let (rc, out) = run_forge ~dir [ "topology"; "apply" ] in
      Alcotest.(check int) "refused" 1 rc;
      expect out "pool a: hosts";
      expect out "[needs a rebuild and restart]";
      expect out "so nothing was applied";
      Unix.sleepf 1.0;
      Alcotest.(check string) "nothing was pushed" before (applied y)))

let () =
  Random.self_init ();
  Alcotest.run "topology-reconcile" [
    ("placement", [
        Alcotest.test_case "three nodes: a killed holder's role moves; a pushed topology moves it again, no restart" `Slow
          test_kill_then_push;
      ]);
    ("apply", [
        Alcotest.test_case "forge topology apply: one pass moves the role; no change; a restart-only change is refused" `Slow
          test_apply;
      ]);
  ]
