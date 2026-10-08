(* forge diagnose's findings (forge/lib/diagnose.ml) against the shared
   fixtures in forge/test/fixtures/diagnose: each fixture must produce exactly
   the ids its expected.txt line names. stdlib/diagnose.march is tested
   against the same file (test/dune, native_diagnose_fixtures), so the March
   and OCaml findings cannot drift apart. *)
open March_forge

let fixture_dir () =
  List.find Sys.file_exists
    [ "fixtures/diagnose"; "forge/test/fixtures/diagnose"; "../fixtures/diagnose" ]

let expected () =
  In_channel.with_open_bin (Filename.concat (fixture_dir ()) "expected.txt") In_channel.input_all
  |> String.split_on_char '\n'
  |> List.filter (fun l -> l <> "")
  |> List.map (fun l ->
      match String.index_opt l ':' with
      | Some i ->
        let name = String.sub l 0 i in
        let rest = String.trim (String.sub l (i + 1) (String.length l - i - 1)) in
        (name, if rest = "" then [] else String.split_on_char ',' rest)
      | None -> failwith ("bad expected.txt line: " ^ l))

let run_fixture name =
  let j = Yojson.Safe.from_file (Filename.concat (fixture_dir ()) (name ^ ".json")) in
  let m k = match j with `Assoc kv -> List.assoc k kv | _ -> `Null in
  Diagnose.run ~before:(m "before") ~after:(m "after")

let test_fixture (name, want) () =
  Alcotest.(check (list string)) name want (Diagnose.ids (run_fixture name))

let test_exit_codes () =
  Alcotest.(check int) "healthy -> 0" 0 (Diagnose.exit_code (run_fixture "healthy"));
  Alcotest.(check int) "warning -> 1" 1 (Diagnose.exit_code (run_fixture "rc_climb"));
  Alcotest.(check int) "critical -> 2" 2 (Diagnose.exit_code (run_fixture "crash_loop_critical"))

let test_envelope () =
  let fixture = Yojson.Safe.from_file (Filename.concat (fixture_dir ()) "mailbox_growth_critical.json") in
  let m k = match fixture with `Assoc kv -> List.assoc k kv | _ -> `Null in
  let before = m "before" and after = m "after" in
  let j = Diagnose.to_json ~node:"n1" ~window_ms:1000 ~before ~after
      (Diagnose.run ~before ~after) in
  let m k = match j with `Assoc kv -> List.assoc k kv | _ -> `Null in
  Alcotest.(check string) "proto" "\"march.diagnose/1\"" (Yojson.Safe.to_string (m "proto"));
  let cov = Yojson.Safe.to_string (m "coverage") in
  Alcotest.(check bool) "coverage names what could not run" true
    (let has s = try ignore (Str.search_forward (Str.regexp_string s) cov 0); true with Not_found -> false in
     has "cluster.suspect" && has "names.lost" && has "mailbox.growth");
  match m "findings" with
  | `List [ f ] ->
    let rows = match f with `Assoc kv -> List.assoc "rows" kv | _ -> `Null in
    Alcotest.(check bool) "the finding carries its rows" true (rows <> `List [])
  | _ -> Alcotest.fail "one finding expected"

let test_capped_coverage () =
  let capped = Yojson.Safe.from_string
      {|{"data":{"actors":{"total":101,"shown":100},"crashes":{"total":21,"crashes":[]}}}|} in
  Alcotest.(check (list (pair string string))) "capped snapshot coverage"
    [ "actors", "shown 100 of 101"; "crashes", "shown 0 of 21" ]
    (Diagnose.coverage ~before:capped ~after:capped)

let () =
  Alcotest.run "diagnose" [
    "fixtures", List.map (fun (n, w) -> Alcotest.test_case n `Quick (test_fixture (n, w))) (expected ());
    "output", [
      Alcotest.test_case "exit codes" `Quick test_exit_codes;
      Alcotest.test_case "envelope and coverage" `Quick test_envelope;
      Alcotest.test_case "capped snapshot coverage" `Quick test_capped_coverage;
    ];
  ]
