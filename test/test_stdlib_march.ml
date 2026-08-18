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
    "io.march";
    (* Loaded before iolist/msgpack so their same-named constructors (Str,
       Array, ...) keep winning bare lookups exactly as they did before
       json.march joined this list. *)
    "parser.march";
    "json.march";
    "json_stream.march";
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
    "hash_map.march";
    "array.march";
    "bigint.march";
    "decimal.march";
    "bytes.march";
    "msgpack.march";
    "toml.march";
    "xml.march";
    "yaml.march";
    "socket.march";
    "dns.march";
    "process.march";
    "logger.march";
    "flow.march";
    "regex.march";
    "queue.march";
    "aho_corasick.march";
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
    "sigil.march";
    "crypto.march";
    "deque.march";
    "ring_buf.march";
    "vector_clock.march";
    "merkle.march";
    "crdt.march";
    "consistent_hash.march";
    "net_frame.march";
    "node_identity.march";
    "cluster_auth.march";
    "handshake.march";
    "net_kernel.march";
    "peer_registry.march";
    "cluster_conn.march";
    "membership.march";
    "swim.march";
    "swim_driver.march";
    "global_registry.march";
    "global_pid.march";
    "remote_call.march";
    "node_rpc.march";
    "node_call.march";
    "cluster_load.march";
    "work_dispatch.march";
    "dist_link.march";
    "dist_supervisor.march";
    "system.march";
    "cluster.march";
    "rrb_vec.march";
    "parallel.march";
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
(* Registry-drift guard                                                *)
(*                                                                      *)
(* Nothing used to check that every test/stdlib/test_*.march file on   *)
(* disk is actually reachable from the Alcotest.run list below -- that *)
(* is exactly how test_json.march once fell out of the build (wired    *)
(* into no runner, unnoticed). See                                     *)
(* specs/progress/2026-07-31-open-follow-up-test-file-registry-drift.md*)
(* ------------------------------------------------------------------ *)

let find_own_source () =
  let candidates = [
    "test/test_stdlib_march.ml";
    "../../../test/test_stdlib_march.ml";
    "../../test/test_stdlib_march.ml";
    "test_stdlib_march.ml";
  ] in
  match find_file candidates with
  | Some p -> p
  | None ->
    failwith "cannot locate test/test_stdlib_march.ml (needed for the \
              registry-drift self-check)"

let find_test_stdlib_dir () =
  let candidates = [
    "test/stdlib";
    "../../../test/stdlib";
    "../../test/stdlib";
  ] in
  match find_file candidates with
  | Some p -> p
  | None ->
    failwith "cannot locate test/stdlib (needed for the registry-drift \
              self-check)"

(** Strip OCaml [(* ... *)] comments (nesting-aware) before scanning this
    file's own source for registrations, so a commented-out entry (e.g.
    test_flow.march below, whose registration is deliberately disabled a
    few dozen lines up) isn't mistaken for a live one. *)
let strip_ocaml_comments src =
  let n = String.length src in
  let buf = Buffer.create n in
  let rec skip_comment i depth =
    if i >= n then i
    else if i + 1 < n && src.[i] = '(' && src.[i + 1] = '*' then
      skip_comment (i + 2) (depth + 1)
    else if i + 1 < n && src.[i] = '*' && src.[i + 1] = ')' then
      (if depth = 1 then i + 2 else skip_comment (i + 2) (depth - 1))
    else skip_comment (i + 1) depth
  in
  let rec go i =
    if i >= n then ()
    else if i + 1 < n && src.[i] = '(' && src.[i + 1] = '*' then
      go (skip_comment (i + 2) 1)
    else begin
      Buffer.add_char buf src.[i];
      go (i + 1)
    end
  in
  go 0;
  Buffer.contents buf

(** Every [run_stdlib_test "test_FOO.march"] filename literal that appears
    (outside comments) in this very file's source -- i.e. the actual
    registry the [Alcotest.run] list below is built from. Parsed rather
    than hand-duplicated so this check can never itself drift from the
    real registration list. *)
let registered_stdlib_test_files () =
  let src = strip_ocaml_comments (read_file (find_own_source ())) in
  let marker = "run_stdlib_test \"" in
  let mlen = String.length marker in
  let slen = String.length src in
  let rec scan i acc =
    if i + mlen > slen then List.rev acc
    else if String.sub src i mlen = marker then
      let start = i + mlen in
      match String.index_from_opt src start '"' with
      | None -> List.rev acc
      | Some close -> scan (close + 1) (String.sub src start (close - start) :: acc)
    else scan (i + 1) acc
  in
  scan 0 []

let stdlib_test_files_on_disk () =
  let dir = find_test_stdlib_dir () in
  Sys.readdir dir
  |> Array.to_list
  |> List.filter (fun f ->
       String.length f > 5 && String.sub f 0 5 = "test_" && Filename.check_suffix f ".march")
  |> List.sort compare

(** [test/stdlib/test_*.march] files that are, as of this writing, known to
    be unregistered here -- see
    specs/todos/2026-08-11-test-stdlib-march-files-not-in-ci.md for the full
    audit (37 files, hundreds of passing tests, runnable manually via
    `march test test/stdlib/test_FOO.march` but wired into no automated
    runner). Fixing that is a separate, larger effort than this guard.

    This allowlist exists so the check below stays FATAL for any *new* file
    quietly falling out of the registry -- the failure mode that motivated
    this guard in the first place (test_json.march, see
    specs/progress/2026-07-31-open-follow-up-test-file-registry-drift.md) --
    without turning this whole binary red over the pre-existing gap.

    Shrink this list as files get wired up under that todo. Do NOT add a
    newly-orphaned file here to silence a real failure; register it
    properly instead, or if it's a deliberate deferral, say why inline
    (test_flow.march is the one entry with its own reason: its registration
    a few dozen lines up is commented out because it targets an older,
    function-transformer Flow API that predates the current Seq-based
    flow.march). *)
let known_unregistered_stdlib_test_files = [
  "test_actor.march";
  "test_array.march";
  "test_bigint.march";
  "test_bytes.march";
  "test_check.march";
  "test_cli.march";
  "test_csv.march";
  "test_dataframe.march";
  "test_datetime.march";
  "test_decimal.march";
  "test_derive_json.march";
  "test_derive_json_multi.march";
  "test_dir.march";
  "test_enum.march";
  "test_file.march";
  "test_flow.march";
  "test_gen.march";
  "test_hamt.march";
  "test_html.march";
  "test_iolist.march";
  "test_island_bridges.march";
  "test_iterable.march";
  "test_map.march";
  "test_math.march";
  "test_option.march";
  "test_path.march";
  "test_plot.march";
  "test_prelude.march";
  "test_properties.march";
  "test_queue.march";
  "test_result.march";
  "test_set.march";
  "test_sigil.march";
  "test_sort.march";
  "test_string.march";
  "test_string_utf8.march";
  "test_task.march";
]

let check_registry_drift () =
  let on_disk = stdlib_test_files_on_disk () in
  let registered = registered_stdlib_test_files () in
  let orphaned =
    List.filter
      (fun f ->
         not (List.mem f registered)
         && not (List.mem f known_unregistered_stdlib_test_files))
      on_disk
  in
  let stale_allowlist_entries =
    List.filter
      (fun f -> not (List.mem f on_disk) || List.mem f registered)
      known_unregistered_stdlib_test_files
  in
  if stale_allowlist_entries <> [] then
    Printf.eprintf
      "[test_stdlib_march] note: known_unregistered_stdlib_test_files names \
       %s, which is no longer an orphan (already registered, or no longer \
       on disk) -- trim the allowlist.\n%!"
      (String.concat ", " stale_allowlist_entries);
  if orphaned <> [] then
    Alcotest.failf
      "%d file(s) under test/stdlib/test_*.march are not registered in \
       test_stdlib_march.ml's Alcotest.run list, and are not in the \
       documented pre-existing-gap allowlist \
       (known_unregistered_stdlib_test_files): %s. Either add a \
       `run_stdlib_test \"FILE\" \"ModName\"` entry to the Alcotest.run \
       list above, or -- if this is an intentional, tracked deferral like \
       the other 37 -- add it to known_unregistered_stdlib_test_files with \
       a one-line reason."
      (List.length orphaned)
      (String.concat ", " orphaned)

(* ------------------------------------------------------------------ *)
(* Test cases                                                          *)
(* ------------------------------------------------------------------ *)

let () =
  Alcotest.run "stdlib_march" [
    ("registry", [
      Alcotest.test_case
        "every test/stdlib/test_*.march file is registered or documented as deferred"
        `Quick check_registry_drift;
    ]);
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
    ("hash_map", [
      Alcotest.test_case "HashMap module"
        `Quick (run_stdlib_test "test_hash_map.march" "TestHashMap");
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
    ("seq", [
      Alcotest.test_case "Seq module"
        `Quick (run_stdlib_test "test_seq.march" "TestSeq");
    ]);
    ("json", [
      Alcotest.test_case "Json module"
        `Quick (run_stdlib_test "test_json.march" "TestJson");
    ]);
    ("json_stream", [
      Alcotest.test_case "JsonStream module"
        `Quick (run_stdlib_test "test_json_stream.march" "TestJsonStream");
    ]);
    ("json_typed", [
      Alcotest.test_case "derive Json x JsonStream typed decoding"
        `Quick (run_stdlib_test "test_json_typed.march" "TestJsonTyped");
    ]);
    ("msgpack", [
      Alcotest.test_case "Msgpack module"
        `Quick (run_stdlib_test "test_msgpack.march" "TestMsgpack");
    ]);
    ("toml", [
      Alcotest.test_case "Toml module"
        `Quick (run_stdlib_test "test_toml.march" "TestToml");
    ]);
    ("xml", [
      Alcotest.test_case "Xml module"
        `Quick (run_stdlib_test "test_xml.march" "TestXml");
    ]);
    ("yaml", [
      Alcotest.test_case "Yaml module"
        `Quick (run_stdlib_test "test_yaml.march" "TestYaml");
    ]);
    ("socket", [
      Alcotest.test_case "Socket module"
        `Quick (run_stdlib_test "test_socket.march" "TestSocket");
    ]);
    ("dns", [
      Alcotest.test_case "Dns module"
        `Quick (run_stdlib_test "test_dns.march" "TestDns");
    ]);
    (* test_flow.march tests the function-transformer Flow API (from_fn/run/then_)
       which differs from the current Seq-based flow.march implementation.
    ("flow", [
      Alcotest.test_case "Flow module"
        `Quick (run_stdlib_test "test_flow.march" "TestFlow");
    ]); *)
    ("deque", [
      Alcotest.test_case "Deque module"
        `Quick (run_stdlib_test "test_deque.march" "TestDeque");
    ]);
    ("ring_buf", [
      Alcotest.test_case "RingBuf module"
        `Quick (run_stdlib_test "test_ring_buf.march" "TestRingBuf");
    ]);
    ("net_frame", [
      Alcotest.test_case "NetFrame module"
        `Quick (run_stdlib_test "test_net_frame.march" "TestNetFrame");
    ]);
    ("node_identity", [
      Alcotest.test_case "NodeIdentity module"
        `Quick (run_stdlib_test "test_node_identity.march" "TestNodeIdentity");
    ]);
    ("cluster", [
      Alcotest.test_case "Cluster module"
        `Quick (run_stdlib_test "test_cluster.march" "TestCluster");
    ]);
    ("cluster_auth", [
      Alcotest.test_case "ClusterAuth module"
        `Quick (run_stdlib_test "test_cluster_auth.march" "TestClusterAuth");
    ]);
    ("handshake", [
      Alcotest.test_case "Handshake module"
        `Quick (run_stdlib_test "test_handshake.march" "TestHandshake");
    ]);
    ("membership", [
      Alcotest.test_case "Membership module"
        `Quick (run_stdlib_test "test_membership.march" "TestMembership");
    ]);
    ("swim", [
      Alcotest.test_case "Swim module"
        `Quick (run_stdlib_test "test_swim.march" "TestSwim");
    ]);
    ("swim_driver", [
      Alcotest.test_case "SwimDriver module"
        `Quick (run_stdlib_test "test_swim_driver.march" "TestSwimDriver");
    ]);
    ("global_registry", [
      Alcotest.test_case "GlobalRegistry module"
        `Quick (run_stdlib_test "test_global_registry.march" "TestGlobalRegistry");
    ]);
    ("global_pid", [
      Alcotest.test_case "GlobalPid module"
        `Quick (run_stdlib_test "test_global_pid.march" "TestGlobalPid");
    ]);
    ("remote_call", [
      Alcotest.test_case "RemoteCall module"
        `Quick (run_stdlib_test "test_remote_call.march" "TestRemoteCall");
    ]);
    ("node_rpc", [
      Alcotest.test_case "NodeRpc module"
        `Quick (run_stdlib_test "test_node_rpc.march" "TestNodeRpc");
    ]);
    ("remote_ref_hashes", [
      Alcotest.test_case "remote_ref_hashes builtin"
        `Quick (run_stdlib_test "test_remote_ref_hashes.march" "TestRemoteRefHashes");
    ]);
    ("net_kernel", [
      Alcotest.test_case "NetKernel module"
        `Quick (run_stdlib_test "test_net_kernel.march" "TestNetKernel");
    ]);
    ("peer_registry", [
      Alcotest.test_case "PeerRegistry module"
        `Quick (run_stdlib_test "test_peer_registry.march" "TestPeerRegistry");
    ]);
    ("vector_clock", [
      Alcotest.test_case "VectorClock module"
        `Quick (run_stdlib_test "test_vector_clock.march" "TestVectorClock");
    ]);
    ("merkle", [
      Alcotest.test_case "Merkle module"
        `Quick (run_stdlib_test "test_merkle.march" "TestMerkle");
    ]);
    ("crdt", [
      Alcotest.test_case "CRDT module"
        `Quick (run_stdlib_test "test_crdt.march" "TestCrdt");
    ]);
    ("consistent_hash", [
      Alcotest.test_case "ConsistentHash module"
        `Quick (run_stdlib_test "test_consistent_hash.march" "TestConsistentHash");
    ]);
    ("list_parallel", [
      Alcotest.test_case "List parallel ops"
        `Quick (run_stdlib_test "test_list_parallel.march" "TestListParallel");
    ]);
    ("rrb_vec", [
      Alcotest.test_case "RRB.Vec and Parallel modules"
        `Quick (run_stdlib_test "test_rrb_vec.march" "TestRRBVec");
    ]);
    ("list", [
      Alcotest.test_case "List module"
        `Quick (run_stdlib_test "test_list.march" "TestList");
    ]);
    ("work_dispatch", [
      Alcotest.test_case "WorkDispatch module"
        `Quick (run_stdlib_test "test_work_dispatch.march" "TestWorkDispatch");
    ]);
    ("dist_link", [
      Alcotest.test_case "DistLink module"
        `Quick (run_stdlib_test "test_dist_link.march" "TestDistLink");
    ]);
    ("dist_supervisor", [
      Alcotest.test_case "DistSupervisor module"
        `Quick (run_stdlib_test "test_dist_supervisor.march" "TestDistSupervisor");
    ]);
    ("regex", [
      Alcotest.test_case "Regex module"
        `Quick (run_stdlib_test "test_regex.march" "TestRegex");
    ]);
    ("aho_corasick", [
      Alcotest.test_case "AhoCorasick module"
        `Quick (run_stdlib_test "test_aho_corasick.march" "TestAhoCorasick");
    ]);
    ("parse", [
      Alcotest.test_case "Parse module"
        `Quick (run_stdlib_test "test_parse.march" "TestParse");
    ]);
    ("parse_errors", [
      Alcotest.test_case "Parse golden error corpus"
        `Quick (run_stdlib_test "test_parse_errors.march" "TestParseErrors");
    ]);
  ]
