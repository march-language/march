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

let () =
  Alcotest.run "jsonrpc"
    [ "stdio",
      [ Alcotest.test_case "initialize/didOpen/hover" `Quick test_full_session ] ]
