(** [forge release build] and the generated [bin/<app>] launcher (R9 of
    specs/plans/2026-09-28-observe-recon-shell-plan.md, design section 7.2).

    REAL binaries: the bundle is built by [Cmd_release_build.build] (a native
    compile), the launcher script is run with [sh], and the node it starts is
    queried over its observe socket.  Hermetic like test_entry_rule: the
    just-built compiler plus the staged runtime and stdlib (forge/test/dune).

    Host tools the live cases need: sh, and one of nc -U / socat / python3
    (the launcher's own requirement); shellcheck and zig are optional and
    their cases skip with a message. *)

open March_forge

let setup_hermetic_toolchain () =
  let resolve env_var =
    match Sys.getenv_opt env_var with
    | None | Some "" ->
      Printf.eprintf "test_release_build: %s is not set (see forge/test/dune)\n" env_var;
      exit 2
    | Some rel ->
      if Filename.is_relative rel then Filename.concat (Sys.getcwd ()) rel else rel
  in
  let march_abs = resolve "MARCH_TEST_BIN" in
  let runtime_dir_abs = resolve "MARCH_TEST_RUNTIME_DIR" in
  let stdlib_dir_abs = resolve "MARCH_TEST_STDLIB_DIR" in
  let forge_abs = resolve "FORGE_TEST_BIN" in
  (* The cross sysroot cache lives under the real HOME; keep it reachable
     when HOME is replaced below. *)
  (match Sys.getenv_opt "HOME" with
   | Some h ->
     let sr = Filename.concat h ".cache/march/cross-sysroot/linux-amd64" in
     if Sys.file_exists sr && Sys.getenv_opt "MARCH_CROSS_SYSROOT_AMD64" = None then
       Unix.putenv "MARCH_CROSS_SYSROOT_AMD64" sr
   | None -> ());
  let bindir = Filename.temp_dir "march_hermetic_bin_" "" in
  Unix.symlink march_abs (Filename.concat bindir "march");
  let old_path = Option.value (Sys.getenv_opt "PATH") ~default:"" in
  Unix.putenv "PATH" (bindir ^ ":" ^ old_path);
  Unix.putenv "MARCH_HOME" (Filename.temp_dir "march_hermetic_home_" "");
  Unix.putenv "HOME" (Filename.temp_dir "march_hermetic_userhome_" "");
  Unix.putenv "MARCH_RUNTIME_DIR" runtime_dir_abs;
  Unix.putenv "MARCH_STDLIB" stdlib_dir_abs;
  forge_abs

let forge_exe = lazy (setup_hermetic_toolchain ())

let have cmd = Sys.command (Printf.sprintf "command -v %s >/dev/null 2>&1" cmd) = 0

let contains s sub =
  try ignore (Str.search_forward (Str.regexp_string sub) s 0); true with Not_found -> false

let write_file path content =
  let rec mkdir_p d =
    if not (Sys.file_exists d) then (mkdir_p (Filename.dirname d); Unix.mkdir d 0o755)
  in
  mkdir_p (Filename.dirname path);
  Out_channel.with_open_text path (fun oc -> output_string oc content)

let read_file path = In_channel.with_open_bin path In_channel.input_all

(** Run a command, stdout and stderr together; (exit code, output). *)
let run_capture cmd =
  let ic = Unix.open_process_in (cmd ^ " 2>&1") in
  let out = In_channel.input_all ic in
  match Unix.close_process_in ic with
  | Unix.WEXITED n -> (n, String.trim out)
  | _ -> (-1, String.trim out)

let app = "relapp"

let program =
  "mod Relapp do\n  needs IO.Console\n  needs IO.Clock\n  fn main(_c : Cap(IO.Console)) : () do\n    println(\"ready\")\n    sleep_ms(600000)\n  end\nend\n"

let forge_toml ~hot =
  Printf.sprintf "[package]\nname = \"%s\"\nversion = \"0.3.0\"\ntype = \"app\"\n%s" app
    (if hot then
       "\n[hot-reload]\nsocket = \"/tmp/unused.sock\"\nssh_host = \"localhost\"\nmodule_prefix = \"Relapp\"\npublic_key = \"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\"\n"
     else "")

let with_project ?(hot = false) f =
  ignore (Lazy.force forge_exe);
  let root = Unix.realpath (Filename.temp_dir "forge_release_build_" "") in
  write_file (Filename.concat root "forge.toml") (forge_toml ~hot);
  write_file (Filename.concat root "src/relapp.march") program;
  let old = Sys.getcwd () in
  Unix.chdir root;
  Fun.protect
    ~finally:(fun () ->
        Unix.chdir old;
        ignore (Sys.command ("rm -rf " ^ Filename.quote root)))
    (fun () -> f root)

let build_ok ?target ?tar () =
  match Cmd_release_build.build ?target ?tar () with
  | Ok (dir, _) -> dir
  | Error e -> Alcotest.failf "release build: %s" e

let exists_in dir rel = Sys.file_exists (Filename.concat dir rel)

let check_layout ~hot dir =
  List.iter (fun rel ->
      Alcotest.(check bool) (rel ^ " exists") true (exists_in dir rel))
    [ "bin/" ^ app; "lib/" ^ app; "lib/patches"; "etc/env"; "etc/policy";
      "etc/debug_policy"; "etc/shell_policy"; "RELEASE" ];
  Alcotest.(check bool) "launcher is executable" true
    (Unix.access (Filename.concat dir ("bin/" ^ app)) [ Unix.X_OK ] = ());
  Alcotest.(check bool) "hcr_manifest only for hot-reload" hot
    (exists_in dir ("lib/" ^ app ^ ".hcr_manifest"));
  Alcotest.(check bool) "pubkey only for hot-reload" hot (exists_in dir "etc/pubkey");
  let release = read_file (Filename.concat dir "RELEASE") in
  List.iter (fun l -> Alcotest.(check bool) ("RELEASE has " ^ l) true (contains release l))
    [ "name=relapp\n"; "version=0.3.0\n"; "target="; "cas_hash="; "compiler="; "built_at=";
      Printf.sprintf "hot_reload=%b\n" hot ]

(* ── pure pieces ────────────────────────────────────────────────────────── *)

let test_names_and_grace () =
  Alcotest.(check bool) "plain name" true (Release_launcher.valid_app_name "my-app_2.x");
  List.iter (fun n ->
      Alcotest.(check bool) ("rejects " ^ n) false (Release_launcher.valid_app_name n))
    [ ""; "a b"; "a'b"; "a;b"; "$(x)"; "../x"; "-x"; ".x"; "a/b" ];
  let d soft hard = Some { Topology.soft_ms = soft; hard_ms = hard } in
  Alcotest.(check int) "soft deadline" 30 (Cmd_release_build.stop_grace_secs (d (Some 30000) (Some 120000)));
  Alcotest.(check int) "rounds up" 2 (Cmd_release_build.stop_grace_secs (d (Some 1001) None));
  Alcotest.(check int) "hard when no soft" 120 (Cmd_release_build.stop_grace_secs (d None (Some 120000)));
  Alcotest.(check int) "default" 30 (Cmd_release_build.stop_grace_secs None);
  Alcotest.(check string) "linux label" "linux-amd64" (Cmd_release_build.target_label (Some "linux/x86_64"))

let test_launcher_script () =
  let script = Release_launcher.script ~app in
  Alcotest.(check bool) "no template holes" false (contains script "@APP@");
  Alcotest.(check bool) "set -eu" true (contains script "\nset -eu\n");
  Alcotest.(check bool) "never evals" false (contains script "eval \"" || contains script "eval $");
  let path = Filename.temp_file "launcher_" ".sh" in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
      write_file path script;
      let rc, out = run_capture ("sh -n " ^ Filename.quote path) in
      Alcotest.(check int) ("sh -n: " ^ out) 0 rc;
      if have "shellcheck" then begin
        let rc, out = run_capture ("shellcheck -s sh " ^ Filename.quote path) in
        Alcotest.(check int) ("shellcheck: " ^ out) 0 rc
      end else
        print_endline "SKIP shellcheck: not installed");
  Alcotest.check_raises "bad app name refused"
    (Invalid_argument "Release_launcher.script: bad app name a b")
    (fun () -> ignore (Release_launcher.script ~app:"a b"))

(* ── the CLI shape ──────────────────────────────────────────────────────── *)

let test_cli_shape () =
  let forge = Lazy.force forge_exe in
  let rc, out = run_capture (Filename.quote forge ^ " release --help") in
  Alcotest.(check int) "release --help" 0 rc;
  Alcotest.(check bool) "still takes --bump" true (contains out "--bump");
  Alcotest.(check bool) "lists build" true (contains out "build");
  Alcotest.(check bool) "lists tag" true (contains out "tag");
  let rc, out = run_capture (Filename.quote forge ^ " release build --help") in
  Alcotest.(check int) "release build --help" 0 rc;
  List.iter (fun f -> Alcotest.(check bool) f true (contains out f)) [ "--target"; "--profile"; "--tar" ]

(* ── real builds ────────────────────────────────────────────────────────── *)

let launcher dir = Filename.quote (Filename.concat dir ("bin/" ^ app))

(* Short, so the Unix-socket paths fit macOS's 103 bytes. *)
let short_run_dir () = Filename.temp_dir ~temp_dir:"/tmp" "rb" ""

let need_observe_client () =
  have "nc" || have "socat" || have "python3"

let kill_pidfile run =
  let pf = Filename.concat run (app ^ ".pid") in
  if Sys.file_exists pf then
    match int_of_string_opt (String.trim (read_file pf)) with
    | Some pid -> (try Unix.kill pid Sys.sigkill with _ -> ())
    | None -> ()

let test_build_and_run () =
  if not (need_observe_client ()) then print_endline "SKIP live launcher: no nc/socat/python3 on this host"
  else with_project (fun _root ->
      let dir, tarball =
        match Cmd_release_build.build ~tar:true () with
        | Ok r -> r
        | Error e -> Alcotest.failf "release build: %s" e in
      check_layout ~hot:false dir;
      Alcotest.(check (option string)) "tarball written" (Some (dir ^ ".tar.gz")) tarball;
      Alcotest.(check bool) "tarball exists" true (Sys.file_exists (dir ^ ".tar.gz"));
      let rc, listing = run_capture ("tar -tzf " ^ Filename.quote (dir ^ ".tar.gz")) in
      Alcotest.(check int) "tar -t" 0 rc;
      Alcotest.(check bool) "tarball holds the launcher" true
        (contains listing (Filename.basename dir ^ "/bin/" ^ app));
      let run = short_run_dir () in
      let env = Printf.sprintf "MARCH_RUN_DIR=%s MARCH_LOG_DIR=%s " (Filename.quote run) (Filename.quote run) in
      let l = env ^ launcher dir in
      Fun.protect
        ~finally:(fun () ->
            kill_pidfile run;
            ignore (Sys.command ("rm -rf " ^ Filename.quote run)))
        (fun () ->
           let rc, out = run_capture (l ^ " ping") in
           Alcotest.(check bool) ("ping before start fails: " ^ out) true (rc <> 0);
           let rc, out = run_capture (l ^ " daemon") in
           Alcotest.(check int) ("daemon: " ^ out) 0 rc;
           let rc, out = run_capture (l ^ " ping") in
           Alcotest.(check int) ("ping: " ^ out) 0 rc;
           Alcotest.(check string) "ping prints pong" "pong" out;
           let rc, out = run_capture (l ^ " pid") in
           Alcotest.(check int) "pid" 0 rc;
           Alcotest.(check bool) "pid is a number" true (int_of_string_opt out <> None);
           let rc, out = run_capture (l ^ " version") in
           Alcotest.(check int) "version" 0 rc;
           Alcotest.(check bool) ("version shows RELEASE: " ^ out) true (contains out "version=0.3.0");
           Alcotest.(check bool) ("version shows the code epoch: " ^ out) true (contains out "epoch=1");
           let rc, out = run_capture (l ^ " status") in
           Alcotest.(check int) "status" 0 rc;
           Alcotest.(check bool) ("status has EPOCHS: " ^ out) true (contains out "EPOCHS {");
           let rc, out = run_capture (l ^ " daemon") in
           Alcotest.(check bool) ("second daemon refused: " ^ out) true (rc <> 0 && contains out "already running");
           let rc, out = run_capture (l ^ " stop") in
           Alcotest.(check int) ("stop: " ^ out) 0 rc;
           Alcotest.(check bool) ("stop says stopped: " ^ out) true (contains out "stopped pid");
           let rc, _ = run_capture (l ^ " pid") in
           Alcotest.(check bool) "pid after stop fails" true (rc <> 0);
           let rc, out = run_capture (l ^ " ping") in
           Alcotest.(check bool) ("ping after stop fails: " ^ out) true (rc <> 0);
           let rc, out = run_capture (l ^ " stop") in
           Alcotest.(check bool) ("stop is idempotent: " ^ out) true (rc = 0 && contains out "not running");
           (* restart = stop + daemon; leaves it up, then stop again *)
           let rc, out = run_capture (l ^ " restart") in
           Alcotest.(check int) ("restart: " ^ out) 0 rc;
           let rc, out = run_capture (l ^ " ping") in
           Alcotest.(check bool) ("ping after restart: " ^ out) true (rc = 0 && out = "pong");
           let rc, out = run_capture (l ^ " stop") in
           Alcotest.(check int) ("final stop: " ^ out) 0 rc;
           let rc, out = run_capture (l ^ " bogus") in
           Alcotest.(check int) ("unknown verb exits 2: " ^ out) 2 rc;
           let rc, out = run_capture (l ^ " eval 1") in
           Alcotest.(check bool) ("eval says so: " ^ out) true (rc <> 0 && contains out "eval")))

(* A SIGTERM-ignoring node must be killed after the grace, not waited on. *)
let test_stop_escalates_to_sigkill () =
  if not (need_observe_client ()) then print_endline "SKIP: no nc/socat/python3"
  else with_project (fun _root ->
      let dir = build_ok () in
      let run = short_run_dir () in
      (* Replace the node with a script that ignores SIGTERM. *)
      let node = Filename.concat dir ("lib/" ^ app) in
      write_file node "#!/bin/sh\ntrap '' TERM\nwhile :; do sleep 1; done\n";
      Unix.chmod node 0o755;
      let env = Printf.sprintf "MARCH_RUN_DIR=%s MARCH_LOG_DIR=%s MARCH_STOP_GRACE=1 MARCH_START_TIMEOUT=1 "
          (Filename.quote run) (Filename.quote run) in
      let l = env ^ launcher dir in
      Fun.protect
        ~finally:(fun () -> kill_pidfile run; ignore (Sys.command ("rm -rf " ^ Filename.quote run)))
        (fun () ->
           let rc, out = run_capture (l ^ " daemon") in
           Alcotest.(check int) ("daemon: " ^ out) 0 rc;
           let pid = int_of_string (String.trim (snd (run_capture (l ^ " pid")))) in
           let rc, out = run_capture (l ^ " stop") in
           Alcotest.(check int) ("stop: " ^ out) 0 rc;
           Alcotest.(check bool) ("SIGKILL after the grace: " ^ out) true (contains out "SIGKILL");
           Alcotest.(check bool) "process gone" true
             (try Unix.kill pid 0; false with Unix.Unix_error _ -> true)))

let test_hot_reload_sidecars () =
  with_project ~hot:true (fun _root ->
      let dir = build_ok () in
      check_layout ~hot:true dir;
      let manifest = read_file (Filename.concat dir ("lib/" ^ app ^ ".hcr_manifest")) in
      Alcotest.(check bool) "manifest has the cas_hash" true (contains manifest "# cas_hash ");
      let release = read_file (Filename.concat dir "RELEASE") in
      Alcotest.(check bool) "RELEASE cas_hash is the manifest's" false (contains release "cas_hash=-\n");
      let pub = String.trim (read_file (Filename.concat dir "etc/pubkey")) in
      Alcotest.(check string) "pubkey" "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" pub)

let test_cross_linux_amd64 () =
  (* The hermetic setup above points MARCH_CROSS_SYSROOT_AMD64 at the cache
     when it exists.  Without a sysroot, march refuses the cross build, so skip
     locally like a missing zig; CI fetches one, so there a missing sysroot is
     a failure, not a skip. *)
  let have_sysroot =
    Sys.getenv_opt "MARCH_CROSS_SYSROOT_AMD64" <> None || Sys.getenv_opt "MARCH_CROSS_SYSROOT" <> None in
  if not (have "zig") then print_endline "SKIP cross build linux/amd64: zig not installed"
  else if not have_sysroot && Sys.getenv_opt "CI" = None then
    print_endline "SKIP cross build linux/amd64: no linux/amd64 sysroot (scripts/fetch-cross-sysroot.sh amd64)"
  else with_project (fun _root ->
      let dir = build_ok ~target:"linux/amd64" () in
      Alcotest.(check bool) ("directory is per-target: " ^ dir) true (contains dir "-linux-amd64");
      check_layout ~hot:false dir;
      let magic = In_channel.with_open_bin (Filename.concat dir ("lib/" ^ app))
          (fun ic -> really_input_string ic 4) in
      Alcotest.(check string) "lib/<app> is an ELF binary" "\x7fELF" magic;
      Alcotest.(check bool) "RELEASE names the target" true
        (contains (read_file (Filename.concat dir "RELEASE")) "target=linux-amd64\n"))

let tests = [
  Alcotest.test_case "names, grace, labels" `Quick test_names_and_grace;
  Alcotest.test_case "launcher script passes sh -n and shellcheck" `Quick test_launcher_script;
  Alcotest.test_case "forge release / release build CLI" `Quick test_cli_shape;
  Alcotest.test_case "build, daemon, ping, version, stop (real binary)" `Slow test_build_and_run;
  Alcotest.test_case "stop escalates to SIGKILL after the grace" `Slow test_stop_escalates_to_sigkill;
  Alcotest.test_case "hot-reload sidecars" `Slow test_hot_reload_sidecars;
  Alcotest.test_case "cross build linux/amd64" `Slow test_cross_linux_amd64;
]

let () = Alcotest.run "release_build" [ ("release build", tests) ]
