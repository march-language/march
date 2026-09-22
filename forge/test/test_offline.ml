(** `forge --offline` and the registry tarball cache.

    Design: `specs/2026-09-11-forge-offline-and-versioned-dep-cache-design.md`
    §3 (the offline contract), §4 (integrity), §2.4 (tarball cache), with the
    test plan in §6.

    Two layers:
    - in-process unit tests of the choke point ([Net_gate]), the tarball cache
      and the lockfile-state classifier, using [Net_gate.on_permit] as a hook
      that FAILS the test if offline code is ever granted network access;
    - end-to-end tests that run the real, just-built [forge] binary (the dune
      rule passes it as FORGE_TEST_BIN, and the compiler as MARCH_TEST_BIN)
      under a private HOME, with a SENTINEL `git`/`curl`/`npm` first on PATH
      that records its argv and exits 1. A test asserting "no network process
      was started" reads that record, so it proves the property rather than
      inferring it from a successful build. FORGE_REGISTRY points at a port
      nothing listens on, so a registry fetch that slipped through would fail
      rather than reach the internet. *)

open March_forge

(* ------------------------------------------------------------------ helpers *)

let scratch_root =
  lazy (Filename.temp_dir "forge_offline_test_" "")

let fresh_dir tag =
  let d = Filename.concat (Lazy.force scratch_root)
      (Printf.sprintf "%s-%d" tag (Random.bits ())) in
  ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote d)));
  d

let write_file path content =
  ignore (Sys.command (Printf.sprintf "mkdir -p %s"
                         (Filename.quote (Filename.dirname path))));
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc

let read_file path =
  try
    let ic = open_in_bin path in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic; s
  with Sys_error _ -> ""

let contains s sub =
  let n = String.length s and k = String.length sub in
  let rec loop i = i + k <= n && (String.sub s i k = sub || loop (i + 1)) in
  k = 0 || loop 0

let count_occurrences s sub =
  let n = String.length s and k = String.length sub in
  let rec loop i acc =
    if i + k > n then acc
    else if String.sub s i k = sub then loop (i + k) (acc + 1)
    else loop (i + 1) acc
  in loop 0 0

let abs_of_env var =
  match Sys.getenv_opt var with
  | None | Some "" -> None
  | Some p ->
    Some (if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p)

(** The binaries under test. Missing ones are a harness error, not a skip:
    a silently skipped end-to-end suite would pass vacuously. *)
let forge_bin = lazy (match abs_of_env "FORGE_TEST_BIN" with
    | Some p when Sys.file_exists p -> p
    | _ -> prerr_endline "test_offline: FORGE_TEST_BIN not set / missing (see forge/test/dune)"; exit 2)

let march_bin = lazy (match abs_of_env "MARCH_TEST_BIN" with
    | Some p when Sys.file_exists p -> p
    | _ -> prerr_endline "test_offline: MARCH_TEST_BIN not set / missing (see forge/test/dune)"; exit 2)

(** A hermetic environment: private HOME and MARCH_HOME, a bin/ holding the
    compiler under test as `march`, and a sentinel/ directory whose `git`,
    `curl` and `npm` (and optionally `march`) record their argv in [log] and
    fail. *)
type env = { home : string; bin : string; sentinel : string; log : string }

let make_env ?(sentinel_march = false) () =
  let root = fresh_dir "env" in
  let home = Filename.concat root "home" in
  let bin = Filename.concat root "bin" in
  let sentinel = Filename.concat root "sentinel" in
  let log = Filename.concat root "network.log" in
  List.iter (fun d -> ignore (Sys.command ("mkdir -p " ^ Filename.quote d)))
    [ home; bin; sentinel; Filename.concat root "mhome" ];
  if not sentinel_march then
    Unix.symlink (Lazy.force march_bin) (Filename.concat bin "march");
  let tools = [ "git"; "curl"; "npm" ] @ (if sentinel_march then [ "march" ] else []) in
  List.iter (fun t ->
      let p = Filename.concat sentinel t in
      write_file p
        (Printf.sprintf "#!/bin/sh\necho \"%s $*\" >> %s\nexit 1\n" t (Filename.quote log));
      Unix.chmod p 0o755)
    tools;
  { home; bin; sentinel; log }

let base_path = Option.value ~default:"/usr/bin:/bin" (Sys.getenv_opt "PATH")

(** Run forge in [dir]. [~sentinel:true] (the default) puts the sentinel tools
    first on PATH; [false] lets a real `git` through, which is only used to
    POPULATE a cache before switching to offline. *)
let run_forge ?(sentinel = true) ?(extra_env = []) env ~dir args =
  let out = Filename.temp_file "forge_out_" ".txt" in
  let err = Filename.temp_file "forge_err_" ".txt" in
  let path =
    (if sentinel then env.sentinel ^ ":" else "") ^ env.bin ^ ":" ^ base_path in
  let envs =
    [ "HOME", env.home;
      "MARCH_HOME", Filename.concat (Filename.dirname env.home) "mhome";
      "PATH", path;
      "FORGE_REGISTRY", "http://127.0.0.1:9";
      "FORGE_OFFLINE", "" ]
    @ extra_env
  in
  let cmd =
    Printf.sprintf "cd %s && env %s %s %s > %s 2> %s"
      (Filename.quote dir)
      (String.concat " "
         (List.map (fun (k, v) -> Filename.quote (k ^ "=" ^ v)) envs))
      (Filename.quote (Lazy.force forge_bin))
      (String.concat " " (List.map Filename.quote args))
      (Filename.quote out) (Filename.quote err)
  in
  let code = Sys.command cmd in
  let o = read_file out and e = read_file err in
  (try Sys.remove out; Sys.remove err with Sys_error _ -> ());
  (code, o, e)

let network_log env = read_file env.log

let check_no_network env =
  Alcotest.(check string) "no network process was started (sentinel log)" ""
    (network_log env)

let shell_ok fmt =
  Printf.ksprintf (fun cmd ->
      let rc = Sys.command cmd in
      if rc <> 0 then Alcotest.failf "setup command failed (%d): %s" rc cmd)
    fmt

(** A lib-type upstream package named [name] with one module, committed and
    tagged v1.0.0 in a local repository (so "cloning" it needs no network). *)
let make_upstream name ~mod_name =
  let d = fresh_dir ("up-" ^ name) in
  write_file (Filename.concat d "forge.toml")
    (Printf.sprintf "[package]\nname = %S\nversion = \"1.0.0\"\ntype = \"lib\"\n" name);
  write_file (Filename.concat d (Printf.sprintf "lib/%s.march" name))
    (Printf.sprintf "mod %s do\n  fn answer() : Int do\n    42\n  end\nend\n" mod_name);
  shell_ok "cd %s && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init && git tag v1.0.0"
    (Filename.quote d);
  d

(** A lib project named "app" whose single module is [body], with the given
    [deps] lines under [deps]. *)
let make_app ?(deps = []) ~body () =
  let d = fresh_dir "app" in
  write_file (Filename.concat d "forge.toml")
    (Printf.sprintf "[package]\nname = \"app\"\nversion = \"0.1.0\"\ntype = \"lib\"\n\n[deps]\n%s\n"
       (String.concat "\n" deps));
  write_file (Filename.concat d "lib/app.march") body;
  d

let app_using mod_name =
  Printf.sprintf "mod App do\n  fn go() : Int do\n    %s.answer()\n  end\nend\n" mod_name

let app_standalone =
  "mod App do\n  fn go() : Int do\n    1\n  end\nend\n"

(** Warm the cache the real way: `forge deps` with a real git on PATH. *)
let populate env app =
  let (code, o, e) = run_forge ~sentinel:false env ~dir:app [ "deps" ] in
  if code <> 0 then Alcotest.failf "populating forge deps failed:\n%s\n%s" o e

let deps_dir env name = Filename.concat env.home (".march/cas/deps/" ^ name)

(** The single coordinate directory of [name] in [env]'s cache. *)
let only_coord env name =
  match Sys.readdir (deps_dir env name) |> Array.to_list
        |> List.filter (fun n -> n.[0] <> '.') with
  | [ c ] -> Filename.concat (deps_dir env name) c
  | cs -> Alcotest.failf "expected one cached coordinate of %s, found %d" name (List.length cs)

(* ======================================================= in-process: gate *)

let with_gate ~offline f =
  let saved_flag = !Net_gate.flag and saved_hook = !Net_gate.on_permit in
  Net_gate.set_offline offline;
  Fun.protect
    ~finally:(fun () ->
        Net_gate.set_offline saved_flag; Net_gate.on_permit := saved_hook)
    f

let forbid_network () =
  Net_gate.on_permit := (fun what ->
      Alcotest.failf "offline code was granted network access: %s" what)

let test_extract_flag () =
  let got, argv = Net_gate.extract_flag
      [| "forge"; "run"; "--offline"; "x.march"; "--"; "--offline"; "a" |] in
  Alcotest.(check bool) "flag found" true got;
  Alcotest.(check (array string)) "only the forge-side flag is removed"
    [| "forge"; "run"; "x.march"; "--"; "--offline"; "a" |] argv;
  let got, argv = Net_gate.extract_flag [| "forge"; "--offline"; "build" |] in
  Alcotest.(check bool) "leading global position" true got;
  Alcotest.(check (array string)) "stripped" [| "forge"; "build" |] argv;
  let got, _ = Net_gate.extract_flag [| "forge"; "build"; "--"; "--offline" |] in
  Alcotest.(check bool) "after -- is the program's, not forge's" false got

let test_env_var_precedence () =
  let saved = Sys.getenv_opt Net_gate.env_var in
  Fun.protect
    ~finally:(fun () -> Unix.putenv Net_gate.env_var (Option.value ~default:"" saved))
    (fun () ->
       with_gate ~offline:false (fun () ->
           List.iter (fun (v, want) ->
               Unix.putenv Net_gate.env_var v;
               Alcotest.(check bool) (Printf.sprintf "FORGE_OFFLINE=%S" v) want
                 (Net_gate.is_offline ()))
             [ "", false; "0", false; "false", false; "no", false; "off", false;
               "1", true; "true", true; "yes", true ];
           (* The flag only ever adds the restriction: env "0" does not undo it. *)
           Unix.putenv Net_gate.env_var "0";
           Net_gate.set_offline true;
           Alcotest.(check bool) "--offline wins over FORGE_OFFLINE=0" true
             (Net_gate.is_offline ())))

let test_permit_refuses_offline () =
  with_gate ~offline:true (fun () ->
      forbid_network ();
      match Net_gate.permit ~what:"clone thing" ~remedy:"run `forge deps`" with
      | Ok () -> Alcotest.fail "permit granted offline"
      | Error msg ->
        Alcotest.(check bool) "names the operation" true (contains msg "clone thing");
        Alcotest.(check bool) "names the remedy" true (contains msg "forge deps"));
  with_gate ~offline:false (fun () ->
      let seen = ref [] in
      Net_gate.on_permit := (fun w -> seen := w :: !seen);
      ignore (Net_gate.permit ~what:"x" ~remedy:"");
      Alcotest.(check (list string)) "online: permitted and observed" [ "x" ] !seen)

(** The git install path goes through the gate: offline, installing a git dep
    is refused before any process starts, naming the dep and `forge deps`. *)
let test_install_dep_refused_offline () =
  let home = fresh_dir "home" in
  let saved = Sys.getenv_opt "HOME" in
  Unix.putenv "HOME" home;
  Fun.protect ~finally:(fun () -> Unix.putenv "HOME" (Option.value ~default:"" saved))
    (fun () ->
       with_gate ~offline:true (fun () ->
           forbid_network ();
           match Cmd_deps.install_dep "depot"
                   (Project.GitTagDep { url = "https://example.invalid/depot.git"; tag = "v1" })
           with
           | Ok _ -> Alcotest.fail "install_dep succeeded offline"
           | Error msg ->
             Alcotest.(check bool) "names the dep" true (contains msg "`depot`");
             Alcotest.(check bool) "names the populating command" true
               (contains msg "forge deps");
             Alcotest.(check bool) "nothing installed" false
               (Sys.file_exists (Filename.concat home ".march/cas/deps/depot"))))

(** Offline, the registry client is never compiled (a `march --compile` that
    exists only to talk to the registry). *)
let test_registry_client_not_compiled_offline () =
  with_gate ~offline:true (fun () ->
      forbid_network ();
      match Registry_query.compile_client () with
      | Ok _ -> Alcotest.fail "registry client compiled offline"
      | Error msg ->
        Alcotest.(check bool) "refusal says offline" true (contains msg "offline"))

(* ============================================= in-process: tarball cache *)

let with_home f =
  let home = fresh_dir "home" in
  let saved = Sys.getenv_opt "HOME" in
  Unix.putenv "HOME" home;
  Fun.protect ~finally:(fun () -> Unix.putenv "HOME" (Option.value ~default:"" saved))
    (fun () -> f home)

let sha256_hex s = Digestif.SHA256.(to_hex (digest_string s))

let test_tarball_cache_roundtrip () =
  with_home (fun _home ->
      let src = Filename.concat (fresh_dir "tb") "x.tar.gz" in
      write_file src "pretend tarball bytes";
      let cs = sha256_hex "pretend tarball bytes" in
      (match Tarball_cache.lookup cs with
       | Tarball_cache.Miss -> ()
       | _ -> Alcotest.fail "empty cache must miss");
      (match Tarball_cache.store ~checksum:("sha256:" ^ cs) ~src with
       | Error e -> Alcotest.fail e
       | Ok p ->
         Alcotest.(check string) "keyed by checksum"
           (Filename.concat (Tarball_cache.cache_dir ()) (cs ^ ".tar.gz")) p);
      (match Tarball_cache.lookup ("sha256:" ^ cs) with
       | Tarball_cache.Hit p ->
         Alcotest.(check string) "bytes intact" "pretend tarball bytes" (read_file p)
       | _ -> Alcotest.fail "stored entry must hit");
      (* Atomic write: the temp file was renamed, not left behind. *)
      let leftovers =
        Sys.readdir (Tarball_cache.cache_dir ()) |> Array.to_list
        |> List.filter (fun n -> n.[0] = '.') in
      Alcotest.(check (list string)) "no temp files left" [] leftovers)

let test_tarball_cache_refuses_wrong_bytes () =
  with_home (fun _home ->
      let src = Filename.concat (fresh_dir "tb") "x.tar.gz" in
      write_file src "these bytes";
      let wrong = sha256_hex "other bytes" in
      (match Tarball_cache.store ~checksum:wrong ~src with
       | Ok _ -> Alcotest.fail "stored bytes under a checksum they do not hash to"
       | Error _ -> ());
      Alcotest.(check bool) "nothing written" false
        (Sys.file_exists (Filename.concat (Tarball_cache.cache_dir ()) (wrong ^ ".tar.gz"))))

(** A corrupted cache entry is detected on read and never handed out. *)
let test_tarball_cache_detects_corruption () =
  with_home (fun _home ->
      let src = Filename.concat (fresh_dir "tb") "x.tar.gz" in
      write_file src "good bytes";
      let cs = sha256_hex "good bytes" in
      let path = match Tarball_cache.store ~checksum:cs ~src with
        | Ok p -> p | Error e -> Alcotest.fail e in
      write_file path "good bytez";                       (* one byte flipped *)
      (match Tarball_cache.lookup cs with
       | Tarball_cache.Hit _ -> Alcotest.fail "corrupted entry was served"
       | Tarball_cache.Miss -> Alcotest.fail "corruption not reported"
       | Tarball_cache.Corrupt { actual; _ } ->
         Alcotest.(check string) "reports the actual hash" (sha256_hex "good bytez") actual);
      Alcotest.(check bool) "corrupt entry removed" false (Sys.file_exists path))

(* ========================================= in-process: lockfile states *)

(* Verbatim from db_test/forge.lock (design §0.1): forge.toml dependency
   syntax in a file named forge.lock. *)
let malformed_lock_text = "depot = { path = \"../depot\" }\n"

let test_lock_states () =
  let root = fresh_dir "lockstate" in
  Alcotest.(check bool) "absent" true
    (Offline_deps.read_state ~project_root:root ~toml_content:"" = Offline_deps.No_lockfile);
  write_file (Filename.concat root "forge.lock") malformed_lock_text;
  Alcotest.(check bool) "forge.toml syntax is not a lockfile" true
    (Offline_deps.read_state ~project_root:root ~toml_content:"" = Offline_deps.Not_a_lockfile)

(* ================================================= end-to-end (forge exe) *)

(** The load-bearing test (design §6): with a warm cache, an offline build and
    `forge deps --offline` start no network process, and succeed. *)
let test_e2e_warm_cache_no_network () =
  let env = make_env () in
  let up = make_upstream "widget" ~mod_name:"Widget" in
  let app = make_app ~body:(app_using "Widget")
      ~deps:[ Printf.sprintf "widget = { git = %S, tag = \"v1.0.0\" }" ("file://" ^ up) ] () in
  populate env app;
  let (code, o, e) = run_forge env ~dir:app [ "build"; "--offline" ] in
  if code <> 0 then Alcotest.failf "offline build failed:\n%s\n%s" o e;
  let (code, o, e) = run_forge env ~dir:app [ "--offline"; "deps" ] in
  if code <> 0 then Alcotest.failf "forge deps --offline failed:\n%s\n%s" o e;
  Alcotest.(check bool) "reports the dep cached and verified" true
    (contains o "widget: cached" && contains o "verified");
  let (code, _, _) = run_forge env ~dir:app ~extra_env:[ "FORGE_OFFLINE", "1" ] [ "check" ] in
  Alcotest.(check int) "FORGE_OFFLINE=1 check succeeds" 0 code;
  check_no_network env

(** With the cache empty, `forge deps` offline reports the miss and exits
    non-zero — and still clones nothing. *)
let test_e2e_deps_offline_missing () =
  let env = make_env () in
  let up = make_upstream "widget" ~mod_name:"Widget" in
  let app = make_app ~body:app_standalone
      ~deps:[ Printf.sprintf "widget = { git = %S, tag = \"v1.0.0\" }" ("file://" ^ up) ] () in
  populate env app;
  ignore (Sys.command ("rm -rf " ^ Filename.quote (deps_dir env "widget")));
  let (code, o, e) = run_forge env ~dir:app ~extra_env:[ "FORGE_OFFLINE", "1" ] [ "deps" ] in
  (* First: nothing tried to fetch the missing dep. (Online, `forge deps`
     would clone it here, and the sentinel would record the clone.) *)
  check_no_network env;
  Alcotest.(check bool) "non-zero exit" true (code <> 0);
  Alcotest.(check bool) "lists the missing dep" true
    (contains o "widget: MISSING" && contains e "widget");
  let (code, _, _) = run_forge env ~dir:app [ "deps"; "--offline" ] in
  Alcotest.(check bool) "flag form: non-zero exit" true (code <> 0);
  check_no_network env

(** A missing dep that is never imported: the build succeeds, with the
    warning naming the dep. *)
let test_e2e_missing_unimported_warns () =
  let env = make_env () in
  let up = make_upstream "widget" ~mod_name:"Widget" in
  let app = make_app ~body:app_standalone
      ~deps:[ Printf.sprintf "widget = { git = %S, tag = \"v1.0.0\" }" ("file://" ^ up) ] () in
  populate env app;
  ignore (Sys.command ("rm -rf " ^ Filename.quote (deps_dir env "widget")));
  let (code, o, e) = run_forge env ~dir:app [ "build"; "--offline" ] in
  if code <> 0 then Alcotest.failf "build should succeed:\n%s\n%s" o e;
  Alcotest.(check bool) "warning names the dep" true
    (contains e "dependency `widget`" && contains e "not in the local cache");
  Alcotest.(check bool) "warning predicts the module error" true
    (contains e "Unknown module Widget");
  check_no_network env

(** A missing dep that IS imported: the build fails with `Unknown module`,
    and the warning explaining why comes first. Pins the accepted UX. *)
let test_e2e_missing_imported_fails_after_warning () =
  let env = make_env () in
  let up = make_upstream "widget" ~mod_name:"Widget" in
  let app = make_app ~body:(app_using "Widget")
      ~deps:[ Printf.sprintf "widget = { git = %S, tag = \"v1.0.0\" }" ("file://" ^ up) ] () in
  populate env app;
  ignore (Sys.command ("rm -rf " ^ Filename.quote (deps_dir env "widget")));
  let (code, o, e) = run_forge env ~dir:app [ "build"; "--offline" ] in
  let all = e ^ o in
  Alcotest.(check bool) "build fails" true (code <> 0);
  Alcotest.(check bool) "compiler reports the module" true (contains all "Unknown module");
  Alcotest.(check bool) "offline warning is on stderr" true (contains e "offline: dependency `widget`");
  check_no_network env

(** No lockfile: exactly one error for the project, not one per dep. *)
let test_e2e_no_lockfile_one_error () =
  let env = make_env () in
  let app = make_app ~body:app_standalone
      ~deps:[ "alpha = { git = \"https://example.invalid/a.git\", tag = \"v1\" }";
              "beta = { git = \"https://example.invalid/b.git\", tag = \"v1\" }" ] () in
  let (_, _, e) = run_forge env ~dir:app [ "build"; "--offline" ] in
  Alcotest.(check int) "one lockfile error" 1 (count_occurrences e "no forge.lock");
  Alcotest.(check int) "no per-dep warnings" 0 (count_occurrences e "offline: dependency");
  let (code, _, e) = run_forge env ~dir:app [ "deps"; "--offline" ] in
  Alcotest.(check bool) "deps --offline fails" true (code <> 0);
  Alcotest.(check int) "deps --offline: one error" 1 (count_occurrences e "no forge.lock");
  check_no_network env

(** forge.toml syntax in forge.lock (3 of 13 real lockfiles): reported as not
    a lockfile, exactly once — never as "no dependencies". *)
let test_e2e_malformed_lockfile () =
  let env = make_env () in
  let app = make_app ~body:app_standalone
      ~deps:[ "depot = { git = \"https://example.invalid/depot.git\", tag = \"v1\" }" ] () in
  write_file (Filename.concat app "forge.lock") malformed_lock_text;
  let (_, _, e) = run_forge env ~dir:app [ "build"; "--offline" ] in
  Alcotest.(check int) "build: one not-a-lockfile error" 1
    (count_occurrences e "is not a lockfile");
  let (code, o, e) = run_forge env ~dir:app [ "deps"; "--offline" ] in
  Alcotest.(check bool) "deps --offline exits non-zero" true (code <> 0);
  Alcotest.(check int) "deps: one not-a-lockfile error" 1
    (count_occurrences e "is not a lockfile");
  Alcotest.(check bool) "never 'no dependencies'" false (contains (o ^ e) "no dependencies");
  check_no_network env

(** Write a format-2 lockfile for [app] (so no drift) naming [entries]. *)
let write_lock app entries =
  let toml = read_file (Filename.concat app "forge.toml") in
  Resolver_lockfile.write (Filename.concat app "forge.lock") entries
    ~manifest_hash:(Resolver_lockfile.compute_manifest_hash toml)

(** Materialise a registry package tree at deps/<name>/<version> and return
    (dir, tree hash). *)
let make_registry_tree env ~name ~mod_name ~version =
  let dir = Filename.concat (deps_dir env name) version in
  write_file (Filename.concat dir "forge.toml")
    (Printf.sprintf "[package]\nname = %S\nversion = %S\ntype = \"lib\"\n" name version);
  write_file (Filename.concat dir (Printf.sprintf "lib/%s.march" name))
    (Printf.sprintf "mod %s do\n  fn answer() : Int do\n    7\n  end\nend\n" mod_name);
  (dir, Resolver_cas_package.hash_directory dir)

let registry_entry ~name ~version ~hash ?checksum () =
  Resolver_lockfile.{ name; version = Some version; source = "registry:forge";
                      commit = None; hash; checksum }

(** A registry dep in the lockfile builds from deps/<name>/<version> offline,
    with no network process and no registry-client compile. *)
let test_e2e_registry_locked_builds () =
  let env = make_env () in
  let app = make_app ~body:(app_using "Gadget") ~deps:[ "gadget = \"~> 1.0\"" ] () in
  let (_, hash) = make_registry_tree env ~name:"gadget" ~mod_name:"Gadget" ~version:"1.2.0" in
  write_lock app [ registry_entry ~name:"gadget" ~version:"1.2.0" ~hash () ];
  let (code, o, e) = run_forge env ~dir:app [ "build"; "--offline" ] in
  if code <> 0 then Alcotest.failf "offline registry build failed:\n%s\n%s" o e;
  Alcotest.(check bool) "no registry client compile" false (contains o "registry client");
  check_no_network env

(** A registry dep NOT in the lockfile is skipped offline even though a
    version of it is cached: picking that version would be version solving. *)
let test_e2e_registry_unlocked_not_guessed () =
  let env = make_env () in
  let app = make_app ~body:app_standalone ~deps:[ "gadget = \"~> 1.0\"" ] () in
  ignore (make_registry_tree env ~name:"gadget" ~mod_name:"Gadget" ~version:"1.0.0");
  write_lock app [];
  let (code, o, e) = run_forge env ~dir:app [ "build"; "--offline" ] in
  if code <> 0 then Alcotest.failf "build should succeed:\n%s\n%s" o e;
  Alcotest.(check bool) "warned: not in forge.lock" true
    (contains e "dependency `gadget` has no entry in forge.lock");
  Alcotest.(check bool) "says the cached version is not used" true
    (contains e "1.0.0 is not used");
  (* And it really is skipped: importing it fails. *)
  write_file (Filename.concat app "lib/app.march") (app_using "Gadget");
  let (code, _, _) = run_forge env ~dir:app [ "build"; "--offline" ] in
  Alcotest.(check bool) "the unlocked dep is not on the search path" true (code <> 0);
  check_no_network env

(** The transitive walk descends into the LOCKED version of a dependency.
    `gadget` has two versions cached; the locked one (1.2.0) depends on
    `sprocket`, and the app imports only `Sprocket`. Before the walk was given
    the lockfile's coordinates, the two-version container was ambiguous to the
    locator, the walk never read gadget's forge.toml, and `Sprocket` was
    unknown — online and offline alike. *)
let test_e2e_transitive_through_locked_version () =
  let env = make_env () in
  let app = make_app ~body:(app_using "Sprocket") ~deps:[ "gadget = \"~> 1.0\"" ] () in
  let (gdir, _) = make_registry_tree env ~name:"gadget" ~mod_name:"Gadget" ~version:"1.2.0" in
  write_file (Filename.concat gdir "forge.toml")
    "[package]\nname = \"gadget\"\nversion = \"1.2.0\"\ntype = \"lib\"\n\n[deps]\nsprocket = \"~> 0.1\"\n";
  let ghash = Resolver_cas_package.hash_directory gdir in
  ignore (make_registry_tree env ~name:"gadget" ~mod_name:"Gadget" ~version:"1.1.0");
  let (_, shash) = make_registry_tree env ~name:"sprocket" ~mod_name:"Sprocket" ~version:"0.1.0" in
  write_lock app [ registry_entry ~name:"gadget" ~version:"1.2.0" ~hash:ghash ();
                   registry_entry ~name:"sprocket" ~version:"0.1.0" ~hash:shash () ];
  List.iter (fun args ->
      let (code, o, e) = run_forge env ~dir:app args in
      if code <> 0 then
        Alcotest.failf "forge %s failed:\n%s\n%s" (String.concat " " args) o e)
    [ [ "check" ]; [ "check"; "--offline" ] ];
  check_no_network env

(** `forge add` (registry) and `forge outdated` refuse offline, before any
    `march` subprocess (the registry-client compile) and without touching
    forge.toml. `march` itself is a sentinel here. *)
let test_e2e_add_outdated_refuse () =
  let env = make_env ~sentinel_march:true () in
  let app = make_app ~body:app_standalone () in
  let toml_before = read_file (Filename.concat app "forge.toml") in
  write_lock app [ registry_entry ~name:"gadget" ~version:"1.0.0" ~hash:"sha256:00" () ];
  let (code, _, e) = run_forge env ~dir:app [ "add"; "gadget"; "--offline" ] in
  Alcotest.(check bool) "add refuses" true (code <> 0);
  Alcotest.(check int) "one clear message" 1 (count_occurrences e "offline (--offline): refusing");
  Alcotest.(check string) "forge.toml untouched" toml_before
    (read_file (Filename.concat app "forge.toml"));
  let (code, _, e) = run_forge env ~dir:app [ "--offline"; "outdated" ] in
  Alcotest.(check bool) "outdated refuses" true (code <> 0);
  Alcotest.(check bool) "says why" true (contains e "no offline mode");
  check_no_network env

(** Integrity (§4): a byte changed in a cached tree fails the offline build,
    naming the dep and both hashes. *)
let test_e2e_integrity_mismatch () =
  let env = make_env () in
  let up = make_upstream "widget" ~mod_name:"Widget" in
  let app = make_app ~body:(app_using "Widget")
      ~deps:[ Printf.sprintf "widget = { git = %S, tag = \"v1.0.0\" }" ("file://" ^ up) ] () in
  populate env app;
  let dir = only_coord env "widget" in
  let src = Filename.concat dir "lib/widget.march" in
  write_file src (String.map (fun c -> if c = '4' then '5' else c) (read_file src));
  let actual = Resolver_cas_package.hash_directory dir in
  let (code, o, e) = run_forge env ~dir:app [ "build"; "--offline" ] in
  Alcotest.(check bool) "build fails" true (code <> 0);
  Alcotest.(check bool) "names the dep" true (contains e "dependency `widget`");
  Alcotest.(check bool) "states the integrity failure" true (contains e "failed its integrity check");
  Alcotest.(check bool) "reports the actual hash" true (contains e actual);
  Alcotest.(check bool) "did not typecheck against the tampered tree" false
    (contains o "built:");
  let (code, o, _) = run_forge env ~dir:app [ "deps"; "--offline" ] in
  Alcotest.(check bool) "deps --offline fails too" true (code <> 0);
  Alcotest.(check bool) "deps --offline flags it" true (contains o "widget: CORRUPT");
  check_no_network env

(** §2.4: a registry dep whose tree was deleted is restored, offline, from
    the cached tarball; a corrupted cached tarball is detected, discarded and
    not extracted. *)
let test_e2e_tarball_restore_and_corruption () =
  let env = make_env () in
  let app = make_app ~body:(app_using "Gadget") ~deps:[ "gadget = \"~> 1.0\"" ] () in
  (* Build a real .tar.gz with one top-level directory, as the registry serves. *)
  let staging = fresh_dir "pkg" in
  let pkg = Filename.concat staging "gadget-1.2.0" in
  write_file (Filename.concat pkg "forge.toml")
    "[package]\nname = \"gadget\"\nversion = \"1.2.0\"\ntype = \"lib\"\n";
  write_file (Filename.concat pkg "lib/gadget.march")
    "mod Gadget do\n  fn answer() : Int do\n    7\n  end\nend\n";
  let hash = Resolver_cas_package.hash_directory pkg in
  let tgz = Filename.concat staging "gadget.tar.gz" in
  shell_ok "tar czf %s -C %s gadget-1.2.0" (Filename.quote tgz) (Filename.quote staging);
  let cs = Tarball_cache.sha256_file tgz in
  let cached = Filename.concat env.home
      (Printf.sprintf ".march/cas/tarballs/%s.tar.gz" cs) in
  write_file cached (read_file tgz);
  write_lock app [ registry_entry ~name:"gadget" ~version:"1.2.0" ~hash
                     ~checksum:("sha256:" ^ cs) () ];
  let tree = Filename.concat (deps_dir env "gadget") "1.2.0" in
  Alcotest.(check bool) "tree absent before" false (Sys.file_exists tree);
  let (code, o, e) = run_forge env ~dir:app [ "deps"; "--offline" ] in
  if code <> 0 then Alcotest.failf "restore failed:\n%s\n%s" o e;
  Alcotest.(check bool) "reports the restore" true (contains o "restored from the tarball cache");
  Alcotest.(check string) "restored tree matches forge.lock" hash
    (Resolver_cas_package.hash_directory tree);
  let (code, o, e) = run_forge env ~dir:app [ "build"; "--offline" ] in
  if code <> 0 then Alcotest.failf "build from restored tree failed:\n%s\n%s" o e;
  (* Now corrupt the cached tarball and delete the tree again. *)
  ignore (Sys.command ("rm -rf " ^ Filename.quote tree));
  let bytes = Bytes.of_string (read_file cached) in
  let i = Bytes.length bytes / 2 in
  Bytes.set bytes i (Char.chr ((Char.code (Bytes.get bytes i) + 1) land 0xff));
  write_file cached (Bytes.to_string bytes);
  let (code, o, e) = run_forge env ~dir:app [ "deps"; "--offline" ] in
  Alcotest.(check bool) "fails" true (code <> 0);
  Alcotest.(check bool) "corruption reported" true (contains (o ^ e) "is corrupt");
  Alcotest.(check bool) "not extracted" false (Sys.file_exists tree);
  Alcotest.(check bool) "corrupt entry discarded" false (Sys.file_exists cached);
  check_no_network env

let () =
  Random.self_init ();
  let e2e name f = Alcotest.test_case name `Quick f in
  Alcotest.run "forge offline"
    [ "gate",
      [ Alcotest.test_case "--offline is stripped only before --" `Quick test_extract_flag;
        Alcotest.test_case "FORGE_OFFLINE values; flag only adds" `Quick test_env_var_precedence;
        Alcotest.test_case "permit refuses offline, observed online" `Quick test_permit_refuses_offline;
        Alcotest.test_case "git install refused offline, names dep + remedy" `Quick
          test_install_dep_refused_offline;
        Alcotest.test_case "registry client never compiled offline" `Quick
          test_registry_client_not_compiled_offline ];
      "tarball cache",
      [ Alcotest.test_case "store/lookup round trip, atomic" `Quick test_tarball_cache_roundtrip;
        Alcotest.test_case "store refuses bytes not matching the key" `Quick
          test_tarball_cache_refuses_wrong_bytes;
        Alcotest.test_case "corrupted entry detected, removed" `Quick
          test_tarball_cache_detects_corruption ];
      "lockfile states",
      [ Alcotest.test_case "absent vs not-a-lockfile" `Quick test_lock_states ];
      "end to end",
      [ e2e "warm cache: build/deps/check offline start no network process"
          test_e2e_warm_cache_no_network;
        e2e "deps --offline: missing dep, non-zero, no clone" test_e2e_deps_offline_missing;
        e2e "missing unimported dep warns, build succeeds" test_e2e_missing_unimported_warns;
        e2e "missing imported dep: warning then Unknown module"
          test_e2e_missing_imported_fails_after_warning;
        e2e "no lockfile: exactly one error" test_e2e_no_lockfile_one_error;
        e2e "forge.toml-syntax lockfile: exactly one error" test_e2e_malformed_lockfile;
        e2e "registry dep in lockfile builds offline" test_e2e_registry_locked_builds;
        e2e "registry dep not locked: cached version not guessed"
          test_e2e_registry_unlocked_not_guessed;
        e2e "transitive walk follows the locked version"
          test_e2e_transitive_through_locked_version;
        e2e "add / outdated refuse, no march spawned" test_e2e_add_outdated_refuse;
        e2e "tampered cached tree fails integrity check" test_e2e_integrity_mismatch;
        e2e "tarball cache: offline restore; corruption detected"
          test_e2e_tarball_restore_and_corruption ] ]
