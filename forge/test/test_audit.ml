(** Tests for `forge audit` — capability extraction, baseline round-trip, and
    the escalation rule that decides the exit code.

    These exercise the pure layers directly (extraction, diff, baseline I/O)
    rather than shelling out to a `forge` subprocess: test_build_check.ml is
    quarantined from `runtest` for doing that, and the interesting logic here is
    all reachable without it. *)

open March_forge

let tmp_dir prefix =
  let base = Filename.get_temp_dir_name () in
  let rec attempt n =
    let path = Filename.concat base (Printf.sprintf "%s-%d-%d" prefix (Unix.getpid ()) n) in
    if Sys.file_exists path then attempt (n + 1)
    else (Unix.mkdir path 0o755; path)
  in
  attempt 0

let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let rec rm_rf path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Array.iter (fun n -> rm_rf (Filename.concat path n)) (Sys.readdir path);
      Unix.rmdir path
    end
    else Sys.remove path

(* ------------------------------------------------------------------ *)
(*  Capability extraction                                              *)
(* ------------------------------------------------------------------ *)

let test_caps_of_dir_collects_needs () =
  let dir = tmp_dir "audit-caps" in
  write_file (Filename.concat dir "a.march")
    "mod A do\n  needs IO.FileRead\n  fn f() : Int do 1 end\nend\n";
  write_file (Filename.concat dir "b.march")
    "mod B do\n  needs IO.NetConnect, IO.Clock\n  fn g() : Int do 2 end\nend\n";
  let caps = Cmd_audit.caps_of_dir dir in
  rm_rf dir;
  Alcotest.(check (list string)) "sorted union across files"
    ["IO.Clock"; "IO.FileRead"; "IO.NetConnect"] caps

let test_caps_of_dir_finds_nested_module_needs () =
  (* A `needs` inside a nested module is just as much part of the package's
     authority as a top-level one; missing it would under-report the surface,
     which is the direction that lets an escalation through unnoticed. *)
  let dir = tmp_dir "audit-nested" in
  write_file (Filename.concat dir "n.march")
    "mod Outer do\n\
    \  mod Inner do\n\
    \    needs IO.FileWrite\n\
    \    fn h() : Int do 3 end\n\
    \  end\n\
     end\n";
  let caps = Cmd_audit.caps_of_dir dir in
  rm_rf dir;
  Alcotest.(check (list string)) "nested needs is collected" ["IO.FileWrite"] caps

let test_caps_of_dir_empty_without_needs () =
  let dir = tmp_dir "audit-empty" in
  write_file (Filename.concat dir "p.march")
    "mod P do\n  fn pure_fn(n : Int) : Int do n * 2 end\nend\n";
  let caps = Cmd_audit.caps_of_dir dir in
  rm_rf dir;
  Alcotest.(check (list string)) "no needs means no capabilities" [] caps

let test_caps_of_dir_ignores_unparseable_file () =
  (* A dependency that does not parse is `forge build`'s problem. Failing the
     audit for it would conflate "cannot read" with "asks for nothing", and the
     readable files still carry real information. *)
  let dir = tmp_dir "audit-broken" in
  write_file (Filename.concat dir "ok.march")
    "mod Ok do\n  needs IO.Clock\n  fn f() : Int do 1 end\nend\n";
  write_file (Filename.concat dir "broken.march") "mod Broken do fn ( ??? end\n";
  let caps = Cmd_audit.caps_of_dir dir in
  rm_rf dir;
  Alcotest.(check (list string)) "readable files still counted" ["IO.Clock"] caps

(* ------------------------------------------------------------------ *)
(*  Baseline round-trip                                                *)
(* ------------------------------------------------------------------ *)

let test_baseline_roundtrip () =
  let dir = tmp_dir "audit-baseline" in
  let path = Filename.concat dir "forge.caps.lock" in
  let deps =
    [ { Cmd_audit.dc_name = "alpha"; dc_caps = ["IO.FileRead"; "IO.Net"]; dc_installed = true };
      { Cmd_audit.dc_name = "beta";  dc_caps = [];                        dc_installed = true } ]
  in
  Cmd_audit.write_baseline path deps;
  let read = Cmd_audit.read_baseline path in
  rm_rf dir;
  Alcotest.(check (list (pair string (list string))))
    "round-trips names and capability sets, including the empty set"
    [ ("alpha", ["IO.FileRead"; "IO.Net"]); ("beta", []) ]
    read

let test_baseline_missing_file_is_empty () =
  Alcotest.(check (list (pair string (list string))))
    "absent baseline reads as empty, not an error"
    [] (Cmd_audit.read_baseline "/nonexistent/forge.caps.lock")

(* ------------------------------------------------------------------ *)
(*  Diff and the escalation rule                                       *)
(* ------------------------------------------------------------------ *)

let dep name caps =
  { Cmd_audit.dc_name = name; dc_caps = caps; dc_installed = true }

let test_diff_detects_widening () =
  let changes =
    Cmd_audit.diff
      ~baseline:[ ("liba", ["IO.FileRead"]) ]
      ~current:[ dep "liba" ["IO.FileRead"; "IO.FileWrite"; "IO.NetConnect"] ]
  in
  Alcotest.(check bool) "reports a widening" true
    (List.exists (function
         | Cmd_audit.Widened ("liba", caps) ->
           caps = ["IO.FileWrite"; "IO.NetConnect"]
         | _ -> false) changes);
  Alcotest.(check bool) "widening is an escalation" true
    (List.exists Cmd_audit.is_escalation changes)

let test_diff_narrowing_is_not_an_escalation () =
  (* Losing a capability is the direction you want; reporting it is useful,
     failing the build for it would train people to ignore the gate. *)
  let changes =
    Cmd_audit.diff
      ~baseline:[ ("liba", ["IO.FileRead"; "IO.NetConnect"]) ]
      ~current:[ dep "liba" ["IO.FileRead"] ]
  in
  Alcotest.(check bool) "reports the narrowing" true
    (List.exists (function
         | Cmd_audit.Narrowed ("liba", ["IO.NetConnect"]) -> true
         | _ -> false) changes);
  Alcotest.(check bool) "but it does not fail the audit" false
    (List.exists Cmd_audit.is_escalation changes)

let test_diff_new_dependency_with_caps_escalates () =
  let changes =
    Cmd_audit.diff ~baseline:[] ~current:[ dep "newdep" ["IO.Process"] ]
  in
  Alcotest.(check bool) "a new dependency carrying capabilities escalates" true
    (List.exists Cmd_audit.is_escalation changes)

let test_diff_new_dependency_without_caps_does_not_escalate () =
  let changes = Cmd_audit.diff ~baseline:[] ~current:[ dep "pure" [] ] in
  Alcotest.(check bool) "a new capability-free dependency is not an escalation" false
    (List.exists Cmd_audit.is_escalation changes)

let test_diff_removed_dependency_does_not_escalate () =
  let changes = Cmd_audit.diff ~baseline:[ ("gone", ["IO.Net"]) ] ~current:[] in
  Alcotest.(check bool) "removal is reported" true
    (List.exists (function Cmd_audit.Removed "gone" -> true | _ -> false) changes);
  Alcotest.(check bool) "removal does not fail the audit" false
    (List.exists Cmd_audit.is_escalation changes)

let test_diff_unchanged_is_empty () =
  let changes =
    Cmd_audit.diff
      ~baseline:[ ("liba", ["IO.FileRead"]) ]
      ~current:[ dep "liba" ["IO.FileRead"] ]
  in
  Alcotest.(check int) "no changes when the capability set matches" 0
    (List.length changes)

let () =
  Alcotest.run "forge-audit"
    [ ( "capability extraction",
        [ Alcotest.test_case "collects needs across files" `Quick
            test_caps_of_dir_collects_needs;
          Alcotest.test_case "finds needs in a nested module" `Quick
            test_caps_of_dir_finds_nested_module_needs;
          Alcotest.test_case "empty without needs" `Quick
            test_caps_of_dir_empty_without_needs;
          Alcotest.test_case "ignores an unparseable file" `Quick
            test_caps_of_dir_ignores_unparseable_file ] );
      ( "baseline",
        [ Alcotest.test_case "round-trips" `Quick test_baseline_roundtrip;
          Alcotest.test_case "missing file reads empty" `Quick
            test_baseline_missing_file_is_empty ] );
      ( "diff",
        [ Alcotest.test_case "detects widening" `Quick test_diff_detects_widening;
          Alcotest.test_case "narrowing is not an escalation" `Quick
            test_diff_narrowing_is_not_an_escalation;
          Alcotest.test_case "new dep with caps escalates" `Quick
            test_diff_new_dependency_with_caps_escalates;
          Alcotest.test_case "new dep without caps does not" `Quick
            test_diff_new_dependency_without_caps_does_not_escalate;
          Alcotest.test_case "removal does not escalate" `Quick
            test_diff_removed_dependency_does_not_escalate;
          Alcotest.test_case "unchanged is empty" `Quick test_diff_unchanged_is_empty ] ) ]
