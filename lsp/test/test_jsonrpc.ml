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

(* ── The class guard ──────────────────────────────────────────────────────────
   Every capability the server ADVERTISES must answer without a protocol error.

   This is the test whose absence let ~20 features die quietly. Each individual
   feature's logic lives in `Analysis.*` and is unit-tested there, where it
   works; what was broken was only the wiring, and nothing exercised that. A
   per-feature test would have caught each one, but this catches the CLASS: add
   a capability to `config_*` without a reachable handler and this fails.

   It asserts "answered without error", deliberately not "answered usefully" —
   a null or empty result is legitimate for many of these on a small buffer, and
   asserting content here would make the guard brittle in exchange for coverage
   the per-feature tests already provide. The failure it exists to catch is
   `Failure("TODO: handle this request")`, which is a protocol ERROR. *)
let advertised_requests uri =
  let pos = `Assoc [ "line", `Int 1; "character", `Int 5 ] in
  let td = `Assoc [ "uri", `String uri ] in
  let range =
    `Assoc [ "start", `Assoc [ "line", `Int 0; "character", `Int 0 ];
             "end",   `Assoc [ "line", `Int 6; "character", `Int 0 ] ]
  in
  [ "textDocument/references",
    `Assoc [ "textDocument", td; "position", pos;
             "context", `Assoc [ "includeDeclaration", `Bool true ] ];
    "textDocument/formatting",
    `Assoc [ "textDocument", td;
             "options", `Assoc [ "tabSize", `Int 2; "insertSpaces", `Bool true ] ];
    "textDocument/documentHighlight", `Assoc [ "textDocument", td; "position", pos ];
    "textDocument/foldingRange", `Assoc [ "textDocument", td ];
    "textDocument/semanticTokens/full", `Assoc [ "textDocument", td ];
    "textDocument/signatureHelp", `Assoc [ "textDocument", td; "position", pos ];
    "textDocument/typeDefinition", `Assoc [ "textDocument", td; "position", pos ];
    "textDocument/implementation", `Assoc [ "textDocument", td; "position", pos ];
    "textDocument/selectionRange",
    `Assoc [ "textDocument", td; "positions", `List [ pos ] ];
    "textDocument/prepareCallHierarchy", `Assoc [ "textDocument", td; "position", pos ];
    "textDocument/linkedEditingRange", `Assoc [ "textDocument", td; "position", pos ];
    "textDocument/inlineValue",
    `Assoc [ "textDocument", td; "range", range;
             "context", `Assoc [ "frameId", `Int 0; "stoppedLocation", range ] ];
    "textDocument/codeLens", `Assoc [ "textDocument", td ];
    "workspace/symbol", `Assoc [ "query", `String "helper" ];
    (* Answered already; kept so a regression in the working set fails here too. *)
    "textDocument/hover", `Assoc [ "textDocument", td; "position", pos ];
    "textDocument/documentSymbol", `Assoc [ "textDocument", td ];
    "textDocument/diagnostic", `Assoc [ "textDocument", td ];
  ]

let run_capability_sweep () : (string * string) list =
  Sys.set_signal Sys.sigalrm
    (Sys.Signal_handle (fun _ -> failwith "march-lsp did not respond (timeout)"));
  ignore (Unix.alarm 90);
  let (ic, oc, ec) = Unix.open_process_args_full exe [| exe |] (Unix.environment ()) in
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "id", `Int 1; "method", `String "initialize";
    "params", `Assoc [ "processId", `Null; "rootUri", `Null;
                       "capabilities", `Assoc [] ] ]);
  ignore (read_until ic ~max:30 (is_id 1));
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "initialized";
                    "params", `Assoc [] ]);
  (* A URI at the FILESYSTEM ROOT makes `project_root` fall back to "/" and the
     workspace index then walks the whole disk — `references` and
     `workspace/symbol` never return. That is a real (pre-existing) sharp edge
     worth knowing about, but it is not what this test is measuring, so use a
     path under a temporary directory the way a real client would. *)
  let dir = Filename.get_temp_dir_name () in
  let uri = "file://" ^ Filename.concat dir "cap_sweep.march" in
  let text =
    "mod M do\n  fn helper(x : Int) : Int do\n    x + 1\n  end\n\
     \  fn main() : Int do\n    helper(2)\n  end\nend\n"
  in
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "method", `String "textDocument/didOpen";
    "params", `Assoc [ "textDocument", `Assoc [
      "uri", `String uri; "languageId", `String "march";
      "version", `Int 1; "text", `String text ] ] ]);
  ignore (read_until ic ~max:30 (is_method "textDocument/publishDiagnostics"));
  let failures = ref [] in
  List.iteri
    (fun i (meth, params) ->
      let id = 100 + i in
      send oc (`Assoc [ "jsonrpc", `String "2.0"; "id", `Int id;
                        "method", `String meth; "params", params ]);
      match read_until ic ~max:60 (is_id id) with
      | None -> failures := (meth, "no reply") :: !failures
      | Some j ->
        (match member "error" j with
         | `Null -> ()
         | e ->
           (* First line only: linol embeds a full Lwt backtrace in the message,
              and twenty of those buries the list this test exists to show. *)
           let m =
             match member "message" e with
             | `String s ->
               (match String.index_opt s '\n' with
                | Some i -> String.sub s 0 i
                | None -> s)
             | _ -> Yojson.Safe.to_string e
           in
           failures := (meth, m) :: !failures))
    (advertised_requests uri);
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "id", `Int 999;
                    "method", `String "shutdown"; "params", `Null ]);
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "exit";
                    "params", `Null ]);
  (try ignore (Unix.close_process_full (ic, oc, ec)) with _ -> ());
  ignore (Unix.alarm 0);
  List.rev !failures

let test_every_advertised_capability_answers () =
  let failures = run_capability_sweep () in
  if failures <> [] then
    Alcotest.failf
      "%d advertised capabilit(ies) do not answer:\n%s\n\n\
       An advertised capability with no reachable handler is a promise the \
       server cannot keep. Either wire it up, or stop advertising it in \
       `config_*` — leaving it advertised is the failure this test exists to \
       prevent."
      (List.length failures)
      (String.concat "\n"
         (List.map (fun (m, e) -> Printf.sprintf "  %-40s %s" m e) failures))

(* ── A document with no project root must not hang the server ────────────────
   `project_root` falls back to the open document's directory when no
   `forge.toml` is found above it. For a file at `/` that meant indexing the
   whole filesystem, and `textDocument/references` / `workspace/symbol` never
   returned — the client cannot distinguish that from a server still thinking.

   Two defences now: the walk is bounded (`Workspace.max_walk_files`), and a
   root that is plainly not a project (`/`, `$HOME`) is refused outright rather
   than walked. This pins the observable consequence of both.

   The alarm is the assertion: before the fix this test does not fail, it
   never finishes. *)
let run_no_project_root () =
  Sys.set_signal Sys.sigalrm
    (Sys.Signal_handle
       (fun _ -> failwith "a document with no project root hung the server"));
  ignore (Unix.alarm 30);
  let (ic, oc, ec) = Unix.open_process_args_full exe [| exe |] (Unix.environment ()) in
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "id", `Int 1; "method", `String "initialize";
    "params", `Assoc [ "processId", `Null; "rootUri", `Null;
                       "capabilities", `Assoc [] ] ]);
  ignore (read_until ic ~max:30 (is_id 1));
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "initialized";
                    "params", `Assoc [] ]);
  (* Deliberately at the filesystem root: no forge.toml can be found above it. *)
  let uri = "file:///no_project_root_probe.march" in
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "method", `String "textDocument/didOpen";
    "params", `Assoc [ "textDocument", `Assoc [
      "uri", `String uri; "languageId", `String "march"; "version", `Int 1;
      "text", `String "mod NP do\n  fn f(x : Int) : Int do\n    x\n  end\nend\n" ] ] ]);
  ignore (read_until ic ~max:30 (is_method "textDocument/publishDiagnostics"));
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "id", `Int 2; "method", `String "textDocument/references";
    "params", `Assoc [ "textDocument", `Assoc [ "uri", `String uri ];
                       "position", `Assoc [ "line", `Int 1; "character", `Int 5 ];
                       "context", `Assoc [ "includeDeclaration", `Bool true ] ] ]);
  let refs = read_until ic ~max:30 (is_id 2) in
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "id", `Int 3; "method", `String "workspace/symbol";
    "params", `Assoc [ "query", `String "f" ] ]);
  let syms = read_until ic ~max:30 (is_id 3) in
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "id", `Int 4;
                    "method", `String "shutdown"; "params", `Null ]);
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "exit";
                    "params", `Null ]);
  (try ignore (Unix.close_process_full (ic, oc, ec)) with _ -> ());
  ignore (Unix.alarm 0);
  (refs <> None, syms <> None)

let test_no_project_root_does_not_hang () =
  let (refs_ok, syms_ok) = run_no_project_root () in
  Alcotest.(check bool) "references answers without a project root" true refs_ok;
  Alcotest.(check bool) "workspace/symbol answers without a project root" true syms_ok

(* ── Per-feature CORRECTNESS ──────────────────────────────────────────────
   [test_every_advertised_capability_answers] above proves each capability is
   REACHABLE. It deliberately asserts nothing about content, so a handler that
   answered `[]` to everything would pass it.

   These tests close that gap. They matter more than they look: the many
   per-feature tests in `test_lsp.ml` exercise `Analysis.*`, and that layer was
   never the broken part — dispatch was. Every one of those tests stayed green
   through the entire period in which these features returned
   `TODO: handle this request` to editors, which is exactly why `dune runtest`
   never noticed.

   Each assertion pins a POSITION, not just a count. A response with the right
   shape and the wrong coordinates is the failure mode that reaches a user, and
   a non-emptiness check cannot see it. Each feature also gets a REJECT case —
   a query whose correct answer is "nothing" — because a handler returning
   every symbol in the file passes every positive test here.

   One server session serves them all: spawning per test would multiply a
   multi-second startup by the number of features for no extra coverage. *)

let fixture_dir = Filename.concat (Filename.get_temp_dir_name ()) "march_lsp_perfeature"
let fixture_path = Filename.concat fixture_dir "fixture.march"

(* Line/character coordinates are asserted literally below, so the layout is
   part of the test. 0-indexed:
     0  mod M do
     1    fn helper(x : Int) : Int do     `helper` at chars 5..11
     2      x + 1
     3    end
     4
     5    fn main() : Int do              `main` at chars 5..9
     6      helper(2)                     the call at chars 4..10
     7    end
     8  end                                                              *)
let fixture_text =
  "mod M do\n\
  \  fn helper(x : Int) : Int do\n\
  \    x + 1\n\
  \  end\n\
   \n\
  \  fn main() : Int do\n\
  \    helper(2)\n\
  \  end\n\
   end\n"

let fixture_uri () = "file://" ^ fixture_path

let decl_pos = `Assoc [ "line", `Int 1; "character", `Int 6 ]
let call_pos = `Assoc [ "line", `Int 6; "character", `Int 5 ]
(* Line 4 is blank — every position-based query here must answer "nothing". *)
let blank_pos = `Assoc [ "line", `Int 4; "character", `Int 0 ]

let per_feature_requests uri =
  let td = `Assoc [ "uri", `String uri ] in
  let ctx = `Assoc [ "includeDeclaration", `Bool true ] in
  [ "references", "textDocument/references",
    `Assoc [ "textDocument", td; "position", decl_pos; "context", ctx ];
    "references-blank", "textDocument/references",
    `Assoc [ "textDocument", td; "position", blank_pos; "context", ctx ];
    "highlight", "textDocument/documentHighlight",
    `Assoc [ "textDocument", td; "position", decl_pos ];
    "highlight-blank", "textDocument/documentHighlight",
    `Assoc [ "textDocument", td; "position", blank_pos ];
    "symbols", "textDocument/documentSymbol", `Assoc [ "textDocument", td ];
    "wsymbol", "workspace/symbol", `Assoc [ "query", `String "helper" ];
    "wsymbol-miss", "workspace/symbol", `Assoc [ "query", `String "zzzznomatch" ];
    "formatting", "textDocument/formatting",
    `Assoc [ "textDocument", td;
             "options", `Assoc [ "tabSize", `Int 2; "insertSpaces", `Bool true ] ];
    "sighelp", "textDocument/signatureHelp",
    `Assoc [ "textDocument", td;
             "position", `Assoc [ "line", `Int 6; "character", `Int 11 ] ];
    "callhier", "textDocument/prepareCallHierarchy",
    `Assoc [ "textDocument", td; "position", decl_pos ];
    "selrange", "textDocument/selectionRange",
    `Assoc [ "textDocument", td; "positions", `List [ call_pos ] ];
    "definition", "textDocument/definition",
    `Assoc [ "textDocument", td; "position", call_pos ];
    "folding", "textDocument/foldingRange", `Assoc [ "textDocument", td ];
    "rename", "textDocument/rename",
    `Assoc [ "textDocument", td; "position", decl_pos; "newName", `String "renamed" ] ]

let run_per_feature_session () : (string * Yojson.Safe.t) list =
  Sys.set_signal Sys.sigalrm
    (Sys.Signal_handle (fun _ -> failwith "march-lsp did not respond (timeout)"));
  ignore (Unix.alarm 120);
  (* The file must exist on disk: `workspace/symbol` answers from the workspace
     index, which reads the directory rather than the open-document set. *)
  (try Unix.mkdir fixture_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let ch = open_out fixture_path in
  output_string ch fixture_text;
  close_out ch;
  let (ic, oc, ec) = Unix.open_process_args_full exe [| exe |] (Unix.environment ()) in
  let uri = fixture_uri () in
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "id", `Int 1; "method", `String "initialize";
    "params", `Assoc [ "processId", `Null;
                       "rootUri", `String ("file://" ^ fixture_dir);
                       "capabilities", `Assoc [] ] ]);
  ignore (read_until ic ~max:30 (is_id 1));
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "initialized";
                    "params", `Assoc [] ]);
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "method", `String "textDocument/didOpen";
    "params", `Assoc [ "textDocument", `Assoc [
      "uri", `String uri; "languageId", `String "march";
      "version", `Int 1; "text", `String fixture_text ] ] ]);
  ignore (read_until ic ~max:30 (is_method "textDocument/publishDiagnostics"));
  let out =
    List.mapi
      (fun i (label, meth, params) ->
        let id = 500 + i in
        send oc (`Assoc [ "jsonrpc", `String "2.0"; "id", `Int id;
                          "method", `String meth; "params", params ]);
        match read_until ic ~max:60 (is_id id) with
        | None -> (label, `Null)
        | Some j ->
          (* An error here is the reachability failure the sweep guards; surface
             it as `Null so the per-feature assertion fails with its own name. *)
          (match member "error" j with
           | `Null -> (label, member "result" j)
           | _ -> (label, `Null)))
      (per_feature_requests uri)
  in
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "id", `Int 999;
                    "method", `String "shutdown"; "params", `Null ]);
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "exit";
                    "params", `Null ]);
  (try ignore (Unix.close_process_full (ic, oc, ec)) with _ -> ());
  ignore (Unix.alarm 0);
  out

let per_feature : (string * Yojson.Safe.t) list Lazy.t =
  lazy (run_per_feature_session ())

let answer label =
  try List.assoc label (Lazy.force per_feature) with Not_found -> `Null

let items j = match j with `List l -> l | _ -> []

(* (startLine, startChar, endLine, endChar) of a `range` member. *)
let range_of j =
  let r = member "range" j in
  let pt k f =
    match member f (member k r) with `Int n -> n | _ -> -1
  in
  (pt "start" "line", pt "start" "character", pt "end" "line", pt "end" "character")

let check_ranges label expected actual =
  Alcotest.(check (list (list int))) label
    (List.map (fun (a, b, c, d) -> [ a; b; c; d ]) expected)
    (List.map (fun (a, b, c, d) -> [ a; b; c; d ])
       (List.sort compare (List.map range_of actual)))

(* The two ranges every reference-shaped answer must name: the declaration of
   `helper`, and its one call site. *)
let helper_decl_range = (1, 5, 1, 11)
let helper_call_range = (6, 4, 6, 10)

let test_references_names_both_sites () =
  check_ranges "references: declaration and call, and nothing else"
    [ helper_decl_range; helper_call_range ] (items (answer "references"))

let test_references_on_a_blank_line_is_empty () =
  Alcotest.(check int) "references on a blank line finds nothing"
    0 (List.length (items (answer "references-blank")))

let test_document_highlight_names_both_sites () =
  check_ranges "documentHighlight: declaration and call"
    [ helper_decl_range; helper_call_range ] (items (answer "highlight"))

let test_document_highlight_on_a_blank_line_is_empty () =
  Alcotest.(check int) "documentHighlight on a blank line finds nothing"
    0 (List.length (items (answer "highlight-blank")))

let test_document_symbol_lists_exactly_the_two_functions () =
  let names =
    List.sort compare
      (List.filter_map
         (fun j -> match member "name" j with `String s -> Some s | _ -> None)
         (items (answer "symbols")))
  in
  (* Exactly two: a prelude leak — the bug this response had before — shows up
     here as dozens of stdlib names rather than as a wrong coordinate. *)
  Alcotest.(check (list string)) "document symbols" [ "helper"; "main" ] names

let test_workspace_symbol_finds_the_one_match () =
  let locs =
    List.map (fun j -> member "location" j) (items (answer "wsymbol"))
  in
  check_ranges "workspace/symbol locates `helper` at its declaration"
    [ helper_decl_range ] locs

let test_workspace_symbol_miss_is_empty () =
  (* Without this, a handler that ignores the query and returns every symbol in
     the workspace passes the test above. *)
  Alcotest.(check int) "a query matching nothing returns nothing"
    0 (List.length (items (answer "wsymbol-miss")))

let test_formatting_edit_equals_march_fmt () =
  match items (answer "formatting") with
  | [ edit ] ->
    let got = match member "newText" edit with `String s -> s | _ -> "" in
    (* Tie the LSP to the formatter the rest of the suite already covers, so
       the two can never drift and a formatter regression surfaces here too. *)
    let expected =
      let lexbuf = Lexing.from_string fixture_text in
      let m =
        March_parser.Parser.module_
          (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
      in
      March_format.Format.format_module ~src:fixture_text m
    in
    Alcotest.(check string) "formatting edit is exactly `march fmt`" expected got
  | l -> Alcotest.failf "expected exactly one formatting edit, got %d" (List.length l)

let test_signature_help_names_the_callee_and_parameter () =
  let r = answer "sighelp" in
  let sigs = items (member "signatures" r) in
  (match sigs with
   | s :: _ ->
     Alcotest.(check string) "signature label"
       "helper(Int)"
       (match member "label" s with `String x -> x | _ -> "")
   | [] -> Alcotest.fail "signatureHelp returned no signatures");
  Alcotest.(check int) "active parameter is the first"
    0 (match member "activeParameter" r with `Int n -> n | _ -> -1)

let test_call_hierarchy_prepares_the_enclosing_function () =
  match items (answer "callhier") with
  | [ item ] ->
    Alcotest.(check string) "prepared item names the function"
      "helper" (match member "name" item with `String s -> s | _ -> "");
    (* `range` spans the whole declaration; `selectionRange` pinpoints the name.
       Asserting both is what distinguishes a correct item from one that reuses
       a single span for each — which reads fine in a client until you use it. *)
    Alcotest.(check (list int)) "selectionRange is the name"
      [ 1; 5; 1; 11 ]
      (let (a, b, c, d) =
         let r = member "selectionRange" item in
         let pt k f = match member f (member k r) with `Int n -> n | _ -> -1 in
         (pt "start" "line", pt "start" "character",
          pt "end" "line", pt "end" "character")
       in
       [ a; b; c; d ]);
    let (sl, _, el, _) = range_of item in
    Alcotest.(check bool) "range covers the whole declaration" true
      (sl = 1 && el = 3)
  | l -> Alcotest.failf "expected one call-hierarchy item, got %d" (List.length l)

let test_selection_range_widens_from_the_call () =
  match items (answer "selrange") with
  | [ sr ] ->
    Alcotest.(check (list int)) "innermost range is the callee name"
      [ 6; 4; 6; 10 ]
      (let (a, b, c, d) = range_of sr in [ a; b; c; d ]);
    (* A selection range that does not widen is useless: the whole feature is
       the parent chain. *)
    let (pa, pb, pc, pd) = range_of (member "parent" sr) in
    Alcotest.(check bool) "parent strictly contains it" true
      (pa = 6 && pb = 4 && pc = 6 && pd > 10)
  | l -> Alcotest.failf "expected one selection range, got %d" (List.length l)

let test_definition_jumps_to_the_declaration () =
  check_ranges "definition of the call lands on the declaration"
    [ helper_decl_range ] (items (answer "definition"))

let test_folding_covers_both_function_bodies () =
  let spans =
    List.sort compare
      (List.map
         (fun j ->
           [ (match member "startLine" j with `Int n -> n | _ -> -1);
             (match member "endLine" j with `Int n -> n | _ -> -1) ])
         (items (answer "folding")))
  in
  Alcotest.(check (list (list int))) "one fold per function body"
    [ [ 1; 3 ]; [ 5; 7 ] ] spans

let test_rename_edits_every_site_and_only_those () =
  let edits =
    match member "changes" (answer "rename") with
    | `Assoc [ (_uri, es) ] -> items es
    | _ -> []
  in
  check_ranges "rename touches the declaration and the call"
    [ helper_decl_range; helper_call_range ] edits;
  List.iter
    (fun e ->
      Alcotest.(check string) "every edit writes the new name"
        "renamed" (match member "newText" e with `String s -> s | _ -> ""))
    edits

(* The leak that hit `semanticTokens` and `documentSymbol`: a per-document
   response describing the whole prelude-injected analysis rather than the open
   file. It shows up as a line number past the end of the document, so check
   that DIRECTLY, across every response at once, rather than per feature. *)
let test_no_response_describes_a_line_past_the_document () =
  let doc_lines = List.length (String.split_on_char '\n' fixture_text) in
  let rec max_line j =
    match j with
    | `Assoc l ->
      List.fold_left
        (fun acc (k, v) ->
          match (k, v) with
          | (("line" | "startLine" | "endLine"), `Int n) -> max acc n
          | _ -> max acc (max_line v))
        (-1) l
    | `List l -> List.fold_left (fun acc v -> max acc (max_line v)) (-1) l
    | _ -> -1
  in
  List.iter
    (fun (label, j) ->
      let m = max_line j in
      if m >= doc_lines then
        Alcotest.failf
          "%s describes line %d, past the end of a %d-line document — the \
           response is built from the whole analysis (prelude included) rather \
           than the open file"
          label m doc_lines)
    (Lazy.force per_feature)

(* ── The dispatch branches nothing exercised end-to-end ──────────────────────
   `dispatch_by_method` in `lsp/lib/server.ml` is a 22-method `if/else if`
   chain. The sessions above reach 16 of those methods; the ones below are the
   remainder, and they were the only branches in the file that no end-to-end
   test had ever executed:

     textDocument/semanticTokens/full        (reached by the reachability sweep,
                                              which asserts no content)
     textDocument/semanticTokens/full/delta
     textDocument/prepareRename
     callHierarchy/incomingCalls
     callHierarchy/outgoingCalls
     workspace/diagnostic
     completionItem/resolve
     textDocument/onTypeFormatting

   `semanticTokens/full/delta` is the reason this matters more than the count
   suggests: it is the ONLY branch in the chain with cross-request state
   (`sem_tokens_cache`, keyed by the `resultId` a previous `full` handed out).
   A refactor that moves the chain away from that cache — or that reorders the
   two semanticTokens arms, `full` being a strict prefix of `full/delta` in an
   `if` chain — breaks it silently, and no other test in this repo notices.

   As above, each branch gets a POSITIVE case and, where the branch has a
   meaningful "nothing" answer, a REJECT case, so that neither a handler that
   always answers empty nor one that answers everything can pass. *)

let cov_dir =
  Filename.concat (Filename.get_temp_dir_name ()) "march_lsp_dispatch_cov"

(* 0-indexed layout, asserted literally below:
     0  mod C do
     1    fn helper(x : Int) : Int do      `helper` at chars 5..11
     2      x + 1
     3    end
     4
     5    fn main() : Int do
     6      helper(2)                      the call at chars 4..10
     7    end
     8  end                                                             *)
let cov_text =
  "mod C do\n\
  \  fn helper(x : Int) : Int do\n\
  \    x + 1\n\
  \  end\n\
   \n\
  \  fn main() : Int do\n\
  \    helper(2)\n\
  \  end\n\
   end\n"

(* A second file, deliberately ill-typed, so `workspace/diagnostic` has
   something to report — and the clean file above gives that same response a
   zero to report, which is what stops "attributes everything to everyone"
   from passing. *)
let cov_bad_text = "mod CBad do\n  fn f() : Int do true end\nend\n"

(* Two ~H sigils in two files: one that must auto-close, one void element that
   must not. *)
let cov_html_text =
  "mod CHtml do\n\
  \  fn page() : IOList do\n\
  \    ~H\"<div>\"\n\
  \  end\n\
   end\n"

let cov_void_text =
  "mod CVoid do\n\
  \  fn page() : IOList do\n\
  \    ~H\"<br>\"\n\
  \  end\n\
   end\n"

let cov_path name = Filename.concat cov_dir name
let cov_uri name = "file://" ^ cov_path name

let write_file path text =
  let ch = open_out path in
  output_string ch text;
  close_out ch

let cov_decl_pos = `Assoc [ "line", `Int 1; "character", `Int 6 ]
let cov_blank_pos = `Assoc [ "line", `Int 4; "character", `Int 0 ]

(* One session for all of them: each server spawn costs seconds, and the delta
   branch needs two requests in the SAME process anyway. *)
let run_dispatch_coverage_session () : (string * Yojson.Safe.t) list =
  Sys.set_signal Sys.sigalrm
    (Sys.Signal_handle (fun _ -> failwith "march-lsp did not respond (timeout)"));
  ignore (Unix.alarm 120);
  (try Unix.mkdir cov_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  write_file (cov_path "fixture.march") cov_text;
  write_file (cov_path "broken.march") cov_bad_text;
  write_file (cov_path "html.march") cov_html_text;
  write_file (cov_path "void.march") cov_void_text;
  let (ic, oc, ec) = Unix.open_process_args_full exe [| exe |] (Unix.environment ()) in
  let uri = cov_uri "fixture.march" in
  let html_uri = cov_uri "html.march" in
  let void_uri = cov_uri "void.march" in
  send oc (`Assoc [
    "jsonrpc", `String "2.0"; "id", `Int 1; "method", `String "initialize";
    "params", `Assoc [ "processId", `Null;
                       "rootUri", `String ("file://" ^ cov_dir);
                       "capabilities", `Assoc [] ] ]);
  ignore (read_until ic ~max:30 (is_id 1));
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "initialized";
                    "params", `Assoc [] ]);
  let open_doc u text =
    send oc (`Assoc [
      "jsonrpc", `String "2.0"; "method", `String "textDocument/didOpen";
      "params", `Assoc [ "textDocument", `Assoc [
        "uri", `String u; "languageId", `String "march";
        "version", `Int 1; "text", `String text ] ] ]);
    ignore (read_until ic ~max:30 (is_method "textDocument/publishDiagnostics"))
  in
  open_doc uri cov_text;
  open_doc html_uri cov_html_text;
  open_doc void_uri cov_void_text;
  let next_id = ref 700 in
  let ask meth params =
    let id = !next_id in
    incr next_id;
    send oc (`Assoc [ "jsonrpc", `String "2.0"; "id", `Int id;
                      "method", `String meth; "params", params ]);
    match read_until ic ~max:60 (is_id id) with
    | None -> `Null
    | Some j ->
      (* A protocol error is exactly the failure this file exists to catch;
         surface it as `Null so the per-branch assertion names the branch. *)
      (match member "error" j with `Null -> member "result" j | _ -> `Null)
  in
  let td u = `Assoc [ "uri", `String u ] in
  let out = ref [] in
  let record label j = out := (label, j) :: !out in

  (* semanticTokens/full first, then the delta that depends on its resultId. *)
  let full = ask "textDocument/semanticTokens/full" (`Assoc [ "textDocument", td uri ]) in
  record "semtok-full" full;
  let prev_id = match member "resultId" full with `String s -> s | _ -> "" in
  record "semtok-delta"
    (ask "textDocument/semanticTokens/full/delta"
       (`Assoc [ "textDocument", td uri; "previousResultId", `String prev_id ]));
  (* A baseline the server never issued must fall back to a FULL response.
     Sent after the real delta, by which point the cache holds a different id. *)
  record "semtok-delta-stale"
    (ask "textDocument/semanticTokens/full/delta"
       (`Assoc [ "textDocument", td uri;
                 "previousResultId", `String "no-such-result-id" ]));

  record "prepare-rename"
    (ask "textDocument/prepareRename"
       (`Assoc [ "textDocument", td uri; "position", cov_decl_pos ]));
  record "prepare-rename-blank"
    (ask "textDocument/prepareRename"
       (`Assoc [ "textDocument", td uri; "position", cov_blank_pos ]));

  (* The client echoes back the item prepareCallHierarchy produced. *)
  let item name =
    `Assoc [ "name", `String name; "kind", `Int 12; "uri", `String uri;
             "range", `Assoc [ "start", `Assoc [ "line", `Int 1; "character", `Int 2 ];
                               "end",   `Assoc [ "line", `Int 3; "character", `Int 5 ] ];
             "selectionRange",
             `Assoc [ "start", `Assoc [ "line", `Int 1; "character", `Int 5 ];
                      "end",   `Assoc [ "line", `Int 1; "character", `Int 11 ] ] ]
  in
  record "incoming"
    (ask "callHierarchy/incomingCalls" (`Assoc [ "item", item "helper" ]));
  record "incoming-leaf"
    (ask "callHierarchy/incomingCalls" (`Assoc [ "item", item "main" ]));
  record "outgoing"
    (ask "callHierarchy/outgoingCalls" (`Assoc [ "item", item "main" ]));
  record "outgoing-leaf"
    (ask "callHierarchy/outgoingCalls" (`Assoc [ "item", item "helper" ]));

  (* `previousResultIds` is not optional in the protocol type, and linol DECODES
     this request before routing it, so omitting it fails the decode rather than
     reaching the handler. Same reason `options` appears on the two
     onTypeFormatting requests below. *)
  record "workspace-diagnostic"
    (ask "workspace/diagnostic" (`Assoc [ "previousResultIds", `List [] ]));

  record "resolve"
    (ask "completionItem/resolve"
       (* [version] must match the document's current version (1, from the
          single [didOpen] above — [on_notif_doc_did_open] bumps from 0) or
          the staleness guard in [completionItem/resolve] refuses to answer;
          see [server_state.ml]'s [is_current] and its call site in
          [server_dispatch.ml]. *)
       (`Assoc [ "label", `String "map"; "kind", `Int 3;
                 "data", `Assoc [ "uri", `String uri; "version", `Int 1;
                                  "autoImport",
                                  `Assoc [ "module", `String "List";
                                           "name", `String "map" ] ] ]));
  record "resolve-plain"
    (ask "completionItem/resolve" (`Assoc [ "label", `String "map"; "kind", `Int 3 ]));

  (* Cursor just past the '>' of `<div>` on line 2 (`    ~H"<div>"`). *)
  record "ontype"
    (ask "textDocument/onTypeFormatting"
       (`Assoc [ "textDocument", td html_uri;
                 "position", `Assoc [ "line", `Int 2; "character", `Int 12 ];
                 "ch", `String ">";
                 "options", `Assoc [ "tabSize", `Int 2; "insertSpaces", `Bool true ] ]));
  (* `<br>` is void: past its '>' (character 11) there is nothing to close. *)
  record "ontype-void"
    (ask "textDocument/onTypeFormatting"
       (`Assoc [ "textDocument", td void_uri;
                 "position", `Assoc [ "line", `Int 2; "character", `Int 11 ];
                 "ch", `String ">";
                 "options", `Assoc [ "tabSize", `Int 2; "insertSpaces", `Bool true ] ]));

  send oc (`Assoc [ "jsonrpc", `String "2.0"; "id", `Int 998;
                    "method", `String "shutdown"; "params", `Null ]);
  send oc (`Assoc [ "jsonrpc", `String "2.0"; "method", `String "exit";
                    "params", `Null ]);
  (try ignore (Unix.close_process_full (ic, oc, ec)) with _ -> ());
  ignore (Unix.alarm 0);
  List.rev !out

let dispatch_cov : (string * Yojson.Safe.t) list Lazy.t =
  lazy (run_dispatch_coverage_session ())

let cov label =
  try List.assoc label (Lazy.force dispatch_cov) with Not_found -> `Null

let int_list j = List.map (function `Int n -> n | _ -> -1) (items j)

let test_semantic_tokens_full_returns_a_token_stream () =
  let r = cov "semtok-full" in
  (match member "resultId" r with
   | `String s -> Alcotest.(check bool) "full response carries a resultId" true (s <> "")
   | _ -> Alcotest.fail "semanticTokens/full returned no resultId");
  let data = int_list (member "data" r) in
  Alcotest.(check bool) "the token stream is non-empty" true (data <> []);
  (* The LSP encoding is five integers per token; a stream that is not a whole
     number of 5-tuples is malformed whatever it contains. *)
  Alcotest.(check int) "the stream is a whole number of 5-tuples"
    0 (List.length data mod 5);
  (* deltaLine values are relative, so their sum is the last token's line. Past
     the end of the document means the response describes the prelude-injected
     analysis rather than the open file — the leak this suite already pins for
     the other per-document responses. *)
  let rec last_line acc = function
    | dl :: _ :: _ :: _ :: _ :: rest -> last_line (acc + dl) rest
    | _ -> acc
  in
  Alcotest.(check bool) "no token starts past the last line of the document" true
    (last_line 0 data < List.length (String.split_on_char '\n' cov_text))

let test_semantic_tokens_delta_against_its_own_baseline_is_an_empty_edit () =
  let r = cov "semtok-delta" in
  (* The assertion this whole case exists for: given the resultId that the
     `full` request handed out, the server must answer in DELTA form. Losing
     the shared `sem_tokens_cache` degrades this to a full response, which every
     client still renders correctly — so nothing but this notices. *)
  (match items (member "edits" r) with
   | [ e ] ->
     Alcotest.(check int) "an unmodified document deletes nothing"
       0 (match member "deleteCount" e with `Int n -> n | _ -> -1);
     Alcotest.(check (list int)) "and inserts nothing" [] (int_list (member "data" e))
   | l -> Alcotest.failf "expected exactly one delta edit, got %d" (List.length l));
  Alcotest.(check bool) "a delta response carries no full `data` array" true
    (member "data" r = `Null)

let test_semantic_tokens_delta_with_an_unknown_baseline_falls_back_to_full () =
  let r = cov "semtok-delta-stale" in
  Alcotest.(check bool) "an unknown previousResultId returns a full stream" true
    (member "edits" r = `Null && int_list (member "data" r) <> [])

let test_prepare_rename_selects_the_identifier () =
  let pt k f =
    match member f (member k (cov "prepare-rename")) with `Int n -> n | _ -> -1
  in
  Alcotest.(check (list int)) "prepareRename selects exactly `helper`"
    [ 1; 5; 1; 11 ]
    [ pt "start" "line"; pt "start" "character";
      pt "end" "line"; pt "end" "character" ]

let test_prepare_rename_on_a_blank_line_rejects () =
  (* `null` is how prepareRename says "this cannot be renamed"; a handler that
     always returns a range makes every position in the file look renameable. *)
  Alcotest.(check bool) "prepareRename on a blank line rejects the rename" true
    (cov "prepare-rename-blank" = `Null)

let call_names key side =
  List.sort compare
    (List.filter_map
       (fun j -> match member "name" (member side j) with `String s -> Some s | _ -> None)
       (items (cov key)))

let test_incoming_calls_names_the_caller () =
  Alcotest.(check (list string)) "helper is called from main"
    [ "main" ] (call_names "incoming" "from");
  match items (cov "incoming") with
  | [ c ] ->
    (* `fromRanges` holds bare Ranges, not objects with a `range` member, so
       this cannot reuse [range_of]. *)
    let pt r k f = match member f (member k r) with `Int n -> n | _ -> -1 in
    (* The whole call expression `helper(2)`, not just the callee name. *)
    Alcotest.(check (list (list int))) "and the fromRanges point at the call site"
      [ [ 6; 4; 6; 13 ] ]
      (List.map
         (fun r -> [ pt r "start" "line"; pt r "start" "character";
                     pt r "end" "line"; pt r "end" "character" ])
         (items (member "fromRanges" c)))
  | l -> Alcotest.failf "expected one incoming call, got %d" (List.length l)

let test_incoming_calls_for_an_uncalled_function_is_empty () =
  Alcotest.(check int) "main is called by nobody"
    0 (List.length (items (cov "incoming-leaf")))

let test_outgoing_calls_names_the_callee () =
  Alcotest.(check (list string)) "main calls helper"
    [ "helper" ] (call_names "outgoing" "to")

let test_outgoing_calls_for_a_leaf_is_empty () =
  Alcotest.(check int) "helper calls nothing"
    0 (List.length (items (cov "outgoing-leaf")))

let test_workspace_diagnostic_reports_the_broken_file_and_only_it () =
  let reports =
    List.filter_map
      (fun j ->
        match member "uri" j with
        | `String u -> Some (Filename.basename u, List.length (items (member "items" j)))
        | _ -> None)
      (items (member "items" (cov "workspace-diagnostic")))
  in
  Alcotest.(check bool) "the project report covers every file under the root" true
    (List.mem_assoc "broken.march" reports && List.mem_assoc "fixture.march" reports);
  Alcotest.(check bool) "the ill-typed file reports at least one diagnostic" true
    (match List.assoc_opt "broken.march" reports with Some n -> n > 0 | None -> false);
  (* Without this, a handler that attributes every diagnostic to every file — or
     that reports the prelude's — passes the assertion above. *)
  Alcotest.(check int) "the clean file reports none"
    0 (match List.assoc_opt "fixture.march" reports with Some n -> n | None -> -1)

let test_completion_item_resolve_attaches_the_auto_import_edit () =
  let r = cov "resolve" in
  Alcotest.(check string) "the resolved item is still the item that was sent"
    "map" (match member "label" r with `String s -> s | _ -> "");
  match items (member "additionalTextEdits" r) with
  | [ e ] ->
    Alcotest.(check string) "resolve inserts the missing import"
      "  use List.{map}\n" (match member "newText" e with `String s -> s | _ -> "")
  | l ->
    Alcotest.failf "expected exactly one additionalTextEdit, got %d" (List.length l)

let test_completion_item_resolve_without_data_is_an_echo () =
  (* The pass-through arm: an item carrying no `autoImport` payload must come
     back unchanged rather than gaining an edit for an unrelated import. *)
  let r = cov "resolve-plain" in
  Alcotest.(check string) "the item round-trips"
    "map" (match member "label" r with `String s -> s | _ -> "");
  Alcotest.(check bool) "and gains no edits" true
    (member "additionalTextEdits" r = `Null)

let test_on_type_formatting_closes_the_open_tag () =
  match items (cov "ontype") with
  | [ e ] ->
    Alcotest.(check string) "typing `>` after `<div>` inserts the closing tag"
      "</div>" (match member "newText" e with `String s -> s | _ -> "");
    Alcotest.(check (list int)) "the edit is a zero-width insert at the cursor"
      [ 2; 12; 2; 12 ]
      (let (a, b, c, d) = range_of e in [ a; b; c; d ])
  | l -> Alcotest.failf "expected exactly one onTypeFormatting edit, got %d" (List.length l)

let test_on_type_formatting_does_not_close_a_void_element () =
  Alcotest.(check int) "`<br>` is void: there is nothing to close"
    0 (List.length (items (cov "ontype-void")))

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
          test_pull_diagnostics_clean_buffer_is_empty;
        Alcotest.test_case "every advertised capability answers" `Quick
          test_every_advertised_capability_answers;
        Alcotest.test_case "a document with no project root does not hang" `Quick
          test_no_project_root_does_not_hang ];
      "dispatch branches",
      [ Alcotest.test_case "semanticTokens/full returns a token stream" `Quick
          test_semantic_tokens_full_returns_a_token_stream;
        Alcotest.test_case "semanticTokens/full/delta against its own baseline" `Quick
          test_semantic_tokens_delta_against_its_own_baseline_is_an_empty_edit;
        Alcotest.test_case "semanticTokens/full/delta falls back on an unknown baseline"
          `Quick test_semantic_tokens_delta_with_an_unknown_baseline_falls_back_to_full;
        Alcotest.test_case "prepareRename selects the identifier" `Quick
          test_prepare_rename_selects_the_identifier;
        Alcotest.test_case "prepareRename on a blank line rejects" `Quick
          test_prepare_rename_on_a_blank_line_rejects;
        Alcotest.test_case "callHierarchy/incomingCalls names the caller" `Quick
          test_incoming_calls_names_the_caller;
        Alcotest.test_case "callHierarchy/incomingCalls of an uncalled fn is empty"
          `Quick test_incoming_calls_for_an_uncalled_function_is_empty;
        Alcotest.test_case "callHierarchy/outgoingCalls names the callee" `Quick
          test_outgoing_calls_names_the_callee;
        Alcotest.test_case "callHierarchy/outgoingCalls of a leaf is empty" `Quick
          test_outgoing_calls_for_a_leaf_is_empty;
        Alcotest.test_case "workspace/diagnostic reports the broken file only" `Quick
          test_workspace_diagnostic_reports_the_broken_file_and_only_it;
        Alcotest.test_case "completionItem/resolve attaches the auto-import edit" `Quick
          test_completion_item_resolve_attaches_the_auto_import_edit;
        Alcotest.test_case "completionItem/resolve without data is an echo" `Quick
          test_completion_item_resolve_without_data_is_an_echo;
        Alcotest.test_case "onTypeFormatting closes the open tag" `Quick
          test_on_type_formatting_closes_the_open_tag;
        Alcotest.test_case "onTypeFormatting does not close a void element" `Quick
          test_on_type_formatting_does_not_close_a_void_element ];
      "per-feature correctness",
      [ Alcotest.test_case "references names both sites" `Quick
          test_references_names_both_sites;
        Alcotest.test_case "references on a blank line is empty" `Quick
          test_references_on_a_blank_line_is_empty;
        Alcotest.test_case "documentHighlight names both sites" `Quick
          test_document_highlight_names_both_sites;
        Alcotest.test_case "documentHighlight on a blank line is empty" `Quick
          test_document_highlight_on_a_blank_line_is_empty;
        Alcotest.test_case "documentSymbol lists exactly the two functions" `Quick
          test_document_symbol_lists_exactly_the_two_functions;
        Alcotest.test_case "workspace/symbol finds the one match" `Quick
          test_workspace_symbol_finds_the_one_match;
        Alcotest.test_case "workspace/symbol miss is empty" `Quick
          test_workspace_symbol_miss_is_empty;
        Alcotest.test_case "formatting edit equals march fmt" `Quick
          test_formatting_edit_equals_march_fmt;
        Alcotest.test_case "signatureHelp names callee and parameter" `Quick
          test_signature_help_names_the_callee_and_parameter;
        Alcotest.test_case "prepareCallHierarchy prepares the function" `Quick
          test_call_hierarchy_prepares_the_enclosing_function;
        Alcotest.test_case "selectionRange widens from the call" `Quick
          test_selection_range_widens_from_the_call;
        Alcotest.test_case "definition jumps to the declaration" `Quick
          test_definition_jumps_to_the_declaration;
        Alcotest.test_case "foldingRange covers both function bodies" `Quick
          test_folding_covers_both_function_bodies;
        Alcotest.test_case "rename edits every site and only those" `Quick
          test_rename_edits_every_site_and_only_those;
        Alcotest.test_case "no response describes a line past the document" `Quick
          test_no_response_describes_a_line_past_the_document ] ]
