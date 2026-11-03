(* The one z3 lookup (MARCH_Z3, then <real exe dir>/../libexec/z3, then PATH),
   the pinned-version probe and the health report
   (specs/2026-11-02-bundled-z3-design.md).  Every z3 here is a fake: a shell
   script that prints a version line, so the cases run without a real z3. *)

open March_refine

let tmp_root =
  let d = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march-z3-lookup-%d" (Unix.getpid ())) in
  (try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  d

let contains s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  go 0

let counter = ref 0

(* A fresh directory per case, so no two fakes share a path (the probe cache
   is keyed on it). *)
let fresh_dir name =
  incr counter;
  let d = Filename.concat tmp_root (Printf.sprintf "%s-%d" name !counter) in
  Unix.mkdir d 0o755;
  d

let write_script path body =
  Out_channel.with_open_bin path (fun oc -> output_string oc ("#!/bin/sh\n" ^ body ^ "\n"));
  Unix.chmod path 0o755

let fake_z3 ?(version = Z3_pin.version) dir =
  let p = Filename.concat dir "z3" in
  write_script p (Printf.sprintf "echo 'Z3 version %s - 64 bit'" version);
  p

(* Each case sets the lookup environment explicitly.  OCaml has no unsetenv,
   so an empty MARCH_Z3 counts as unset. *)
let with_env ?(march_z3 = "") ~path f =
  Unix.putenv "MARCH_Z3" march_z3;
  Unix.putenv "PATH" path;
  Unix.putenv "XDG_CACHE_HOME" (fresh_dir "cache");
  f ()

let source_s = function Solver.Env -> "env" | Solver.Bundled -> "bundled" | Solver.Path -> "path"

let found = Alcotest.(result (pair string string) string)

let find () =
  match Solver.find_z3 () with
  | Ok (p, s) -> Ok (p, source_s s)
  | Error e -> Error e

let helper_exe = Filename.concat (Filename.dirname Sys.executable_name) "z3_lookup_helper.exe"

let copy_file src dst =
  let s = In_channel.with_open_bin src In_channel.input_all in
  Out_channel.with_open_bin dst (fun oc -> output_string oc s);
  Unix.chmod dst 0o755

(* An install laid out like a release archive: <root>/bin/<helper> and
   <root>/libexec/z3.  The helper prints its own find_z3 as `source:path`. *)
let bundled_install () =
  let root = fresh_dir "install" in
  let bin = Filename.concat root "bin" and libexec = Filename.concat root "libexec" in
  Unix.mkdir bin 0o755;
  Unix.mkdir libexec 0o755;
  let exe = Filename.concat bin "march" in
  copy_file helper_exe exe;
  let z3 = fake_z3 libexec in
  (exe, Unix.realpath z3)

let run_helper exe =
  let ic = Unix.open_process_args_in exe [| exe |] in
  let out = String.trim (In_channel.input_all ic) in
  ignore (Unix.close_process_in ic);
  out

let lookup_suite =
  [ Alcotest.test_case "march_z3_wins_over_path" `Quick (fun () ->
        let env_z3 = fake_z3 (fresh_dir "env") in
        let path_dir = fresh_dir "path" in
        ignore (fake_z3 path_dir);
        with_env ~march_z3:env_z3 ~path:path_dir (fun () ->
            Alcotest.check found "env first" (Ok (env_z3, "env")) (find ())));
    Alcotest.test_case "march_z3_missing_is_broken" `Quick (fun () ->
        let path_dir = fresh_dir "path" in
        ignore (fake_z3 path_dir);
        with_env ~march_z3:"/nonexistent/z3" ~path:path_dir (fun () ->
            (match Solver.find_z3 () with
             | Error msg ->
                 Alcotest.(check bool) "names the path" true
                   (contains msg "/nonexistent/z3")
             | Ok _ -> Alcotest.fail "a set MARCH_Z3 that does not exist must not fall through");
            match Solver.health () with
            | Solver.Broken { path; _ } -> Alcotest.(check string) "path" "/nonexistent/z3" path
            | _ -> Alcotest.fail "expected Broken"));
    Alcotest.test_case "lookup_falls_back_to_path_for_dev_build" `Quick (fun () ->
        let path_dir = fresh_dir "path" in
        let z3 = fake_z3 path_dir in
        with_env ~path:("/nonexistent-dir:" ^ path_dir) (fun () ->
            Alcotest.check found "path" (Ok (z3, "path")) (find ())));
    Alcotest.test_case "lookup_not_found" `Quick (fun () ->
        with_env ~path:(fresh_dir "empty") (fun () ->
            Alcotest.check found "missing" (Error "not found") (find ());
            match Solver.health () with
            | Solver.Missing _ -> ()
            | _ -> Alcotest.fail "expected Missing"));
    Alcotest.test_case "lookup_finds_bundled" `Quick (fun () ->
        let exe, z3 = bundled_install () in
        let path_dir = fresh_dir "path" in
        ignore (fake_z3 path_dir);
        with_env ~path:path_dir (fun () ->
            Alcotest.(check string) "bundled beats PATH" ("bundled:" ^ z3) (run_helper exe)));
    Alcotest.test_case "lookup_resolves_symlinked_exe" `Quick (fun () ->
        let exe, z3 = bundled_install () in
        let link_dir = fresh_dir "current" in
        let link = Filename.concat link_dir "march" in
        Unix.symlink exe link;
        with_env ~path:(fresh_dir "empty") (fun () ->
            Alcotest.(check string) "through the symlink" ("bundled:" ^ z3) (run_helper link))) ]

let probe_suite =
  [ Alcotest.test_case "probe_parses_version" `Quick (fun () ->
        with_env ~path:(fresh_dir "empty") (fun () ->
            let ok = fake_z3 ~version:"4.16.0" (fresh_dir "ok") in
            Alcotest.(check (result string string)) "version" (Ok "4.16.0") (Solver.probe_version ok);
            let garbage = Filename.concat (fresh_dir "garbage") "z3" in
            write_script garbage "echo garbage";
            Alcotest.(check bool) "garbage" true (Result.is_error (Solver.probe_version garbage));
            let fails = Filename.concat (fresh_dir "fails") "z3" in
            write_script fails "echo 'Z3 version 4.16.0 - 64 bit'; exit 1";
            Alcotest.(check bool) "exit 1" true (Result.is_error (Solver.probe_version fails))));
    Alcotest.test_case "probe_is_cached_on_disk" `Quick (fun () ->
        with_env ~path:(fresh_dir "empty") (fun () ->
            let dir = fresh_dir "logged" in
            let log = Filename.concat dir "calls" in
            let z3 = Filename.concat dir "z3" in
            write_script z3
              (Printf.sprintf "echo x >> %s; echo 'Z3 version %s - 64 bit'" log Z3_pin.version);
            ignore (Solver.probe_version z3);
            Solver.clear_probe_memo ();
            ignore (Solver.probe_version z3);
            let calls = In_channel.with_open_bin log In_channel.input_all in
            Alcotest.(check string) "z3 exec'd once" "x\n" calls));
    Alcotest.test_case "health_healthy" `Quick (fun () ->
        let z3 = fake_z3 (fresh_dir "ok") in
        with_env ~march_z3:z3 ~path:(fresh_dir "empty") (fun () ->
            match Solver.health () with
            | Solver.Healthy { version; source = Solver.Env; _ } ->
                Alcotest.(check string) "version" Z3_pin.version version
            | _ -> Alcotest.fail "expected Healthy"));
    Alcotest.test_case "health_mismatch" `Quick (fun () ->
        let z3 = fake_z3 ~version:"4.8.12" (fresh_dir "old") in
        with_env ~march_z3:z3 ~path:(fresh_dir "empty") (fun () ->
            match Solver.health () with
            | Solver.Mismatch { version; path; _ } ->
                Alcotest.(check string) "version" "4.8.12" version;
                Alcotest.(check string) "path" z3 path
            | _ -> Alcotest.fail "expected Mismatch"));
    (* A z3 that never finishes `--version` (wedged, or a fake reading its
       stdin) must not hang the compiler: the probe gets no stdin and the
       hang backstop, and reports it as broken. *)
    Alcotest.test_case "probe_does_not_hang" `Quick (fun () ->
        with_env ~path:(fresh_dir "empty") (fun () ->
            (* This process's stdin: a pipe nobody ever writes or closes, so
               a probe that inherits it would wait for ever. *)
            let saved_stdin = Unix.dup Unix.stdin in
            let r, w = Unix.pipe () in
            Unix.dup2 r Unix.stdin;
            let reads = Filename.concat (fresh_dir "reads") "z3" in
            write_script reads "/bin/cat > /dev/null; echo 'Z3 version 4.16.0 - 64 bit'";
            let got = Solver.probe_version reads in
            Unix.dup2 saved_stdin Unix.stdin;
            List.iter Unix.close [ saved_stdin; r; w ];
            Alcotest.(check (result string string)) "stdin is empty" (Ok "4.16.0") got;
            let sleeps = Filename.concat (fresh_dir "sleeps") "z3" in
            write_script sleeps "/bin/sleep 30";
            Unix.putenv "MARCH_Z3_BACKSTOP_MS" "500";
            let t0 = Unix.gettimeofday () in
            let r = Solver.probe_version sleeps in
            Unix.putenv "MARCH_Z3_BACKSTOP_MS" "";
            Alcotest.(check bool) "an error" true (Result.is_error r);
            Alcotest.(check bool) "within 3 s" true (Unix.gettimeofday () -. t0 < 3.0)));
    Alcotest.test_case "health_broken_on_bad_probe" `Quick (fun () ->
        let z3 = Filename.concat (fresh_dir "bad") "z3" in
        write_script z3 "exit 1";
        with_env ~march_z3:z3 ~path:(fresh_dir "empty") (fun () ->
            match Solver.health () with
            | Solver.Broken { path; _ } -> Alcotest.(check string) "path" z3 path
            | _ -> Alcotest.fail "expected Broken")) ]

let () =
  Alcotest.run "z3_lookup" [ ("lookup", lookup_suite); ("probe", probe_suite) ]
