(* End-to-end JSON-RPC integration tests: spawn the real march-lsp binary,
   speak LSP over stdio with Content-Length framing, and assert protocol
   responses. This is the one layer the transport-free unit tests cannot reach
   (server.ml / main.ml dispatch, capabilities, framing). *)

(* Resolve the server binary relative to THIS test executable (cwd-independent,
   works under both `dune runtest` and `dune exec`): test is at
   .../lsp/test/test_jsonrpc.exe, the server at .../lsp/bin/main.exe. *)
let exe = Filename.concat (Filename.dirname Sys.executable_name) "../bin/main.exe"

(* ── Content-Length framing over the process pipes ────────────────────────── *)

let send oc (json : Yojson.Safe.t) =
  let body = Yojson.Safe.to_string json in
  Printf.fprintf oc "Content-Length: %d\r\n\r\n%s" (String.length body) body;
  flush oc

let read_frame ic : Yojson.Safe.t option =
  let strip_cr s =
    let n = String.length s in
    if n > 0 && s.[n - 1] = '\r' then String.sub s 0 (n - 1) else s
  in
  let rec headers len =
    match input_line ic with
    | exception End_of_file -> len
    | line ->
      let line = strip_cr line in
      if line = "" then len
      else
        let len =
          match String.split_on_char ':' line with
          | k :: rest when String.lowercase_ascii (String.trim k) = "content-length" ->
            (try int_of_string (String.trim (String.concat ":" rest)) with _ -> len)
          | _ -> len
        in
        headers len
  in
  let len = headers (-1) in
  if len < 0 then None
  else begin
    let buf = Bytes.create len in
    really_input ic buf 0 len;
    Some (Yojson.Safe.from_string (Bytes.to_string buf))
  end

(* Read frames until [pred] matches one (returns it) or [max] frames seen. *)
let read_until ic ~max pred : Yojson.Safe.t option =
  let rec loop n =
    if n <= 0 then None
    else match read_frame ic with
      | None -> None
      | Some j -> if pred j then Some j else loop (n - 1)
  in
  loop max

let member k j = match j with `Assoc l -> (try List.assoc k l with Not_found -> `Null) | _ -> `Null
let is_method m j = member "method" j = `String m
let is_id i j = member "id" j = `Int i

(* ── The test ─────────────────────────────────────────────────────────────── *)

let run_session () =
  (* Guard against a hung server: abort the whole test after 25s. *)
  Sys.set_signal Sys.sigalrm
    (Sys.Signal_handle (fun _ -> failwith "march-lsp did not respond (timeout)"));
  ignore (Unix.alarm 25);
  let (ic, oc, ec) = Unix.open_process_args_full exe [| exe |] (Unix.environment ()) in

  (* 1. initialize *)
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "id", `Int 1; "method", `String "initialize";
    "params", `Assoc [ "processId", `Null; "rootUri", `Null;
                       "capabilities", `Assoc [] ] ]);
  let init = read_until ic ~max:30 (is_id 1) in
  let init_ok =
    match init with
    | Some j -> member "result" j <> `Null && member "capabilities" (member "result" j) <> `Null
    | None -> false
  in

  (* 2. initialized + didOpen a buffer with a type error (Bool vs Int) *)
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "initialized";
                    "params", `Assoc [] ]);
  let uri = "file:///bad.march" in
  let text = "mod M do\n  fn f() : Int do true end\nend\n" in
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "method", `String "textDocument/didOpen";
    "params", `Assoc [ "textDocument", `Assoc [
      "uri", `String uri; "languageId", `String "march";
      "version", `Int 1; "text", `String text ] ] ]);
  let diags = read_until ic ~max:30 (is_method "textDocument/publishDiagnostics") in
  let diags_nonempty =
    match diags with
    | Some j -> (match member "diagnostics" (member "params" j) with
                 | `List (_ :: _) -> true | _ -> false)
    | None -> false
  in

  (* 3. hover on the function name `f` (line 1, char 5) *)
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "id", `Int 2; "method", `String "textDocument/hover";
    "params", `Assoc [
      "textDocument", `Assoc [ "uri", `String uri ];
      "position", `Assoc [ "line", `Int 1; "character", `Int 5 ] ] ]);
  let hover = read_until ic ~max:30 (is_id 2) in
  let hover_ok =
    match hover with
    | Some j -> member "result" j <> `Null  (* hover returned contents, not null *)
    | None -> false
  in

  (* 4. shutdown/exit so the process terminates cleanly *)
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "id", `Int 3;
                    "method", `String "shutdown"; "params", `Null ]);
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "exit";
                    "params", `Null ]);
  (try ignore (Unix.close_process_full (ic, oc, ec)) with _ -> ());
  ignore (Unix.alarm 0);
  (init_ok, diags_nonempty, hover_ok)

let test_full_session () =
  let (init_ok, diags_nonempty, hover_ok) = run_session () in
  Alcotest.(check bool) "initialize returns capabilities" true init_ok;
  Alcotest.(check bool) "didOpen publishes a diagnostic for the type error"
    true diags_nonempty;
  Alcotest.(check bool) "hover on a function returns contents" true hover_ok

(* ── workspace/executeCommand reaches a real handler ──────────────────────────
   Regression guard for a whole feature that shipped dead. linol dispatches
   `workspace/executeCommand` as a KNOWN client request, so a handler placed in
   [on_unknown_request] is never reached and linol's default returns `null`.
   Both the runnable code lenses (`march.runTest`, `march.debug`, …) and
   `march.suggestRefinement` were in that position, so NONE of them had ever
   worked — invisible to every unit test, because a command is only observable
   through a live protocol session.

   Asserting on a DELIBERATELY UNKNOWN command id is the point: it needs no
   project on disk, no solver and no shell-out, yet it can only produce the
   structured payload below if [on_req_execute_command] is actually being
   dispatched to. A `null` here means the handler has come unwired again. *)
let run_execute_command () =
  Sys.set_signal Sys.sigalrm
    (Sys.Signal_handle (fun _ -> failwith "march-lsp did not respond (timeout)"));
  ignore (Unix.alarm 25);
  let (ic, oc, ec) = Unix.open_process_args_full exe [| exe |] (Unix.environment ()) in
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "id", `Int 1; "method", `String "initialize";
    "params", `Assoc [ "processId", `Null; "rootUri", `Null;
                       "capabilities", `Assoc [] ] ]);
  ignore (read_until ic ~max:30 (is_id 1));
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "initialized";
                    "params", `Assoc [] ]);
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "id", `Int 2;
    "method", `String "workspace/executeCommand";
    "params", `Assoc [ "command", `String "march.definitelyNotACommand";
                       "arguments", `List [] ] ]);
  let reply = read_until ic ~max:30 (is_id 2) in
  let dispatched =
    match reply with
    | Some j ->
      let r = member "result" j in
      r <> `Null && member "kind" r = `String "unknown"
    | None -> false
  in
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "id", `Int 3;
                    "method", `String "shutdown"; "params", `Null ]);
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "exit";
                    "params", `Null ]);
  (try ignore (Unix.close_process_full (ic, oc, ec)) with _ -> ());
  ignore (Unix.alarm 0);
  dispatched

let test_execute_command_dispatches () =
  Alcotest.(check bool)
    "workspace/executeCommand reaches on_req_execute_command (not linol's null default)"
    true (run_execute_command ())

(* ── shutdown/exit must actually terminate the process ────────────────────────

   `Jsonrpc2.run` takes a `?shutdown` predicate whose own documentation says it
   should be `s#get_status = `ReceivedExit`. march-lsp passed none, so it
   defaulted to `fun _ -> false`: after handling the `exit` notification the
   loop went straight back to `read_msg` and blocked on stdin forever. The
   client has said goodbye and is waiting for the process to go away; instead it
   hangs until the editor's timeout kills it.

   Invisible to every other test here, because they all end with
   `close_process_full` — closing the pipes ends the server via EOF whether or
   not `exit` is honoured. This one must therefore NOT close the pipes, and
   instead observe the server closing its own stdout. *)
let run_exit_terminates () =
  let (ic, oc, ec) = Unix.open_process_args_full exe [| exe |] (Unix.environment ()) in
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "id", `Int 1; "method", `String "initialize";
    "params", `Assoc [ "processId", `Null; "rootUri", `Null;
                       "capabilities", `Assoc [] ] ]);
  ignore (read_until ic ~max:30 (is_id 1));
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "initialized";
                    "params", `Assoc [] ]);
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "id", `Int 2;
                    "method", `String "shutdown"; "params", `Null ]);
  ignore (read_until ic ~max:30 (is_id 2));
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "exit";
                    "params", `Null ]);
  Sys.set_signal Sys.sigalrm
    (Sys.Signal_handle
       (fun _ -> failwith "march-lsp did not exit after the `exit` notification"));
  ignore (Unix.alarm 10);
  let exited =
    match input_line ic with
    | exception End_of_file -> true   (* server closed its stdout: it exited *)
    | _ -> false                      (* still talking: it is still alive *)
  in
  ignore (Unix.alarm 0);
  (try ignore (Unix.close_process_full (ic, oc, ec)) with _ -> ());
  exited

let test_exit_terminates () =
  Alcotest.(check bool)
    "the `exit` notification terminates the server without closing its pipes"
    true (run_exit_terminates ())

(* ── textDocument/diagnostic (pull) ───────────────────────────────────────────
   The server advertises `diagnosticProvider`, so a conforming client may pull
   instead of relying on the push. Until this was implemented the request fell
   through to linol's `on_request_unhandled`, whose default fails with
   `TODO: handle this request` — every pull logged an error while push
   diagnostics quietly carried the feature, which is why it went unnoticed.

   Two cases, because "returns something" is not the property: a handler that
   always answers EMPTY would satisfy the first on its own. *)
let pull_diagnostics ~(text : string) ~(uri : string) : Yojson.Safe.t option =
  Sys.set_signal Sys.sigalrm
    (Sys.Signal_handle (fun _ -> failwith "march-lsp did not respond (timeout)"));
  ignore (Unix.alarm 25);
  let (ic, oc, ec) = Unix.open_process_args_full exe [| exe |] (Unix.environment ()) in
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "id", `Int 1; "method", `String "initialize";
    "params", `Assoc [ "processId", `Null; "rootUri", `Null;
                       "capabilities", `Assoc [] ] ]);
  ignore (read_until ic ~max:30 (is_id 1));
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "initialized";
                    "params", `Assoc [] ]);
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "method", `String "textDocument/didOpen";
    "params", `Assoc [ "textDocument", `Assoc [
      "uri", `String uri; "languageId", `String "march";
      "version", `Int 1; "text", `String text ] ] ]);
  ignore (read_until ic ~max:30 (is_method "textDocument/publishDiagnostics"));
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "id", `Int 2;
    "method", `String "textDocument/diagnostic";
    "params", `Assoc [ "textDocument", `Assoc [ "uri", `String uri ] ] ]);
  let reply = read_until ic ~max:30 (is_id 2) in
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "id", `Int 3;
                    "method", `String "shutdown"; "params", `Null ]);
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "exit";
                    "params", `Null ]);
  (try ignore (Unix.close_process_full (ic, oc, ec)) with _ -> ());
  ignore (Unix.alarm 0);
  Option.map (fun j -> member "result" j) reply

let report_items (r : Yojson.Safe.t option) : int option =
  match r with
  | Some (`Assoc _ as res) ->
    (match member "items" res with
     | `List l -> Some (List.length l)
     | _ -> None)
  | _ -> None

let test_pull_diagnostics_reports_an_error () =
  let n =
    report_items
      (pull_diagnostics ~uri:"file:///pull_bad.march"
         ~text:"mod M do\n  fn f() : Int do true end\nend\n")
  in
  match n with
  | None -> Alcotest.fail "textDocument/diagnostic returned no full report"
  | Some k ->
    Alcotest.(check bool) "the type error is in the pulled report" true (k > 0)

(* The companion that makes the first one mean something: a clean buffer must
   come back as an EMPTY full report — not an error, and not the other file's
   items. *)
let test_pull_diagnostics_clean_buffer_is_empty () =
  let n =
    report_items
      (pull_diagnostics ~uri:"file:///pull_ok.march"
         ~text:"mod M do\n  fn f() : Int do 1 end\nend\n")
  in
  match n with
  | None -> Alcotest.fail "textDocument/diagnostic returned no full report"
  | Some k -> Alcotest.(check int) "clean buffer reports no items" 0 k

let () =
  Alcotest.run "jsonrpc"
    [ "stdio",
      [ Alcotest.test_case "initialize/didOpen/hover" `Quick test_full_session;
        Alcotest.test_case "workspace/executeCommand is dispatched" `Quick
          test_execute_command_dispatches;
        Alcotest.test_case "exit notification terminates the server" `Quick
          test_exit_terminates;
        Alcotest.test_case "textDocument/diagnostic reports an error" `Quick
          test_pull_diagnostics_reports_an_error;
        Alcotest.test_case "textDocument/diagnostic is empty when clean" `Quick
          test_pull_diagnostics_clean_buffer_is_empty ] ]
