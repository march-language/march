open March_forge

let schema ty = `Assoc ["Counter", `Assoc ["state_fields", `List [
  `Assoc ["name", `String "value"; "ty", `String ty]]]]
let releases seq id = `Assoc ["Counter", `Assoc ["seq", seq; "id", `String id]]
let response schemas releases = "SCHEMAS " ^ Yojson.Safe.to_string
    (`Assoc ["version", `Int 1; "schemas", schemas; "releases", releases])
let base = releases (`Int 0) "-"
let release_id = String.make 32 'a'

let with_file json f =
  let path = Filename.temp_file "march-schema-baseline-" ".json" in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    Yojson.Safe.to_file path json;
    f path)

(* A real stream exchange: the fake server requires the exact read-only query.
   None closes the stream after the request to test transport failure. *)
let query reply local_path =
  let client, server = Unix.socketpair Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  match Unix.fork () with
  | 0 ->
    Unix.close client;
    let conn = Cmd_deploy_hot.conn_of_fd server in
    let code = try
        if Cmd_deploy_hot.recv_line conn <> "SCHEMAS" then 2
        else (Option.iter (Cmd_deploy_hot.send_line conn) reply; 0)
      with _ -> 3 in
    Unix.close server;
    Unix._exit code
  | pid ->
    Unix.close server;
    Fun.protect ~finally:(fun () ->
      Unix.close client;
      let _, status = Unix.waitpid [] pid in
      Alcotest.(check bool) "server received SCHEMAS" true (status = Unix.WEXITED 0))
      (fun () -> Cmd_deploy_hot.running_schemas
          (Cmd_deploy_hot.conn_of_fd client) ~local_path)

let expect_error = function
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "expected refusal"
let expect_schema expected = function
  | Ok actual -> Alcotest.(check string) "schema" (Yojson.Safe.to_string expected)
      (Yojson.Safe.to_string actual)
  | Error m -> Alcotest.fail m

let test_known_empty () =
  query (Some (response (`Assoc []) (`Assoc []))) "" |> expect_schema (`Assoc [])

let test_unavailable_without_prior () =
  List.iter (fun reply ->
    match query (Some reply) "" with
    | Error m -> Alcotest.(check bool) "actionable legacy refusal" true
        (String.contains m '-' && String.length m > 30)
    | Ok _ -> Alcotest.fail "unknown baseline admitted")
    ["ERR unknown_command"; "ERR schemas_unavailable"]

let test_legacy_explicit_file () =
  with_file (schema "Int") (fun path ->
    query (Some "ERR unknown_command") path |> expect_schema (schema "Int"))

let test_malformed_no_fallback () =
  with_file (schema "Int") (fun path ->
    List.iter (fun reply -> query (Some reply) path |> expect_error)
      ["SCHEMAS {bad"; "SCHEMAS {}"; "ERR read_failed";
       response (schema "Int") (`Assoc []);
       response (schema "Int") (releases (`Int (-1)) release_id);
       response (schema "Int") (releases (`Int 1) "-");
       response (schema "Int") (releases (`Int 0) release_id);
       response (schema "Int") (releases (`String "1") release_id)])

let test_transport_no_fallback () =
  with_file (schema "Int") (fun path ->
    let failed = try ignore (query None path); false with Failure _ -> true in
    Alcotest.(check bool) "transport failure refuses" true failed)

let test_stale_local () =
  with_file (schema "String") (fun path ->
    let log = Filename.temp_file "march-schema-warning-" ".log" in
    let saved = Unix.dup Unix.stderr in
    let fd = Unix.openfile log [Unix.O_WRONLY; Unix.O_TRUNC] 0o600 in
    Fun.protect ~finally:(fun () ->
      flush stderr; Unix.dup2 saved Unix.stderr; Unix.close saved;
      Unix.close fd; Sys.remove log) (fun () ->
        Unix.dup2 fd Unix.stderr;
        query (Some (response (schema "Int") (releases (`Int 7) release_id))) path
        |> expect_schema (schema "Int");
        flush stderr;
        let warning = In_channel.with_open_bin log In_channel.input_all in
        Alcotest.(check bool) "stale baseline warning" true
          (try ignore (Str.search_forward (Str.regexp_string "local schema baseline is stale") warning 0); true
           with Not_found -> false)))

let test_provenance () =
  List.iter (fun release ->
    match Cmd_deploy_hot.parse_schema_response (response (schema "Int") release) with
    | Ok (Some _) -> () | _ -> Alcotest.fail "valid provenance rejected")
    [base; releases (`Int 8) release_id;
     releases (`Intlit "18446744073709551614") release_id];
  List.iter (fun release ->
    Cmd_deploy_hot.parse_schema_response (response (schema "Int") release) |> expect_error)
    [`Null; `Assoc []; releases (`Float 1.) release_id;
     releases (`Intlit "18446744073709551615") release_id;
     releases (`Int 2) (String.make 32 'z');
     `Assoc ["Other", `Assoc ["seq", `Int 0; "id", `String "-"]];
     `Assoc ["Counter", `Assoc ["seq", `Int 0; "seq", `Int 1; "id", `String "-"]]]

let () = Alcotest.run "schema baseline" ["socket", [
  Alcotest.test_case "known empty" `Quick test_known_empty;
  Alcotest.test_case "unavailable without prior" `Quick test_unavailable_without_prior;
  Alcotest.test_case "explicit legacy baseline" `Quick test_legacy_explicit_file;
  Alcotest.test_case "malformed does not fallback" `Quick test_malformed_no_fallback;
  Alcotest.test_case "transport does not fallback" `Quick test_transport_no_fallback;
  Alcotest.test_case "stale local warns" `Quick test_stale_local;
  Alcotest.test_case "release provenance" `Quick test_provenance]]
