(* Observe_client: the forge side of the node observe socket
   (runtime/march_observe.c; R0 of specs/plans/2026-09-28-observe-recon-shell-plan.md).
   The server itself is tested by test/test_observe.c and the native
   observe_ping golden; here a forked fake server answers one request so the
   client's transport, framing and envelope parsing are exercised without a
   compiled node. *)
open March_forge

let envelope ?error ?data () =
  let tail = match error, data with
    | Some e, _ -> Printf.sprintf ",\"error\":%S" e
    | None, Some d -> ",\"data\":" ^ d
    | None, None -> ",\"data\":null" in
  "{\"proto\":\"march.observe/1\",\"node\":\"pid:1\",\"at_ms\":1,\"took_us\":2,\"truncated\":false"
  ^ tail ^ "}"

let tmp_dir () =
  let d = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "obsc%d_%d" (Unix.getpid ()) (Random.int 1_000_000)) in
  Unix.mkdir d 0o700; d

(* Serve one connection on [path]: write the line it receives to [seen], then
   answer with [reply] and close. *)
let fake_server path ~seen ~reply =
  (try Sys.remove path with Sys_error _ -> ());
  let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Unix.bind fd (Unix.ADDR_UNIX path);
  Unix.listen fd 1;
  match Unix.fork () with
  | 0 ->
    let (c, _) = Unix.accept fd in
    let ic = Unix.in_channel_of_descr c and oc = Unix.out_channel_of_descr c in
    let line = try input_line ic with End_of_file -> "" in
    Out_channel.with_open_bin seen (fun o -> output_string o line);
    output_string oc (reply ^ "\n"); flush oc;
    Unix._exit 0
  | p -> Unix.close fd; p

let host_at dir = { Hosts.name = "n1"; ssh = ""; socket = Filename.concat dir "r.sock";
                    pubkey = ""; labels = [] }

let test_parse_ok () =
  match Observe_client.parse_reply (envelope ~data:"\"pong\"" ()) with
  | Ok r ->
    Alcotest.(check string) "data" "\"pong\"" (Yojson.Safe.to_string (Observe_client.data_of r));
    Alcotest.(check bool) "not truncated" false (Observe_client.truncated r)
  | Error e -> Alcotest.fail e

let test_parse_errors () =
  let err s = match Observe_client.parse_reply s with Ok _ -> "ok" | Error e -> e in
  Alcotest.(check string) "error envelope" "observe: busy" (err (envelope ~error:"busy" ()));
  Alcotest.(check bool) "malformed" true
    (String.starts_with ~prefix:"observe: malformed reply" (err "{\"proto\":"));
  Alcotest.(check string) "other protocol" "observe: unsupported protocol x/9"
    (err "{\"proto\":\"x/9\",\"data\":1}");
  Alcotest.(check string) "not an object" "observe: reply is not a JSON object" (err "[1]");
  Alcotest.(check string) "no protocol" "observe: reply has no protocol field" (err "{\"data\":1}")

let test_query_round_trip () =
  let dir = tmp_dir () in
  let h = host_at dir in
  let seen = Filename.concat dir "seen" in
  let pid = fake_server (Observe_client.socket_of h) ~seen ~reply:(envelope ~data:"{\"n\":3}" ()) in
  let r = Observe_client.query Remote.local h "ACTORS mbox 5" in
  ignore (Unix.waitpid [] pid);
  Alcotest.(check string) "the request reached the observe socket, not the reload socket"
    "ACTORS mbox 5" (In_channel.with_open_bin seen In_channel.input_all);
  match r with
  | Ok reply ->
    Alcotest.(check string) "data" "{\"n\":3}" (Yojson.Safe.to_string (Observe_client.data_of reply))
  | Error e -> Alcotest.fail e

let test_query_error_reply () =
  let dir = tmp_dir () in
  let h = host_at dir in
  let seen = Filename.concat dir "seen" in
  let pid = fake_server (Observe_client.socket_of h) ~seen ~reply:(envelope ~error:"busy" ()) in
  let r = Observe_client.query Remote.local h "PING" in
  ignore (Unix.waitpid [] pid);
  match r with
  | Ok _ -> Alcotest.fail "an error envelope must be an Error"
  | Error e -> Alcotest.(check string) "busy is an error" "observe: busy" e

let test_query_no_socket () =
  let dir = tmp_dir () in
  match Observe_client.query Remote.local (host_at dir) "PING" with
  | Ok _ -> Alcotest.fail "expected an error with no socket"
  | Error e -> Alcotest.(check bool) "connect error" true (String.length e > 0)

let test_query_rejects_multiline () =
  let dir = tmp_dir () in
  match Observe_client.query Remote.local (host_at dir) "PING\nHELP" with
  | Ok _ -> Alcotest.fail "a two-line request must be refused"
  | Error e -> Alcotest.(check string) "refused" "observe: a request is a single line" e

let () =
  Random.self_init ();
  Alcotest.run "observe_client" [
    "parse", [
      Alcotest.test_case "ok envelope" `Quick test_parse_ok;
      Alcotest.test_case "error and malformed replies" `Quick test_parse_errors;
    ];
    "query", [
      Alcotest.test_case "round trip over the local transport" `Quick test_query_round_trip;
      Alcotest.test_case "an error envelope is an Error" `Quick test_query_error_reply;
      Alcotest.test_case "no socket" `Quick test_query_no_socket;
      Alcotest.test_case "multi-line request refused" `Quick test_query_rejects_multiline;
    ];
  ]
