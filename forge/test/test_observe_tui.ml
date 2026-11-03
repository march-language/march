(* forge observe's panels (forge/lib/observe_tui.ml) rendered to text over
   fixture replies, with no terminal: one golden per panel, for a live reply
   and for a crash dump.  The fixtures are replies recorded from a real node
   (test/native/observe_crashes.march, run with MARCH_OBSERVE_SOCKET) and a
   real crash dump (test/native/crash_dump.march, run with MARCH_CRASH_DUMP),
   with a few fields edited so the Epochs and Cluster panels have something
   to show (see the file names).  The terminal loop and the WATCH stream are
   exercised by test/shell/observe_tui_pty.py and test/test_observe.c.

   After an intentional change to a panel:
     UPDATE_OBSERVE_TUI=1 ./_build/default/forge/test/test_observe_tui.exe -e
   then review `git diff forge/test/fixtures/observe_tui/`. *)
open March_forge
module T = Observe_tui

let fixture_dir () =
  List.find Sys.file_exists
    [ "fixtures/observe_tui"; "forge/test/fixtures/observe_tui"; "../fixtures/observe_tui" ]

let json name = Yojson.Safe.from_file (Filename.concat (fixture_dir ()) (name ^ ".json"))

let read file = In_channel.with_open_bin file In_channel.input_all

(** Where the goldens are rewritten: the source tree, when dune says where it is. *)
let source_dir () =
  match Sys.getenv_opt "DUNE_SOURCEROOT" with
  | Some root -> Filename.concat root "forge/test/fixtures/observe_tui"
  | None -> fixture_dir ()

let golden name text =
  let path = Filename.concat (fixture_dir ()) (name ^ ".expected") in
  if Sys.getenv_opt "UPDATE_OBSERVE_TUI" <> None then
    Out_channel.with_open_bin (Filename.concat (source_dir ()) (name ^ ".expected"))
      (fun oc -> output_string oc text)
  else if not (Sys.file_exists path) then
    Alcotest.failf "no golden %s (UPDATE_OBSERVE_TUI=1 creates it); rendered:\n%s" path text
  else Alcotest.(check string) name (read path) text

let ctx = { T.default_ctx with T.width = 130; height = 30 }
let render ?(ctx = ctx) panel reply = T.panel_text ~ctx panel reply
let contains s sub =
  try ignore (Str.search_forward (Str.regexp_string sub) s 0); true with Not_found -> false

(* ── Live panels ─────────────────────────────────────────────────────── *)

let test_system () = golden "system" (render T.System (json "snapshot"))

let test_load () =
  let history = [ 0.05; 0.1; 0.4; 0.9; 1.0; 0.6; 0.2; 0.0 ] in
  golden "load" (render ~ctx:{ ctx with T.history } T.Load (json "snapshot"))

let test_actors_top () = golden "actors_top" (render ~ctx:{ ctx with T.selected = 1 } T.Actors (json "top"))

let test_actors_snapshot () =
  (* No TOP reply: the snapshot's rows, ranked here. *)
  golden "actors_snapshot_stack" (render ~ctx:{ ctx with T.sort = "stack" } T.Actors (json "snapshot"));
  golden "actors_snapshot_crashes" (render ~ctx:{ ctx with T.sort = "crashes" } T.Actors (json "snapshot"))

let test_actor () = golden "actor" (render T.Actor (json "actor"))

let test_actor_none () = golden "actor_none" (render T.Actor (`Assoc [ "data", `Null ]))

let test_supervision () =
  golden "supervision" (render ~ctx:{ ctx with T.selected = 2 } T.Supervision (json "snapshot"))

let test_names () = golden "names" (render T.Names (json "snapshot"))
let test_epochs () = golden "epochs" (render T.Epochs (json "snapshot"))
let test_cluster () = golden "cluster" (render T.Cluster (json "cluster"))

let test_cluster_unavailable () =
  golden "cluster_unavailable" (render T.Cluster (json "cluster_unavailable"));
  golden "cluster_no_verb" (render T.Cluster (`Assoc [ "data", `Null ]))

let test_crashes () = golden "crashes" (render T.Crashes (json "snapshot"))

let test_empty () =
  let e = json "empty" in
  golden "empty_actors" (render T.Actors e);
  golden "empty_supervision" (render T.Supervision e);
  golden "empty_names" (render T.Names e);
  golden "empty_epochs" (render T.Epochs e);
  golden "empty_crashes" (render T.Crashes e);
  golden "waiting" (render T.System `Null)

(* ── Crash dumps ─────────────────────────────────────────────────────── *)

let dump () =
  match T.load_dump (Filename.concat (fixture_dir ()) "crash_dump.json") with
  | Ok d -> d
  | Error m -> Alcotest.fail m

let dump_ctx = { ctx with T.dump = true }

let test_dump_panels () =
  let d = dump () in
  golden "dump_banner" (T.dump_banner d ^ "\n");
  List.iter (fun p ->
      golden ("dump_" ^ String.lowercase_ascii (T.title p)) (render ~ctx:dump_ctx p d.T.reply)) T.all_panels

let test_dump_message_text () =
  let d = dump () in
  let crashes = render ~ctx:dump_ctx T.Crashes d.T.reply in
  Alcotest.(check bool) "the dump's crash ring carries the panic message" true
    (contains crashes "dump-main-panic-xyzzy" && contains crashes "dump-child-crash-xyzzy");
  let live = render T.Crashes (json "snapshot") in
  Alcotest.(check bool) "a live reply never does" false (contains live "xyzzy");
  Alcotest.(check bool) "and says where to get it" true (contains live "--crashes-full")

let test_dump_live_only_greyed () =
  let d = dump () in
  Alcotest.(check bool) "Actor is live-only" true (T.live_only T.Actor && T.live_only T.Cluster);
  Alcotest.(check bool) "Actors is not" false (T.live_only T.Actors);
  List.iter (fun p ->
      let t = render ~ctx:dump_ctx p d.T.reply in
      Alcotest.(check bool) (T.title p ^ " says it is live-only") true (contains t "live-only"))
    [ T.Actor; T.Cluster ]

let test_parse_dump_errors () =
  let err s = match T.parse_dump s with Error m -> m | Ok _ -> Alcotest.fail ("accepted: " ^ s) in
  Alcotest.(check bool) "not JSON" true (contains (err "{oops") "not valid JSON");
  Alcotest.(check bool) "wrong proto" true (contains (err {|{"proto":"march.observe/1"}|}) "not a crash dump");
  Alcotest.(check bool) "a truncated snapshot" true
    (contains (err {|{"proto":"march.observe.dump/1","snapshot":null}|}) "no usable snapshot");
  Alcotest.(check bool) "not an object" true (contains (err "[1]") "not a JSON object")

(** The merge: messages are attached by [seq], and the ring wins over the
    snapshot's own (capped) crashes section. *)
let test_dump_merge () =
  let text = {|{"proto":"march.observe.dump/1","reason":"abort","at_ms":5,"pid":9,
    "snapshot":{"proto":"march.observe/1","node":"n","at_ms":5,"data":{"crashes":{"total":1,"crashes":[{"seq":7,"kind":"panic"}]}}},
    "crashes_total":2,
    "crashes_full":[{"seq":8,"kind":"panic","pid":null,"message":"later"},{"seq":7,"kind":"crash","pid":3,"message":"earlier"}]}|} in
  match T.parse_dump text with
  | Error m -> Alcotest.fail m
  | Ok d ->
    Alcotest.(check string) "reason" "abort" d.T.reason;
    let es = T.crash_entries d.T.reply in
    Alcotest.(check int) "ring entries" 2 (List.length es);
    Alcotest.(check (list string)) "messages by seq" [ "later"; "earlier" ]
      (List.map (fun e -> T.js (T.jm "message" e)) es);
    Alcotest.(check int) "total comes from the ring" 2 (T.ji (T.jm "total" (T.section "crashes" d.T.reply)))

(* ── Behaviour of the pieces the loop uses ───────────────────────────── *)

let test_selectable () =
  let snap = json "snapshot" and top = json "top" in
  Alcotest.(check (list int)) "Actors follows the TOP order"
    (List.map (fun r -> T.ji (T.jm "pid" r)) (T.jl (T.jm "top" (T.data_of top))))
    (T.selectable T.Actors top);
  Alcotest.(check bool) "Supervision lists tree nodes depth-first" true
    (T.selectable T.Supervision snap = [ 1; 4; 6; 7; 8 ]);
  Alcotest.(check int) "Crashes: one per ring entry" 3 (List.length (T.selectable T.Crashes snap));
  Alcotest.(check (list int)) "System has none" [] (T.selectable T.System snap);
  let d = dump () in
  Alcotest.(check bool) "a panic outside any actor has no pid to open" true
    (List.mem (-1) (T.selectable T.Crashes d.T.reply))

let test_sorts_and_requests () =
  Alcotest.(check string) "s cycles" "stack" (T.next_sort "mbox");
  Alcotest.(check string) "and wraps" "mbox" (T.next_sort "msgs_out");
  Alcotest.(check (option string)) "Actors asks TOP" (Some "TOP stack 100")
    (T.request_of ~sort:"stack" ~pid:None T.Actors);
  Alcotest.(check (option string)) "Actor asks ACTOR <pid>" (Some "ACTOR 7")
    (T.request_of ~sort:"mbox" ~pid:(Some 7) T.Actor);
  Alcotest.(check (option string)) "Actor with no pid asks nothing" None
    (T.request_of ~sort:"mbox" ~pid:None T.Actor);
  Alcotest.(check (option string)) "Cluster asks CLUSTER" (Some "CLUSTER")
    (T.request_of ~sort:"mbox" ~pid:None T.Cluster);
  Alcotest.(check (option string)) "System reads the stream" None
    (T.request_of ~sort:"mbox" ~pid:None T.System);
  Alcotest.(check bool) "panels by name" true (T.panel_of_string "SUPERVISION" = Some T.Supervision);
  Alcotest.(check bool) "unknown panel" true (T.panel_of_string "trace" = None)

(** Names and panic text come from the node: no control character may reach
    the terminal, and a long one is cut, not wrapped. *)
let test_hostile_text () =
  let row name = `Assoc [ "pid", `Int 1; "type", `String "T"; "names", `List [ `String name ];
                           "status", `String "waiting"; "mbox", `Int 0; "value", `Int 0;
                           "stack_bytes", `Int 0; "crashes", `Int 0; "child_crashes", `Int 0;
                           "children", `Int 0; "link", `String "none" ] in
  let reply = `Assoc [ "data", `Assoc [ "total", `Int 1; "top", `List [ row "evil\027[2J\nname" ] ] ] in
  let t = render T.Actors reply in
  Alcotest.(check bool) "no escape byte survives" false (String.contains t '\027');
  Alcotest.(check int) "the newline did not add a row" 4 (List.length (String.split_on_char '\n' t));
  let crash msg = `Assoc [ "data", `Assoc [ "crashes", `Assoc [ "total", `Int 1; "crashes", `List [
      `Assoc [ "seq", `Int 1; "kind", `String "panic"; "pid", `Null; "type", `Null; "supervisor", `Null;
               "restart", `Int 0; "at_ms", `Int 0; "message", `String msg ] ] ] ] ] in
  let t = render T.Crashes (crash ("boom\027]0;owned\007\n" ^ String.make 400 'x')) in
  Alcotest.(check bool) "panic text: no escape or bell" false (String.contains t '\027' || String.contains t '\007');
  Alcotest.(check bool) "and cut to the width" true
    (List.for_all (fun l -> String.length l <= 130) (String.split_on_char '\n' t))

let test_panel_widths () =
  (* A narrow terminal crops; nothing is wider than asked for. *)
  List.iter (fun w ->
      let c = { ctx with T.width = w } in
      List.iter (fun p ->
          let t = render ~ctx:c p (json "snapshot") in
          List.iter (fun l ->
              if String.length l > w then
                Alcotest.failf "%s at width %d has a %d-wide line: %s" (T.title p) w (String.length l) l)
            (String.split_on_char '\n' t)) [ T.System; T.Load; T.Supervision; T.Names; T.Epochs; T.Crashes ])
    [ 40; 60; 80 ]

let () =
  Alcotest.run "observe_tui" [
    "panels", [
      Alcotest.test_case "system" `Quick test_system;
      Alcotest.test_case "load" `Quick test_load;
      Alcotest.test_case "actors (TOP reply)" `Quick test_actors_top;
      Alcotest.test_case "actors (snapshot rows)" `Quick test_actors_snapshot;
      Alcotest.test_case "actor" `Quick test_actor;
      Alcotest.test_case "actor, none selected" `Quick test_actor_none;
      Alcotest.test_case "supervision" `Quick test_supervision;
      Alcotest.test_case "names" `Quick test_names;
      Alcotest.test_case "epochs" `Quick test_epochs;
      Alcotest.test_case "cluster" `Quick test_cluster;
      Alcotest.test_case "cluster, unavailable" `Quick test_cluster_unavailable;
      Alcotest.test_case "crashes" `Quick test_crashes;
      Alcotest.test_case "empty node" `Quick test_empty;
      Alcotest.test_case "narrow terminals" `Quick test_panel_widths;
      Alcotest.test_case "hostile text" `Quick test_hostile_text;
    ];
    "crash dump", [
      Alcotest.test_case "every panel" `Quick test_dump_panels;
      Alcotest.test_case "message text only in a dump" `Quick test_dump_message_text;
      Alcotest.test_case "live-only panels greyed" `Quick test_dump_live_only_greyed;
      Alcotest.test_case "malformed dumps" `Quick test_parse_dump_errors;
      Alcotest.test_case "ring merged by seq" `Quick test_dump_merge;
    ];
    "loop pieces", [
      Alcotest.test_case "selectable rows" `Quick test_selectable;
      Alcotest.test_case "sorts and requests" `Quick test_sorts_and_requests;
    ];
  ]
