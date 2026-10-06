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

(* query_socket: an observe socket addressed by its own path, the
   [forge observe --socket] path. *)
let test_query_socket () =
  let dir = tmp_dir () in
  let path = Filename.concat dir "o.sock" in
  let seen = Filename.concat dir "seen" in
  let pid = fake_server path ~seen ~reply:(envelope ~data:"\"pong\"" ()) in
  let r = Observe_client.query_socket path "PING" in
  ignore (Unix.waitpid [] pid);
  Alcotest.(check string) "the path is used as given (no .observe suffix)"
    "PING" (In_channel.with_open_bin seen In_channel.input_all);
  match r with
  | Ok reply -> Alcotest.(check string) "data" "\"pong\"" (Yojson.Safe.to_string (Observe_client.data_of reply))
  | Error e -> Alcotest.fail e

let test_request_of () =
  let r ?(sections = []) words = Cmd_observe.request_of ~words ~sections in
  let ok = Alcotest.(result string string) in
  Alcotest.check ok "default" (Ok "SNAPSHOT") (r []);
  Alcotest.check ok "sections" (Ok "SNAPSHOT actors,mem") (r ~sections:["actors"; "mem"] []);
  Alcotest.check ok "verb upper-cased, arguments kept" (Ok "ACTORS mbox 20") (r ["actors"; "mbox"; "20"]);
  Alcotest.check ok "both refused" (Error "observe: give a request or --section, not both")
    (r ~sections:["mem"] ["TREE"])

let hr ?(ssh = "") envs =
  { Project.hr_socket = "/run/app.sock"; hr_ssh_host = ssh; hr_public_key = None;
    hr_envs = envs; hr_health_check_url = None; hr_strategy = "rolling";
    hr_target = None; hr_module_prefix = None; hr_compact_after = None }

let env name host =
  { Project.hre_name = name; hre_ssh_host = host; hre_socket = "/run/" ^ name ^ ".sock";
    hre_public_key = None }

let test_hosts_of () =
  let names r = match r with
    | Ok hs -> List.map (fun h -> h.Hosts.name ^ "@" ^ h.Hosts.ssh) hs
    | Error e -> [ "error: " ^ e ] in
  let l = Alcotest.(list string) in
  Alcotest.check l "flat config is the one host" [ "default@root@a" ]
    (names (Cmd_observe.hosts_of (hr ~ssh:"root@a" []) ~env:""));
  let two = hr [ env "web" "root@w"; env "jobs" "root@j" ] in
  Alcotest.check l "every env by default" [ "web@root@w"; "jobs@root@j" ]
    (names (Cmd_observe.hosts_of two ~env:""));
  Alcotest.check l "--env picks one" [ "jobs@root@j" ] (names (Cmd_observe.hosts_of two ~env:"jobs"));
  Alcotest.check l "unknown env" [ "error: observe: no [[hot-reload.env]] named db" ]
    (names (Cmd_observe.hosts_of two ~env:"db"));
  Alcotest.(check bool) "no host at all is an error" true
    (match Cmd_observe.hosts_of (hr []) ~env:"" with Error _ -> true | Ok _ -> false)

(* The signed debug request: what march_observe_debug.c verifies is the line
   without its signature word, signed by the deploy key. *)
let test_signed_request () =
  let pk, sk = March_ed25519.Ed25519.keygen () in
  let line = Observe_client.signed_request ~sk ~nonce:"00112233445566778899aabbccddeeff"
      ~now_ms:1_000_000 "STATE" [ "pid:7"; "timeout_ms:500" ] in
  match String.split_on_char ' ' line with
  | verb :: sig_b64 :: rest ->
    Alcotest.(check string) "verb first" "STATE" verb;
    Alcotest.(check (list string)) "fields after the signature"
      [ "nonce:00112233445566778899aabbccddeeff"; "not_after_ms:1030000"; "pid:7"; "timeout_ms:500" ] rest;
    let signed = String.concat " " (verb :: rest) in
    let raw = Cmd_hot_reload.b64_decode_raw sig_b64 in
    let ok = match raw with
      | Some b -> March_ed25519.Ed25519.verify (Bytes.of_string signed) (Bytes.sub b 0 64) pk
      | None -> false in
    Alcotest.(check bool) "the signature verifies over the line without it" true ok;
    let bad = match raw with
      | Some b -> March_ed25519.Ed25519.verify (Bytes.of_string (signed ^ "x")) (Bytes.sub b 0 64) pk
      | None -> true in
    Alcotest.(check bool) "and over nothing else" false bad
  | _ -> Alcotest.fail line

let test_explain_debug_error () =
  let has sub s =
    let n = String.length s and m = String.length sub in
    let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in go 0 in
  Alcotest.(check bool) "expired names the clock" true
    (has "ahead" (Observe_client.explain_debug_error "observe: expired"));
  Alcotest.(check bool) "too far names the clock" true
    (has "behind" (Observe_client.explain_debug_error "observe: not_after_too_far"));
  Alcotest.(check bool) "policy names the file" true
    (has "MARCH_DEBUG_POLICY" (Observe_client.explain_debug_error "n1: observe: policy"));
  Alcotest.(check string) "anything else unchanged" "observe: busy"
    (Observe_client.explain_debug_error "observe: busy")

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
      Alcotest.test_case "query_socket uses the path as given" `Quick test_query_socket;
      Alcotest.test_case "signed debug request" `Quick test_signed_request;
      Alcotest.test_case "debug refusals explained" `Quick test_explain_debug_error;
    ];
    "forge observe", [
      Alcotest.test_case "request line" `Quick test_request_of;
      Alcotest.test_case "hosts from forge.toml" `Quick test_hosts_of;
    ];
  ]
