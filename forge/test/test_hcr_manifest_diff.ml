(** The hot-reload manifest of a one-line edit flags exactly the edited
    function (2026-10-01; specs/progress/2026-10-01-hcr-topology-app-functions-no-dispatch-slots.md
    and specs/progress/2026-10-01-hcr-entry-module-top-level-fns-outside-boundary.md).

    Each case compiles a project's hot-reload patch twice, as forge does
    (`march --compile --compile-so --hot-reload <Entry> --topology ...`),
    once as committed and once with a one-line edit, and diffs the two
    `.hcr_manifest`s with forge's own [Deploy_plan.fn_diff]. Names made from
    the compiler's global counters (`$lam<n>...`, `$jp<n>`) may come and go;
    of the rest, only the edited function (and the slot that carries it) may
    change, and every changed function must be deliverable by a slot that
    changed too ([Deploy_plan.undeliverable]), or `forge deploy` plans a
    restart.

    - examples/topology_app, a handler edit (`state.total + n` -> `+ n + 1`):
      before the fix every function that merely referenced a renumbered
      lambda changed too (`Front.start`, `Front.run`, `main`, ...), and an
      unslotted `main` changing made every deploy a restart.
    - examples/topology_app, an edit inside `Back.serve_one`'s closure: the
      lifted lambda has no slot and is never called by name; the manifest
      names the slot that builds it as its caller.
    - fixtures/upgrade/entry_v1 (the role body at the top of the entry
      module): an edit to the top-level `nested`.

    Hermetic like test_upgrade_from.ml: the just-built march, an empty
    MARCH_HOME, a private HOME, the staged runtime and stdlib. *)

open March_forge

let getenv_abs v =
  match Sys.getenv_opt v with
  | None | Some "" ->
    Printf.eprintf "test_hcr_manifest_diff: %s is not set (see forge/test/dune)\n" v;
    exit 2
  | Some p -> if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p

let read_file path = try In_channel.with_open_bin path In_channel.input_all with Sys_error _ -> ""
let write_file path s = Out_channel.with_open_bin path (fun oc -> output_string oc s)

let sh cmd =
  let rc = Sys.command cmd in
  if rc <> 0 then Alcotest.failf "`%s` exited %d" cmd rc

let env = lazy (
  let march = getenv_abs "MARCH_TEST_BIN" in
  let runtime = getenv_abs "MARCH_TEST_RUNTIME_DIR" and stdlib = getenv_abs "MARCH_TEST_STDLIB_DIR" in
  Printf.sprintf "env HOME=%s MARCH_HOME=%s MARCH_RUNTIME_DIR=%s MARCH_STDLIB=%s %s"
    (Filename.quote (Filename.temp_dir "hcr_md_home_" "")) (Filename.quote (Filename.temp_dir "hcr_md_mh_" ""))
    (Filename.quote runtime) (Filename.quote stdlib) (Filename.quote march))

(** A writable copy of [srcs] (directories copied over each other in
    order), with its topology digest written the way forge writes it. *)
let project srcs =
  let dir = Filename.temp_dir "hcr_md_" "" in
  List.iter (fun s -> sh (Printf.sprintf "cp -R %s/. %s && chmod -R u+w %s" (Filename.quote s) (Filename.quote dir) (Filename.quote dir))) srcs;
  sh (Printf.sprintf "rm -rf %s/.forge %s/.march" (Filename.quote dir) (Filename.quote dir));
  (match Topology.load ~root:dir () with
   | Ok t -> ignore (Topology.write_digest ~root:dir t)
   | Error _ -> Alcotest.failf "%s: the topology does not load" dir);
  dir

(** Compile [dir]'s patch (fresh working directory, so no artifact cache is
    shared between versions) and parse its manifest. *)
let manifest ~entry_module dir label =
  let src = Filename.concat dir "src" in
  let entry = match Sys.readdir src |> Array.to_list |> List.filter (fun f -> Filename.check_suffix f ".march") with
    | [ f ] -> Filename.concat src f
    | _ -> Alcotest.failf "%s: expected one .march file" src in
  let cwd = Filename.concat dir ("build_" ^ label) in
  Unix.mkdir cwd 0o755;
  let so = Filename.concat cwd "patch.so" and log = Filename.concat cwd "build.log" in
  let rc = Sys.command (Printf.sprintf "cd %s && %s --compile --compile-so --hot-reload %s --topology %s -o %s %s > %s 2>&1"
                          (Filename.quote cwd) (Lazy.force env) entry_module
                          (Filename.quote (Topology.digest_file ~root:dir)) (Filename.quote so) (Filename.quote entry)
                          (Filename.quote log)) in
  if rc <> 0 then Alcotest.failf "the %s patch did not build (exit %d):\n%s" label rc (read_file log);
  match Cmd_deploy_hot.parse_manifest (so ^ ".hcr_manifest") with
  | Ok m -> m
  | Error e -> Alcotest.failf "%s: %s" label e

let edit dir what by =
  let src = Filename.concat dir "src" in
  let f = Filename.concat src (List.find (fun f -> Filename.check_suffix f ".march") (Array.to_list (Sys.readdir src))) in
  let text = read_file f in
  let changed = Str.replace_first (Str.regexp_string what) by text in
  if changed = text then Alcotest.failf "fixture: %S not found in %s" what f;
  write_file f changed

let generated n = String.length n > 0 && n.[0] = '$'

(** Diff [old] and [new_]: the non-generated changed functions must be
    exactly [expect], and every changed function deliverable when [slots]
    are the running base's slots among them. *)
let check what ~old ~new_ ~expect ~slots =
  let d = Deploy_plan.fn_diff (Some old) new_ in
  Printf.printf "%s: changed %s\n%!" what (String.concat ", " d.changed);
  Alcotest.(check (list string)) (what ^ ": the changed functions") expect
    (List.filter (fun n -> not (generated n)) d.changed);
  Alcotest.(check (list string)) (what ^ ": nothing removed but generated names") []
    (List.filter (fun n -> not (generated n)) d.removed);
  Alcotest.(check (list string)) (what ^ ": every change reaches a changed slot") []
    (Deploy_plan.undeliverable ~slots ~changed:d.changed new_)

(* The first compile in an empty HOME runs with a cold ~/.cache/march and
   specializes the stdlib differently (2026-10-01: no
   `Topology.offer_actor_role$...`, two functions more; filed as
   specs/todos/2026-10-01-cold-stdlib-cache-changes-specializations.md), which
   would show here as stdlib functions that "changed". Not what this test is
   about: compile once to warm the cache, and diff only warm builds. *)
let warm = lazy (
  let dir = project [ getenv_abs "TOPOLOGY_APP_DIR" ] in
  ignore (manifest ~entry_module:"TopologyApp" dir "warmup"))

let topology_base = lazy (
  Lazy.force warm;
  let dir = project [ getenv_abs "TOPOLOGY_APP_DIR" ] in
  manifest ~entry_module:"TopologyApp" dir "v1")

let test_topology_handler_edit () =
  let old = Lazy.force topology_base in
  let dir = project [ getenv_abs "TOPOLOGY_APP_DIR" ] in
  edit dir "let t = state.total + n\n" "let t = state.total + n + 1\n";
  check "a handler edit" ~old ~new_:(manifest ~entry_module:"TopologyApp" dir "v2")
    ~expect:[ "CounterActor_Deliver"; "CounterActor_dispatch" ] ~slots:[ "CounterActor_dispatch" ]

let test_topology_closure_edit () =
  let old = Lazy.force topology_base in
  let dir = project [ getenv_abs "TOPOLOGY_APP_DIR" ] in
  edit dir "n * env.factor)))" "n * env.factor + 1)))";
  check "an edit inside Back.serve_one's closure" ~old ~new_:(manifest ~entry_module:"TopologyApp" dir "v2")
    ~expect:[ "Back.serve_one" ] ~slots:[ "Back.serve_one" ]

let test_entry_module_edit () =
  let fx = getenv_abs "UPGRADE_FIXTURES_DIR" in
  Lazy.force warm;
  let srcs = [ Filename.concat fx "v1"; Filename.concat fx "entry_v1" ] in
  let old = manifest ~entry_module:"UpgradeApp" (project srcs) "v1" in
  let dir = project srcs in
  edit dir "\"upgrade v1: a nested session answered \"" "\"upgrade v1.1: a nested session answered \"";
  check "an edit to the entry module's top-level `nested`" ~old ~new_:(manifest ~entry_module:"UpgradeApp" dir "v2")
    ~expect:[ "nested" ] ~slots:[ "nested" ]

let () =
  Alcotest.run "hcr-manifest-diff" [
    ("one-line edit", [
        Alcotest.test_case "topology app: a handler edit flags its handler and dispatch only" `Slow test_topology_handler_edit;
        Alcotest.test_case "topology app: a closure edit flags its slot, the lambda deliverable" `Slow test_topology_closure_edit;
        Alcotest.test_case "entry module: a top-level fn edit flags that fn only" `Slow test_entry_module_edit;
      ]);
  ]
