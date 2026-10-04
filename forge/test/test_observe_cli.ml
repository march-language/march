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
      Alcotest.test_case "status JSON" `Quick test_status_json;
    ];
  ]
