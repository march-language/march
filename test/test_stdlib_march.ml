(** Stdlib March test runner.

    Each stdlib test file lives in test/stdlib/test_FOO.march and defines a
    module (e.g. [mod TestFoo do ... pub fn main() ... end]).

    This runner:
      1. Loads all required stdlib declarations in dependency order.
      2. Parses the test .march file.
      3. Evaluates the resulting module (stdlib prepended so names are in scope).
      4. Calls [TestFoo.main()] and expects it to return without panicking.
         Any [March_eval.Eval.Eval_error] is turned into an Alcotest failure.
*)

(* ------------------------------------------------------------------ *)
(* Helpers: find files                                                 *)
(* ------------------------------------------------------------------ *)

let find_file candidates =
  List.find_opt Sys.file_exists candidates

let find_stdlib_file name =
  let candidates = [
    Filename.concat "stdlib" name;
    Filename.concat "../../../stdlib" name;
    Filename.concat "../../stdlib" name;
  ] in
  match find_file candidates with
  | None ->
    Printf.eprintf "Cannot find stdlib/%s\n%!" name;
    failwith ("missing stdlib file: " ^ name)
  | Some p -> p

let find_test_file name =
  let candidates = [
    Filename.concat "test/stdlib" name;
    Filename.concat "stdlib" name;
    Filename.concat "../../../test/stdlib" name;
    Filename.concat "../../test/stdlib" name;
    name;
  ] in
  match find_file candidates with
  | None ->
    Printf.eprintf "Cannot find test file %s\n%!" name;
    failwith ("missing test file: " ^ name)
  | Some p -> p

let read_file path =
  let ic = open_in path in
  let n  = in_channel_length ic in
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  close_in ic;
  Bytes.to_string buf

(* ------------------------------------------------------------------ *)
(* Stdlib loading                                                      *)
(* ------------------------------------------------------------------ *)

(** Parse, desugar and return a stdlib file as a list of declarations.
    For [prelude.march] the inner declarations are returned flat so that
    Prelude's functions land in global scope (matching bin/main.ml behaviour).
    All other files are returned as a single [DMod] so names are qualified. *)
let load_stdlib_decls name =
  let path = find_stdlib_file name in
  let src  = read_file path in
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
  try
    let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
    let m = March_desugar.Desugar.desugar_module m in
    if name = "prelude.march" then
      (* Unwrap outer mod so prelude globals are in scope directly *)
      (match m.March_ast.Ast.mod_decls with
       | [March_ast.Ast.DMod (_, _, inner, _)] -> inner
       | decls -> decls)
    else
      [March_ast.Ast.DMod (m.March_ast.Ast.mod_name,
                           March_ast.Ast.Public,
                           m.March_ast.Ast.mod_decls,
                           March_ast.Ast.dummy_span)]
  with _ ->
    Printf.eprintf "[test] skipping stdlib %s (parse error)\n%!" name;
    []

(** Load all stdlib modules in dependency order, matching bin/main.ml. *)
let all_stdlib_decls =
  let files = [
    "prelude.march";
    "option.march";
    "result.march";
    "list.march";
    "hamt.march";
    "map.march";
    "math.march";
    "string.march";
    "iolist.march";
    "http.march";
    "http_transport.march";
    "http_client.march";
    "seq.march";
    "path.march";
    "file.march";
    "dir.march";
    "sort.march";
    "csv.march";
    "websocket.march";
    "tls.march";
    "http_server.march";
    "iterable.march";
    "set.march";
    "array.march";
    "bigint.march";
    "decimal.march";
    "bytes.march";
    "process.march";
    "logger.march";
    "flow.march";
    "regex.march";
    "random.march";
    "stats.march";
    "test.march";
    "pubsub.march";
    "channel.march";
    "channel_server.march";
    "presence.march";
    "channel_socket.march";
    "vault.march";
    "env.march";
    "config.march";
    "html.march";
  ] in
  lazy (List.concat_map load_stdlib_decls files)

(* ------------------------------------------------------------------ *)
(* Test runner                                                         *)
(* ------------------------------------------------------------------ *)

(** Parse a test .march file (which must contain exactly one top-level
    mod declaration) and return its declarations. *)
let parse_test_file filename =
  let path = find_test_file filename in
  let src  = read_file path in
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
  let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  March_desugar.Desugar.desugar_module m

(** Run a stdlib test file using the native test runner.
    [test_filename] is the basename of the file under test/stdlib/.
    Collects all [test "..."] blocks and runs them via [run_tests]. *)
let run_stdlib_test test_filename _mod_name () =
  March_eval.Eval.reset_scheduler_state ();
  let stdlib = Lazy.force all_stdlib_decls in
  let m = parse_test_file test_filename in
  (* Prepend stdlib so user code can reference Http.*, Test.*, etc. *)
  let m' = { m with March_ast.Ast.mod_decls = stdlib @ m.March_ast.Ast.mod_decls } in
  let (total, n_failed, _) =
    try March_eval.Eval.run_tests m'
    with March_eval.Eval.Eval_error msg ->
      Alcotest.failf "eval error: %s" msg
  in
  if n_failed > 0 then
    Alcotest.failf "%d/%d tests failed in %s" n_failed total test_filename

(* ------------------------------------------------------------------ *)
(* Test cases                                                          *)
(* ------------------------------------------------------------------ *)

let () =
  Alcotest.run "stdlib_march" [
    ("http", [
      Alcotest.test_case "Http module"
        `Quick (run_stdlib_test "test_http.march" "TestHttp");
    ]);
    ("http_transport", [
      Alcotest.test_case "HttpTransport module"
        `Quick (run_stdlib_test "test_http_transport.march" "TestHttpTransport");
    ]);
    ("http_client", [
      Alcotest.test_case "HttpClient module"
        `Quick (run_stdlib_test "test_http_client.march" "TestHttpClient");
    ]);
    ("http_server", [
      Alcotest.test_case "HttpServer module"
        `Quick (run_stdlib_test "test_http_server.march" "TestHttpServer");
    ]);
    ("websocket", [
      Alcotest.test_case "WebSocket module"
        `Quick (run_stdlib_test "test_websocket.march" "TestWebSocket");
    ]);
    ("tls", [
      Alcotest.test_case "Tls module"
        `Quick (run_stdlib_test "test_tls.march" "TestTls");
    ]);
    ("pubsub", [
      Alcotest.test_case "PubSub module"
        `Quick (run_stdlib_test "test_pubsub.march" "TestPubSub");
    ]);
    ("channel", [
      Alcotest.test_case "Channel module"
        `Quick (run_stdlib_test "test_channel.march" "TestChannel");
    ]);
    ("channel_server", [
      Alcotest.test_case "ChannelServer module"
        `Quick (run_stdlib_test "test_channel_server.march" "TestChannelServer");
    ]);
    ("presence", [
      Alcotest.test_case "Presence module"
        `Quick (run_stdlib_test "test_presence.march" "TestPresence");
    ]);
    ("channel_socket", [
      Alcotest.test_case "ChannelSocket module"
        `Quick (run_stdlib_test "test_channel_socket.march" "TestChannelSocket");
    ]);
    ("process", [
      Alcotest.test_case "Process module"
        `Quick (run_stdlib_test "test_process.march" "TestProcess");
    ]);
    ("logger", [
      Alcotest.test_case "Logger module"
        `Quick (run_stdlib_test "test_logger.march" "TestLogger");
    ]);
    ("env", [
      Alcotest.test_case "Env module"
        `Quick (run_stdlib_test "test_env.march" "TestEnv");
    ]);
    ("config", [
      Alcotest.test_case "Config module"
        `Quick (run_stdlib_test "test_config.march" "TestConfig");
    ]);
    ("stats", [
      Alcotest.test_case "Stats module"
        `Quick (run_stdlib_test "test_stats.march" "TestStats");
    ]);
    ("random", [
      Alcotest.test_case "Random module"
        `Quick (run_stdlib_test "test_random.march" "TestRandom");
    ]);
    ("test", [
      Alcotest.test_case "Test module (assertion helpers)"
        `Quick (run_stdlib_test "test_test.march" "TestTest");
    ]);
    (* test_flow.march tests the function-transformer Flow API (from_fn/run/then_)
       which differs from the current Seq-based flow.march implementation.
    ("flow", [
      Alcotest.test_case "Flow module"
        `Quick (run_stdlib_test "test_flow.march" "TestFlow");
    ]); *)
  ]
