(* forge top's and forge status's rendering (forge/lib/cmd_observe.ml) over
   fixture snapshots, without a node: the one-line summary, the top frame,
   and the status JSON. The live end-to-end (a real compiled node) is
   test/dune's native_diagnose_runaway. *)
open March_forge

let fixture name =
  let dir = List.find Sys.file_exists
      [ "fixtures/diagnose"; "forge/test/fixtures/diagnose"; "../fixtures/diagnose" ] in
  let j = Yojson.Safe.from_file (Filename.concat dir (name ^ ".json")) in
  match j with `Assoc kv -> List.assoc "after" kv | _ -> `Null

let contains s sub =
  try ignore (Str.search_forward (Str.regexp_string sub) s 0); true with Not_found -> false

let test_summary () =
  let s = Cmd_observe.reply_summary (fixture "mailbox_growth_critical") in
  Alcotest.(check int) "actors" 5 s.Cmd_observe.actors;
  Alcotest.(check int) "queued counts held messages" 5000 s.Cmd_observe.queued;
  (match s.Cmd_observe.deepest with
   | Some (pid, _, w) ->
     Alcotest.(check int) "deepest pid" 2 pid;
     Alcotest.(check int) "deepest waiting = mbox + held" 4000 w
   | None -> Alcotest.fail "a deepest mailbox expected");
  let line = Cmd_observe.summary_line s in
  Alcotest.(check bool) "line names the deepest mailbox" true (contains line "deepest mailbox W (pid 2) 4000");
  Alcotest.(check bool) "line has rss" true (contains line "rss 47 MB")

let test_crashes_hour () =
  let s = Cmd_observe.reply_summary (fixture "crash_loop_warning") in
  (* crashes 10, 20 and 30 minutes before the window: all within the hour. *)
  Alcotest.(check int) "crashes in the last hour" 3 s.Cmd_observe.crashes_hour;
  let healthy = Cmd_observe.reply_summary (fixture "healthy") in
  Alcotest.(check bool) "no deepest mailbox when every mailbox is empty" true
    (healthy.Cmd_observe.deepest = None)

let test_render_top () =
  let top = `Assoc [ "proto", `String "march.observe/1"; "data", `Assoc [
      "attr", `String "mbox"; "top", `List [
        `Assoc [ "pid", `Int 2; "value", `Int 4000; "type", `String "W";
                 "names", `List [ `String "queue" ]; "status", `String "waiting"; "mbox", `Int 4000 ] ] ] ] in
  let frame = Cmd_observe.render_top ~node:"n1" ~sort:"mbox" ~window_ms:None
      (Cmd_observe.reply_summary (fixture "mailbox_growth_critical")) top in
  Alcotest.(check bool) "header names the node" true (contains frame "n1  actors 5");
  Alcotest.(check bool) "row for pid 2" true (contains frame "queue");
  Alcotest.(check bool) "column header" true (contains frame "MBOX")

let test_top_supervision () =
  let child = `Assoc [ "pid", `Int 7; "value", `Int 16384; "type", `String "Counter"; "names", `List [];
                        "status", `String "waiting"; "mbox", `Int 0; "stack_bytes", `Int 16384;
                        "crashes", `Int 0; "child_crashes", `Int 0; "children", `Int 0;
                        "link", `String "supervised"; "parent", `Int 3; "parent_type", `String "Sup";
                        "spawned_by", `Null; "supervisor", `Null ] in
  let sup = `Assoc [ "pid", `Int 3; "value", `Int 16384; "type", `String "Sup"; "names", `List [ `String "boss" ];
                      "status", `String "waiting"; "mbox", `Int 0; "stack_bytes", `Int 16384;
                      "crashes", `Int 0; "child_crashes", `Int 2; "children", `Int 4;
                      "link", `String "none"; "parent", `Null; "parent_type", `Null; "spawned_by", `Null;
                      "supervisor", `Assoc [ "strategy", `String "one_for_one"; "max_restarts", `Int 5;
                                             "window_secs", `Int 60; "restarts_held", `Int 1 ] ] in
  let twig = `Assoc [ "pid", `Int 9; "value", `Int 0; "type", `Null; "names", `List []; "status", `String "waiting";
                      "mbox", `Int 0; "link", `String "spawned"; "parent", `Null; "spawned_by", `Int 3 ] in
  let c = Cmd_observe.top_row_line child and s = Cmd_observe.top_row_line sup
  and t = Cmd_observe.top_row_line twig in
  Alcotest.(check bool) "a supervised child names its supervisor and type" true
    (contains c "supervised" && contains c "3 (Sup)" && not (contains c "kids"));
  Alcotest.(check bool) "a supervisor shows policy, restarts held/max and crashes" true
    (contains s "one_for_one 1/5 in 60s, 4 kids" && contains s "boss");
  Alcotest.(check bool) "crashes column adds the children's" true (contains s "       2  none");
  Alcotest.(check bool) "an unsupervised spawned actor names its spawner; old nodes' missing fields read 0" true
    (contains t "spawned by 3" && contains t "spawned")

let test_status_json () =
  let j = Cmd_observe.summary_json (Cmd_observe.reply_summary (fixture "mailbox_growth_critical")) in
  let s = Yojson.Safe.to_string j in
  Alcotest.(check bool) "deepest in JSON" true (contains s "\"deepest\":{\"pid\":2");
  Alcotest.(check bool) "queued in JSON" true (contains s "\"queued\":5000")

let () =
  Alcotest.run "observe_cli" [
    "summary", [
      Alcotest.test_case "figures and line" `Quick test_summary;
      Alcotest.test_case "crashes in the last hour; empty mailboxes" `Quick test_crashes_hour;
    ];
    "render", [
      Alcotest.test_case "top frame" `Quick test_render_top;
      Alcotest.test_case "top supervision columns" `Quick test_top_supervision;
      Alcotest.test_case "status JSON" `Quick test_status_json;
    ];
  ]
