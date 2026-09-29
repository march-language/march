(** Tests for the capability gate `forge add` runs, and for `forge outdated`'s
    upgrade preview (specs/todos/2026-08-04-dependency-cap-audit-followups.md,
    "Wire into forge add / forge outdated").

    Every case runs [Cmd_add.run] in-process against a scratch project with
    PATH dependencies, under a scratch HOME and MARCH_HOME, so nothing is
    fetched and nothing outside the fixture is written. The inferred-mode cases
    put a FAKE `march` first on PATH that logs every invocation (the same
    technique as test_audit_inferred.ml): that log is what shows the gate
    analyzed only the dependencies the add touched.

    Every fixture package is a real module (`mod X do ... end`). A bare `fn`
    file parses to an EMPTY surface, so a "no new capabilities" case built on
    one would pass whatever the gate did; [test_fixtures_parse] pins that the
    fixtures really parse and really declare what the cases assume. *)

open March_forge

let write_file path content =
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc

let read_file path =
  try
    let ic = open_in_bin path in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic;
    s
  with Sys_error _ -> ""

let rec mkdir_p d =
  if not (Sys.file_exists d) then begin
    mkdir_p (Filename.dirname d);
    Unix.mkdir d 0o755
  end

let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec at i = i + m <= n && (String.sub hay i m = needle || at (i + 1)) in
  at 0

(* ------------------------------------------------------------------ *)
(*  Fixture                                                            *)
(* ------------------------------------------------------------------ *)

(* The source of package [name]'s one module, declaring [needs]. *)
let module_src name needs =
  let m = String.capitalize_ascii name in
  Printf.sprintf "mod %s do\n%s  fn f() : Int do 1 end\nend\n" m
    (String.concat ""
       (List.map (fun c -> Printf.sprintf "  needs %s\n" c) needs))

type fixture = {
  base : string;
  app : string;
  bindir : string;
  log : string;
}

let counter = ref 0

(* A `march` that supports `caps` and reports IO.Clock for every package. *)
let fake_march ~log =
  Printf.sprintf
    "#!/bin/sh\n\
     echo \"$*\" >> %s\n\
     case \"$1\" in\n\
    \  --version) echo 'march 9.9.9-fake'; exit 0 ;;\n\
    \  caps)\n\
    \    case \"$*\" in *forge_caps_probe*) echo '{\"caps\":[]}'; exit 0 ;; esac\n\
    \    echo '{\"caps\":[\"IO.Clock\"]}'; exit 0 ;;\n\
     esac\n\
     echo \"march: $1: No such file or directory\" >&2\n\
     exit 1\n"
    (Filename.quote log)

let add_package f ~name ~needs =
  let dir = Filename.concat f.base name in
  mkdir_p (Filename.concat dir "lib");
  write_file (Filename.concat dir "forge.toml")
    (Printf.sprintf
       "[package]\nname = %S\nversion = \"0.1.0\"\ntype = \"lib\"\n\n[deps]\n" name);
  write_file (Filename.concat (Filename.concat dir "lib") (name ^ ".march"))
    (module_src name needs)

(* [packages]: (name, needs) available on disk; the app depends on
   [app_deps] from the start. *)
let make_fixture ~app_deps ~packages =
  incr counter;
  let base =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "forge-add-capgate-%d-%d" (Unix.getpid ()) !counter)
  in
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote base)));
  mkdir_p base;
  let f =
    { base;
      app = Filename.concat base "app";
      bindir = Filename.concat base "bin";
      log = Filename.concat base "march.log" }
  in
  mkdir_p f.bindir;
  mkdir_p (Filename.concat base "home");
  mkdir_p (Filename.concat base "march_home");
  let exe = Filename.concat f.bindir "march" in
  write_file exe (fake_march ~log:f.log);
  Unix.chmod exe 0o755;
  mkdir_p (Filename.concat f.app "lib");
  write_file (Filename.concat f.app "forge.toml")
    (Printf.sprintf "[package]\nname = \"app\"\nversion = \"0.1.0\"\n\n[deps]\n%s"
       (String.concat ""
          (List.map (fun d -> Printf.sprintf "%s = { path = \"../%s\" }\n" d d) app_deps)));
  write_file (Filename.concat (Filename.concat f.app "lib") "app.march")
    (module_src "app" []);
  List.iter (fun (name, needs) -> add_package f ~name ~needs) packages;
  f

let in_fixture f k =
  let saved = List.map (fun v -> (v, Sys.getenv_opt v)) [ "PATH"; "HOME"; "MARCH_HOME" ] in
  let old_cwd = Sys.getcwd () in
  Unix.putenv "PATH" (f.bindir ^ ":" ^ Option.value ~default:"" (List.assoc "PATH" saved));
  Unix.putenv "HOME" (Filename.concat f.base "home");
  Unix.putenv "MARCH_HOME" (Filename.concat f.base "march_home");
  Sys.chdir f.app;
  Fun.protect
    ~finally:(fun () ->
        Sys.chdir old_cwd;
        List.iter (fun (v, o) -> Unix.putenv v (Option.value ~default:"" o)) saved)
    k

(* Run [f], returning its result and everything it printed to stdout. *)
let capture f =
  flush stdout;
  let tmp = Filename.temp_file "capgate_out" ".txt" in
  let fd = Unix.openfile tmp [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o644 in
  let saved = Unix.dup Unix.stdout in
  Unix.dup2 fd Unix.stdout;
  Unix.close fd;
  let r = try Ok (f ()) with e -> Error e in
  flush stdout;
  Unix.dup2 saved Unix.stdout;
  Unix.close saved;
  let out = read_file tmp in
  Sys.remove tmp;
  match r with Ok v -> (v, out) | Error e -> raise e

let add ?(accept_caps = false) f name =
  in_fixture f (fun () ->
      capture (fun () ->
          Cmd_add.run ~accept_caps ~name ~git:None ~tag:None ~branch:None ~rev:None
            ~path:(Some ("../" ^ name)) ~dev:false ~dev_only:false ~test_dep:false
            ~force:false ()))

let deps f =
  match in_fixture f (fun () -> capture Cmd_deps.run) with
  | Ok (), _ -> ()
  | Error e, out -> Alcotest.failf "forge deps failed: %s\n%s" e out

let record ?(inferred = false) f =
  match in_fixture f (fun () -> capture (fun () -> Cmd_audit.run ~record_mode:true ~inferred ())) with
  | Ok 0, _ -> ()
  | Ok c, out -> Alcotest.failf "record exited %d:\n%s" c out
  | Error e, out -> Alcotest.failf "record failed: %s\n%s" e out

let toml f = read_file (Filename.concat f.app "forge.toml")
let lock f = read_file (Filename.concat f.app "forge.lock")
let caps_lock_path f = Filename.concat f.app "forge.caps.lock"

(* `march caps` runs over [pkg]'s own files (the probe excluded). *)
let caps_runs f pkg =
  String.split_on_char '\n' (read_file f.log)
  |> List.filter (fun l ->
      String.length l >= 5 && String.sub l 0 5 = "caps "
      && contains l (Printf.sprintf "/%s/lib/" pkg))
  |> List.length

(* ------------------------------------------------------------------ *)
(*  The fixtures are what the cases assume                             *)
(* ------------------------------------------------------------------ *)

let test_fixtures_parse () =
  let f = make_fixture ~app_deps:[] ~packages:[ ("fs", [ "IO.FileWrite" ]); ("pure", []) ] in
  Alcotest.(check (list string)) "fs declares IO.FileWrite" [ "IO.FileWrite" ]
    (Cmd_audit.caps_of_dir (Filename.concat f.base "fs"));
  match Cmd_audit.parse_file (Filename.concat f.base "pure/lib/pure.march") with
  | None -> Alcotest.fail "the capability-free fixture does not parse"
  | Some [] -> Alcotest.fail "the capability-free fixture parses to an EMPTY surface"
  | Some _ ->
    Alcotest.(check (list string)) "pure declares nothing" []
      (Cmd_audit.caps_of_dir (Filename.concat f.base "pure"))

(* ------------------------------------------------------------------ *)
(*  Declared-mode baseline                                             *)
(* ------------------------------------------------------------------ *)

let test_no_baseline_is_informational () =
  let f = make_fixture ~app_deps:[] ~packages:[ ("fs", [ "IO.FileWrite" ]) ] in
  let r, out = add f "fs" in
  Alcotest.(check bool) "add succeeds" true (Result.is_ok r);
  Alcotest.(check bool) "forge.toml has the dependency" true (contains (toml f) "fs = { path");
  Alcotest.(check bool) "reports what fs declares" true
    (contains out "capabilities: fs — IO.FileWrite");
  Alcotest.(check bool) "points at forge audit --record" true
    (contains out "forge audit --record");
  Alcotest.(check bool) "writes no baseline" false (Sys.file_exists (caps_lock_path f))

(* An app that depends on clock (IO.Clock), resolved and recorded. *)
let recorded_fixture ?(inferred = false) extra =
  let f = make_fixture ~app_deps:[ "clock" ] ~packages:(("clock", [ "IO.Clock" ]) :: extra) in
  deps f;
  record ~inferred f;
  f

let test_widening_add_is_refused_and_rolled_back () =
  let f = recorded_fixture [ ("fs", [ "IO.FileWrite" ]) ] in
  let toml0 = toml f and lock0 = lock f and caps0 = read_file (caps_lock_path f) in
  let r, out = add f "fs" in
  (match r with
   | Ok () -> Alcotest.failf "adding a dependency with new capabilities must be refused:\n%s" out
   | Error msg ->
     Alcotest.(check bool) "names the dependency" true (contains msg "fs");
     Alcotest.(check bool) "names the flag" true (contains msg "--accept-caps"));
  Alcotest.(check bool) "shows the delta" true
    (contains out "+ fs — new dependency, declares: IO.FileWrite");
  Alcotest.(check string) "forge.toml restored byte-for-byte" toml0 (toml f);
  Alcotest.(check string) "forge.lock restored byte-for-byte" lock0 (lock f);
  Alcotest.(check string) "forge.caps.lock untouched" caps0 (read_file (caps_lock_path f))

let test_accept_caps_keeps_and_records () =
  let f = recorded_fixture [ ("fs", [ "IO.FileWrite" ]) ] in
  let r, out = add ~accept_caps:true f "fs" in
  Alcotest.(check bool) "add succeeds with --accept-caps" true (Result.is_ok r);
  Alcotest.(check bool) "still shows the delta" true (contains out "+ fs");
  Alcotest.(check bool) "forge.toml has the dependency" true (contains (toml f) "fs = { path");
  Alcotest.(check bool) "forge.lock has the dependency" true (contains (lock f) "\"fs\"");
  Alcotest.(check (list (pair string (list string))))
    "forge.caps.lock gains fs and keeps clock"
    [ ("clock", [ "IO.Clock" ]); ("fs", [ "IO.FileWrite" ]) ]
    (Cmd_audit.read_baseline (caps_lock_path f));
  Alcotest.(check (option bool)) "mode stays declared" (Some false)
    (Option.map (fun m -> m = `Inferred) (Cmd_audit.baseline_mode (caps_lock_path f)));
  let code, _ = in_fixture f (fun () -> capture (fun () -> Cmd_audit.run ())) in
  Alcotest.(check bool) "forge audit passes afterwards" true (code = Ok 0)

let test_capability_free_add_passes () =
  let f = recorded_fixture [ ("pure", []) ] in
  let r, out = add f "pure" in
  Alcotest.(check bool) "add succeeds without the flag" true (Result.is_ok r);
  Alcotest.(check bool) "says nothing new was asked for" true
    (contains out "no new authority requested (pure)")

let test_changed_existing_dependency_is_gated () =
  (* The upgrade case: an existing dependency changed under the add (its lock
     entry's tree hash moved) and now needs IO.Process. *)
  let f = recorded_fixture [ ("pure", []) ] in
  write_file (Filename.concat f.base "clock/lib/clock.march")
    (module_src "clock" [ "IO.Clock"; "IO.Process" ]);
  let r, out = add f "pure" in
  (match r with
   | Ok () -> Alcotest.failf "a widened dependency must be refused:\n%s" out
   | Error msg -> Alcotest.(check bool) "names clock" true (contains msg "clock"));
  Alcotest.(check bool) "shows the widening" true
    (contains out "! clock — now ALSO needs: IO.Process");
  let r, _ = add ~accept_caps:true f "pure" in
  Alcotest.(check bool) "accepted with the flag" true (Result.is_ok r);
  Alcotest.(check (option (list string))) "clock's new set recorded"
    (Some [ "IO.Clock"; "IO.Process" ])
    (List.assoc_opt "clock" (Cmd_audit.read_baseline (caps_lock_path f)))

let test_untouched_dependency_is_not_gated () =
  (* clock's recorded set is stale (it declares IO.Clock, the baseline says
     nothing), but the add does not touch it: that drift is `forge audit`'s
     to report, not a reason to refuse an unrelated add. *)
  let f = recorded_fixture [ ("pure", []) ] in
  write_file (caps_lock_path f) "mode = \"declared\"\n\n[[package]]\nname = \"clock\"\ncaps = []\n";
  let r, out = add f "pure" in
  Alcotest.(check bool) "unrelated add passes" true (Result.is_ok r);
  Alcotest.(check bool) "clock is not mentioned as changed" false (contains out "clock —")

(* ------------------------------------------------------------------ *)
(*  Inferred-mode baseline: bounded to the touched dependencies        *)
(* ------------------------------------------------------------------ *)

let test_inferred_gate_is_bounded_and_cached () =
  let f = recorded_fixture ~inferred:true [ ("newdep", []) ] in
  Alcotest.(check (option bool)) "baseline records inferred mode" (Some true)
    (Option.map (fun m -> m = `Inferred) (Cmd_audit.baseline_mode (caps_lock_path f)));
  (* A cold cache for everything: only the touched dependency may be run. *)
  ignore (Sys.command (Printf.sprintf "rm -rf %s"
                         (Filename.quote (Filename.concat f.app ".forge/audit-cache"))));
  let clock_before = caps_runs f "clock" in
  let r, out = add f "newdep" in
  (match r with
   | Ok () -> Alcotest.failf "inferred IO.Clock on a new dep must be refused:\n%s" out
   | Error _ -> ());
  Alcotest.(check bool) "the delta is the INFERRED set" true
    (contains out "+ newdep — new dependency, declares: IO.Clock");
  Alcotest.(check int) "newdep analyzed once" 1 (caps_runs f "newdep");
  Alcotest.(check int) "clock (untouched) not re-analyzed" clock_before (caps_runs f "clock");
  let r, _ = add ~accept_caps:true f "newdep" in
  Alcotest.(check bool) "accepted" true (Result.is_ok r);
  Alcotest.(check int) "the second add is a cache hit" 1 (caps_runs f "newdep");
  Alcotest.(check (option bool)) "mode stays inferred" (Some true)
    (Option.map (fun m -> m = `Inferred) (Cmd_audit.baseline_mode (caps_lock_path f)))

let test_audit_warns_on_mode_mismatch () =
  let f = recorded_fixture [] in
  let _, out =
    in_fixture f (fun () -> capture (fun () -> Cmd_audit.run ~inferred:true ()))
  in
  Alcotest.(check bool) "warns that the baseline was recorded without --inferred" true
    (contains out "was recorded from `needs` declarations")

(* ------------------------------------------------------------------ *)
(*  Pure pieces                                                        *)
(* ------------------------------------------------------------------ *)

let entry ?version ?commit ?(hash = "h") name =
  Resolver_lockfile.{ name; version; source = "path:../" ^ name; commit; hash; checksum = None }

let test_touched_entries () =
  let before = [ entry "a"; entry ~hash:"h1" "b"; entry ~version:"1.0.0" "c" ] in
  let after =
    [ entry "a"; entry ~hash:"h2" "b"; entry ~version:"1.1.0" "c"; entry "d" ] in
  Alcotest.(check (list string)) "changed hash, changed version, and new"
    [ "b"; "c"; "d" ] (Cmd_audit.touched_entries ~before ~after)

let test_legacy_baseline_has_no_mode () =
  let dir = Filename.get_temp_dir_name () in
  let p = Filename.concat dir (Printf.sprintf "legacy-caps-%d.lock" (Unix.getpid ())) in
  write_file p "# old\n\n[[package]]\nname = \"a\"\ncaps = [\"IO.Clock\"]\n";
  Alcotest.(check bool) "no mode line reads as unrecorded" true
    (Cmd_audit.baseline_mode p = None);
  Alcotest.(check (list (pair string (list string)))) "entries still read"
    [ ("a", [ "IO.Clock" ]) ] (Cmd_audit.read_baseline p);
  Cmd_audit.write_baseline ~inferred:true p
    [ { Cmd_audit.dc_name = "a"; dc_caps = [ "IO.Clock" ]; dc_installed = true } ];
  Alcotest.(check bool) "written inferred" true (Cmd_audit.baseline_mode p = Some `Inferred);
  Alcotest.(check (list (pair string (list string)))) "mode line does not disturb entries"
    [ ("a", [ "IO.Clock" ]) ] (Cmd_audit.read_baseline p);
  Sys.remove p

let test_outdated_preview_line () =
  let f = make_fixture ~app_deps:[]
      ~packages:[ ("wider", [ "IO.Clock"; "IO.FileWrite" ]); ("same", [ "IO.Clock" ]) ] in
  let tree name () = Ok (Filename.concat f.base name) in
  let line ~before t = Cmd_outdated.upgrade_caps_line ~inferred:false ~before ~tree:t in
  let wider = line ~before:(Some [ "IO.Clock" ]) (tree "wider") in
  Alcotest.(check bool) ("widened release is flagged: " ^ wider) true
    (contains wider "NEW capabilities: IO.FileWrite");
  Alcotest.(check string) "same set" "caps: no new capabilities"
    (line ~before:(Some [ "IO.Clock" ]) (tree "same"));
  Alcotest.(check bool) "unknown current set is not compared" true
    (contains (line ~before:None (fun () -> Alcotest.fail "must not fetch")) "not compared");
  Alcotest.(check bool) "a failed fetch is unknown, never 'no new'" true
    (contains (line ~before:(Some []) (fun () -> Error "offline")) "caps: unknown (offline)")

let () =
  Alcotest.run "forge-add-capgate"
    [ ( "fixtures", [ Alcotest.test_case "fixtures parse and declare" `Quick test_fixtures_parse ] );
      ( "declared",
        [ Alcotest.test_case "no baseline: informational" `Quick test_no_baseline_is_informational;
          Alcotest.test_case "widening add refused, rolled back" `Quick
            test_widening_add_is_refused_and_rolled_back;
          Alcotest.test_case "--accept-caps keeps and records" `Quick
            test_accept_caps_keeps_and_records;
          Alcotest.test_case "capability-free add passes" `Quick test_capability_free_add_passes;
          Alcotest.test_case "changed existing dependency is gated" `Quick
            test_changed_existing_dependency_is_gated;
          Alcotest.test_case "untouched dependency is not gated" `Quick
            test_untouched_dependency_is_not_gated ] );
      ( "inferred",
        [ Alcotest.test_case "bounded to touched deps, cached" `Quick
            test_inferred_gate_is_bounded_and_cached;
          Alcotest.test_case "forge audit warns on a mode mismatch" `Quick
            test_audit_warns_on_mode_mismatch ] );
      ( "pure",
        [ Alcotest.test_case "touched_entries" `Quick test_touched_entries;
          Alcotest.test_case "legacy baseline has no mode" `Quick test_legacy_baseline_has_no_mode;
          Alcotest.test_case "outdated preview line" `Quick test_outdated_preview_line ] ) ]
