(* Host scopes on IO.NetConnect (lib/caps/host_scope.ml).

   The algebra is pure, so these pin the cases that would make a scope read as
   enforcement while leaking: a wildcard that admits its own apex or a
   look-alike suffix, a literal URL whose authority the runtime parser reads
   differently, and the default-port rule.  See
   specs/2026-11-09-host-scoped-network-capabilities-design.md. *)

module H = March_caps.Host_scope

let pat s =
  match H.parse_pattern s with
  | Ok p -> p
  | Error e -> Alcotest.failf "parse_pattern %S failed: %s" s e

let decls l =
  List.map
    (fun s ->
       match H.parse_decl (Some s) with
       | Ok d -> d
       | Error e -> Alcotest.failf "parse_decl %S failed: %s" s e)
    l

let test_parse_rejects () =
  List.iter
    (fun s ->
       match H.parse_pattern s with
       | Ok _ -> Alcotest.failf "pattern %S should be rejected" s
       | Error _ -> ())
    [ "https://a.com"; "a.com/../x"; "u@a.com"; "a..com"; "*"; "a.*.com";
      "\xc3\xa9.com"; ""; "*.com:"; "a.com:0"; "a.com:99999" ]

let test_parse_accepts () =
  List.iter
    (fun s ->
       match H.parse_pattern s with
       | Ok _ -> ()
       | Error e -> Alcotest.failf "pattern %S should parse: %s" s e)
    [ "example.com"; "example.com:8443"; "*.example.com"; "203.0.113.7";
      "[2001:db8::1]"; "[2001:db8::1]:443"; "localhost" ]

let test_wildcard () =
  let p = pat "*.example.com" in
  let m h = H.matches p ~host:h ~port:443 in
  Alcotest.(check bool) "subdomain" true (m "api.example.com");
  Alcotest.(check bool) "deep subdomain" true (m "a.b.example.com");
  Alcotest.(check bool) "apex is not a subdomain" false (m "example.com");
  Alcotest.(check bool) "look-alike suffix" false (m "badexample.com")

let test_case_and_trailing_dot () =
  Alcotest.(check bool) "case and trailing dot" true
    (H.matches (pat "example.com") ~host:"Example.COM." ~port:443);
  Alcotest.(check bool) "pattern side normalized too" true
    (H.matches (pat "Example.Com.") ~host:"example.com" ~port:443)

let test_ports () =
  let p = pat "example.com:8443" in
  Alcotest.(check bool) "named port" true
    (H.matches p ~host:"example.com" ~port:8443);
  Alcotest.(check bool) "other port" false
    (H.matches p ~host:"example.com" ~port:443);
  Alcotest.(check bool) "portless pattern admits any port" true
    (H.matches (pat "example.com") ~host:"example.com" ~port:9)

let authority = Alcotest.(option (pair string int))

let auth ~prefix s =
  Option.map (fun (a : H.authority) -> (a.a_host, a.a_port))
    (H.authority_of_url ~prefix s)

let test_default_ports () =
  Alcotest.check authority "http default" (Some ("example.com", 80))
    (auth ~prefix:false "http://example.com/");
  Alcotest.check authority "https default, no path" (Some ("example.com", 443))
    (auth ~prefix:false "https://example.com");
  Alcotest.check authority "explicit port" (Some ("example.com", 8443))
    (auth ~prefix:false "https://example.com:8443/x");
  Alcotest.check authority "host lowercased" (Some ("example.com", 443))
    (auth ~prefix:false "https://Example.COM./x");
  Alcotest.(check bool) "http under a :443 scope is refused" false
    (H.permits (decls [ "example.com:443" ]) ~host:"example.com" ~port:80);
  Alcotest.(check bool) "explicit :443 under a portless scope" true
    (H.permits (decls [ "example.com" ]) ~host:"example.com" ~port:443)

let test_authority_prefix () =
  Alcotest.check authority "complete prefix" (Some ("example.com", 443))
    (auth ~prefix:true "https://example.com/");
  List.iter
    (fun s ->
       Alcotest.check authority s None (auth ~prefix:true s))
    [ "https://example.com"; "https://example.com?"; "https://example.com#";
      "https://a.com@b.com/"; "https://a.com\\@b.com/"; "ftp://a.com/";
      "https://a.com:/"; "https://a com/"; "https://a.com%2f/";
      "https://[2001:db8::1]/"; "https:///" ]

let test_whole_url_rejects_confusing_authority () =
  List.iter
    (fun s -> Alcotest.check authority s None (auth ~prefix:false s))
    [ "https://example.com@foo.com/"; "https://foo.com\\@example.com/";
      "https://example.com?x"; "notaurl" ]

let test_no_redirects_decl () =
  (match H.parse_decl (Some "a.com;no_redirects") with
   | Ok d ->
     Alcotest.(check bool) "flag" true d.no_redirects;
     Alcotest.(check int) "one pattern" 1 (List.length d.patterns)
   | Error e -> Alcotest.fail e);
  (match H.parse_decl (Some ";no_redirects") with
   | Ok d ->
     Alcotest.(check bool) "flag" true d.no_redirects;
     Alcotest.(check int) "any host" 0 (List.length d.patterns)
   | Error e -> Alcotest.fail e);
  (match H.parse_decl None with
   | Ok d ->
     Alcotest.(check bool) "unscoped" false d.no_redirects;
     Alcotest.(check int) "any host" 0 (List.length d.patterns)
   | Error e -> Alcotest.fail e);
  (match H.parse_decl (Some "a.com;sometimes") with
   | Ok _ -> Alcotest.fail "unknown option accepted"
   | Error _ -> ())

let test_forbids_redirects () =
  let ds = decls [ "a.com;no_redirects"; "b.com" ] in
  Alcotest.(check bool) "a.com forbids" true
    (H.forbids_redirects ds ~host:"a.com" ~port:443);
  Alcotest.(check bool) "b.com follows" false
    (H.forbids_redirects ds ~host:"b.com" ~port:443)

let test_spec_roundtrip () =
  List.iter
    (fun l ->
       let ds = decls l in
       Alcotest.(check bool) (String.concat "|" l) true
         (H.decode_spec (H.encode_spec ds) = ds))
    [ [ "a.com" ]; [ "a.com;no_redirects"; "*.b.com:8443" ];
      [ ";no_redirects" ] ];
  Alcotest.(check string) "empty = any host" "" (H.encode_spec []);
  Alcotest.(check bool) "decode empty" true (H.decode_spec "" = [])

let test_permits_union () =
  let ds = decls [ "a.com"; "b.com" ] in
  Alcotest.(check bool) "a" true (H.permits ds ~host:"a.com" ~port:443);
  Alcotest.(check bool) "b" true (H.permits ds ~host:"b.com" ~port:443);
  Alcotest.(check bool) "c" false (H.permits ds ~host:"c.com" ~port:443);
  Alcotest.(check bool) "no decls = unscoped" true
    (H.permits [] ~host:"c.com" ~port:443);
  Alcotest.(check bool) "an any-host decl = unscoped" true
    (H.permits (decls [ "a.com"; ";no_redirects" ]) ~host:"c.com" ~port:443)

(* ── Declarations (Task 2) ───────────────────────────────────────────── *)

let errors_of src = Test_helpers.typecheck src

let messages ctx =
  List.map (fun (d : March_errors.Errors.diagnostic) -> d.message)
    (March_errors.Errors.sorted ctx)

let decl_src decl =
  Printf.sprintf
    {|mod HostDecl do
  %s
  fn f(x : Int) : Int do x end
end
|}
    decl

let accepts name decl =
  let ctx = errors_of (decl_src decl) in
  if March_errors.Errors.has_errors ctx then
    Alcotest.failf "%s should typecheck:\n%s" name
      (String.concat "\n" (messages ctx))

let rejects_with name ~expect decl =
  let ctx = errors_of (decl_src decl) in
  if not (March_errors.Errors.has_errors ctx) then
    Alcotest.failf "%s should be rejected" name;
  if not (List.exists
            (fun m ->
               match Str.search_forward (Str.regexp_string expect) m 0 with
               | _ -> true
               | exception Not_found -> false)
            (messages ctx))
  then
    Alcotest.failf "%s rejected, but not with %S:\n%s" name expect
      (String.concat "\n" (messages ctx))

let test_net_scope_accepted () =
  accepts "host scope" {|needs IO.NetConnect("example.com")|};
  accepts "two hosts" {|needs IO.NetConnect("example.com"), IO.NetConnect("*.foo.com:8443")|}

let test_net_scope_bad_pattern () =
  rejects_with "scheme in scope" ~expect:"scheme"
    {|needs IO.NetConnect("https://example.com")|};
  rejects_with "dot segment in a path scope" ~expect:".."
    {|needs IO.NetConnect("example.com/../api/")|}

let test_other_net_caps_rejected () =
  rejects_with "TLS scope" ~expect:"IO.NetConnect"
    {|needs IO.NetConnect.TLS("example.com")|};
  rejects_with "Network scope" ~expect:"does not take"
    {|needs IO.Network("example.com")|}

let test_no_redirects_parses () =
  accepts "host + no_redirects" {|needs IO.NetConnect("example.com", no_redirects)|};
  accepts "bare no_redirects" {|needs IO.NetConnect(no_redirects)|};
  rejects_with "no_redirects on a filesystem cap" ~expect:"no_redirects"
    {|needs IO.FileRead("/etc", no_redirects)|}

let test_fs_scope_unchanged () =
  accepts "fs scope" {|needs IO.FileRead("/etc/myapp")|};
  rejects_with "relative fs scope" ~expect:"relative path"
    {|needs IO.FileRead("etc")|}

let test_fs_manifest_ignores_net () =
  Alcotest.(check (option string)) "no FS manifest for a host scope" None
    (March_caps.Cap_scope.manifest_json [ ("IO.NetConnect", Some "a.com") ])

let test_declared_net_scopes_per_module () =
  let src =
    {|mod Top do
  mod A do
    needs IO.NetConnect("a.com")
    fn f(x : Int) : Int do x end
  end
  mod B do
    needs IO.NetConnect("b.com", no_redirects)
    fn g(x : Int) : Int do x end
  end
  mod C do
    needs IO.NetConnect
    fn h(x : Int) : Int do x end
  end
  fn main() : Int do 1 end
end
|}
  in
  let ctx, _, env =
    March_typecheck.Typecheck.check_module_full (Test_helpers.parse_and_desugar src)
  in
  if March_errors.Errors.has_errors ctx then
    Alcotest.failf "fixture should typecheck:\n%s" (String.concat "\n" (messages ctx));
  let scopes = March_typecheck.Typecheck.declared_net_scopes env ~entry_module:"Top" in
  let hosts m =
    match List.assoc_opt m scopes with
    | None -> Alcotest.failf "no entry for module %s" m
    | Some ds ->
      List.concat_map
        (fun (d : H.decl) ->
           List.map
             (fun p -> H.pattern_to_string p ^ if d.no_redirects then "!" else "")
             d.patterns)
        ds
  in
  Alcotest.(check (list string)) "A" [ "a.com" ] (hosts "A");
  Alcotest.(check (list string)) "B" [ "b.com!" ] (hosts "B");
  Alcotest.(check (list string)) "C is unscoped" [] (hosts "C")

let test_format_roundtrip () =
  let src =
    "mod F do\n  needs IO.NetConnect(\"a.com\", no_redirects), IO.NetConnect(no_redirects)\nend\n"
  in
  let out = March_format.Format.format_source ~filename:"f.march" src in
  List.iter
    (fun want ->
       match Str.search_forward (Str.regexp_string want) out 0 with
       | _ -> ()
       | exception Not_found -> Alcotest.failf "formatted output lacks %S:\n%s" want out)
    [ {|IO.NetConnect("a.com", no_redirects)|}; {|IO.NetConnect(no_redirects)|} ]

(* ── The run-time matcher and parser agree with the compile-time ones ──── *)

let compiler_exe =
  Filename.concat (Filename.dirname Sys.executable_name) "../bin/main.exe"

let run_march src =
  let f = Filename.temp_file "host_scope_diff" ".march" in
  let oc = open_out f in
  output_string oc src;
  close_out oc;
  let out = Filename.temp_file "host_scope_diff" ".out" in
  let rc =
    Sys.command
      (Printf.sprintf "%s %s > %s 2>&1 </dev/null" (Filename.quote compiler_exe)
         (Filename.quote f) (Filename.quote out))
  in
  let ic = open_in out in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  Sys.remove f;
  Sys.remove out;
  if rc <> 0 then Alcotest.failf "march program failed (rc=%d):\n%s" rc s;
  String.split_on_char '\n' (String.trim s)

let march_str s = "\"" ^ String.escaped s ^ "\""

let matcher_corpus =
  [ ("", "anything.test", 443); ("example.com", "example.com", 443);
    ("example.com", "Example.COM.", 80); ("example.com", "foo.com", 443);
    ("example.com,foo.com", "foo.com", 443); ("*.example.com", "api.example.com", 443);
    ("*.example.com", "a.b.example.com", 8443); ("*.example.com", "example.com", 443);
    ("*.example.com", "badexample.com", 443); ("example.com:8443", "example.com", 8443);
    ("example.com:8443", "example.com", 443); ("!example.com", "example.com", 443);
    ("!", "whatever.test", 443); ("203.0.113.7", "203.0.113.7", 80);
    ("[2001:db8::1]:443", "[2001:db8::1]", 443); ("[2001:db8::1]:443", "[2001:db8::1]", 80) ]

let test_matcher_agrees () =
  let lines =
    List.map
      (fun (spec, host, port) ->
         Printf.sprintf
           "    println(if HttpClient.hc_scope_permits(%s, %s, %d) do \"true\" else \"false\" end)"
           (march_str spec) (march_str host) port)
      matcher_corpus
  in
  let src =
    Printf.sprintf
      "mod Diff do\n  needs IO.Console\n  fn main(_c : Cap(IO.Console)) do\n%s\n  end\nend\n"
      (String.concat "\n" lines)
  in
  let got = run_march src in
  Alcotest.(check int) "one line per case" (List.length matcher_corpus) (List.length got);
  List.iter2
    (fun (spec, host, port) line ->
       let want = H.permits (H.decode_spec spec) ~host ~port in
       Alcotest.(check string)
         (Printf.sprintf "%S admits %s:%d" spec host port)
         (string_of_bool want) line)
    matcher_corpus got

let method_corpus =
  [ ("api.com@get", "api.com", 443, "get"); ("api.com@get", "api.com", 443, "post");
    ("api.com@get+head", "api.com", 443, "head"); ("api.com@get,api.com@post", "api.com", 443, "post");
    ("api.com", "api.com", 443, "delete"); ("@get", "any.test", 443, "get");
    ("@get", "any.test", 443, "put"); ("!api.com@post", "api.com", 443, "post");
    ("other.com@get", "api.com", 443, "get"); ("", "api.com", 443, "patch") ]

let test_method_matcher_agrees () =
  let lines =
    List.map
      (fun (spec, host, port, m) ->
         Printf.sprintf
           "    println(if HttpClient.hc_scope_permits_method(%s, %s, %d, %s) do \"true\" else \"false\" end)"
           (march_str spec) (march_str host) port (march_str m))
      method_corpus
  in
  let src =
    Printf.sprintf
      "mod MDiff do\n  needs IO.Console\n  fn main(_c : Cap(IO.Console)) do\n%s\n  end\nend\n"
      (String.concat "\n" lines)
  in
  let got = run_march src in
  Alcotest.(check int) "one line per case" (List.length method_corpus) (List.length got);
  List.iter2
    (fun (spec, host, port, m) line ->
       let want = H.permits_method (H.decode_spec spec) ~host ~port ~meth:m in
       Alcotest.(check string)
         (Printf.sprintf "%S admits %s %s:%d" spec m host port)
         (string_of_bool want) line)
    method_corpus got

let path_corpus =
  [ ("a.test/v1/weather/", "a.test", 443, "get", "/v1/weather/today");
    ("a.test/v1/weather/", "a.test", 443, "get", "/v1/weatherman");
    ("a.test/v1/weather/", "a.test", 443, "get", "/v1/weather");
    ("a.test/v1/weather/", "a.test", 443, "get", "/v1/weather/../admin");
    ("a.test/v1/weather/", "a.test", 443, "get", "/v1/weather/%2e%2e/x");
    ("a.test/v1/weather/", "a.test", 443, "get", "/v1/weather//x");
    ("a.test/v1/weather/@get", "a.test", 443, "post", "/v1/weather/x");
    ("a.test/v1/x/,a.test/v2/", "a.test", 443, "get", "/v2/y");
    ("a.test/v1/x/,a.test/v2/", "a.test", 443, "get", "/v1/y");
    ("a.test", "a.test", 443, "get", "/anything/../x");
    ("", "a.test", 443, "get", "/x");
    ("a.test:8443/v1/", "a.test", 443, "get", "/v1/x");
    ("a.test/v1/weather/", "a.test", 443, "get", "/v1/weather/x HTTP/1.1\r\nHost: h\r\n\r\nDELETE /admin");
    ("a.test/v1/weather/", "a.test", 443, "get", "/v1/weather/..;/admin");
    ("a.test/v1/weather/", "a.test", 443, "get", "/v1/weather/%252e%252e/admin");
    ("a.test/v1/weather/", "a.test", 443, "get", "/v1/weather/#/../../admin");
    ("a.test/v1/weather/", "a.test", 443, "get", "/v1/weather?x=1");
    ("a.test/v1/weather/", "a.test", 443, "get", "/v1/weather/a%20b") ]

let test_path_matcher_agrees () =
  let lines =
    List.map
      (fun (spec, host, port, m, path) ->
         Printf.sprintf
           "    println(if Http.scope_permits_request(%s, %s, %d, %s, %s) do \"true\" else \"false\" end)"
           (march_str spec) (march_str host) port (march_str m) (march_str path))
      path_corpus
  in
  let src =
    Printf.sprintf
      "mod PDiff do\n  needs IO.Console\n  fn main(_c : Cap(IO.Console)) do\n%s\n  end\nend\n"
      (String.concat "\n" lines)
  in
  let got = run_march src in
  Alcotest.(check int) "one line per case" (List.length path_corpus) (List.length got);
  List.iter2
    (fun (spec, host, port, m, path) line ->
       let want =
         H.permits_request (H.decode_spec spec) ~host ~port ~meth:(Some m) ~path:(Some path)
       in
       Alcotest.(check string)
         (Printf.sprintf "%S admits %s %s%s" spec m host path)
         (string_of_bool want) line)
    path_corpus got

let url_corpus =
  [ "http://example.com/"; "https://example.com"; "https://example.com:8443/x";
    "https://Example.COM./x"; "http://203.0.113.7:8080/a?b=c"; "https://a-b.c-d.test/p" ]

let test_url_parser_agrees () =
  let lines =
    List.map
      (fun u ->
         Printf.sprintf
           "    match Http.parse_url(%s) do\n    Ok(r) -> println(Http.host(r) ++ \" \" ++ int_to_string(HttpClient.hc_effective_port(Http.scheme(r), Http.port(r))))\n    Err(_) -> println(\"ERR\")\n    end"
           (march_str u))
      url_corpus
  in
  let src =
    Printf.sprintf
      "mod UrlDiff do\n  needs IO.Console\n  fn main(_c : Cap(IO.Console)) do\n%s\n  end\nend\n"
      (String.concat "\n" lines)
  in
  let got = run_march src in
  Alcotest.(check int) "one line per URL" (List.length url_corpus) (List.length got);
  List.iter2
    (fun u line ->
       match H.authority_of_url ~prefix:false u with
       | None -> Alcotest.failf "corpus URL %S should be host-evident" u
       | Some a -> (
           match String.split_on_char ' ' line with
           | [ host; port ] ->
             Alcotest.(check string) (u ^ " host") a.a_host (H.normalize_host host);
             Alcotest.(check string) (u ^ " port") (string_of_int a.a_port) port
           | _ -> Alcotest.failf "%S: runtime said %S" u line))
    url_corpus got

(* ── Destination table (Task 4) ──────────────────────────────────────── *)

module D = March_caps.Net_dest

let test_every_net_builtin_classified () =
  let missing =
    List.filter_map
      (fun (name, cap) ->
         if D.is_network_cap cap && D.builtin_dest name = None then Some name
         else None)
      March_typecheck.Typecheck.builtin_cap_table
  in
  Alcotest.(check (list string)) "network builtins without a destination row" []
    missing

let test_tls_connect_is_handle () =
  Alcotest.(check bool) "tls_connect's hostname is not a destination" true
    (D.builtin_dest "tls_connect" = Some D.Handle);
  Alcotest.(check bool) "tcp_connect takes a host" true
    (D.builtin_dest "tcp_connect" = Some (D.Host (0, Some 1)))

let test_bad_net_dest_param () =
  let src =
    {|mod BadDest do
  @[net_dest(nope)]
  fn f(url : String) : String do url end
end
|}
  in
  let ctx = errors_of src in
  if not
       (List.exists
          (fun m ->
             match Str.search_forward (Str.regexp_string "nope") m 0 with
             | _ -> true
             | exception Not_found -> false)
          (messages ctx))
  then
    Alcotest.failf "@[net_dest(nope)] should be rejected naming `nope`:\n%s"
      (String.concat "\n" (messages ctx))

let test_good_net_dest_param () =
  let src =
    {|mod GoodDest do
  @[net_dest(url)]
  fn f(url : String) : String do url end
end
|}
  in
  let ctx = errors_of src in
  if March_errors.Errors.has_errors ctx then
    Alcotest.failf "@[net_dest(url)] should typecheck:\n%s"
      (String.concat "\n" (messages ctx))

let dest_tests =
  [
    Alcotest.test_case "every network builtin classified" `Quick
      test_every_net_builtin_classified;
    Alcotest.test_case "tls_connect is a handle op" `Quick test_tls_connect_is_handle;
    Alcotest.test_case "bad @[net_dest] param" `Quick test_bad_net_dest_param;
    Alcotest.test_case "good @[net_dest] param" `Quick test_good_net_dest_param;
  ]

let decl_tests =
  [
    Alcotest.test_case "net scope accepted" `Quick test_net_scope_accepted;
    Alcotest.test_case "net scope bad pattern" `Quick test_net_scope_bad_pattern;
    Alcotest.test_case "other net caps rejected" `Quick test_other_net_caps_rejected;
    Alcotest.test_case "no_redirects parses" `Quick test_no_redirects_parses;
    Alcotest.test_case "fs scope unchanged" `Quick test_fs_scope_unchanged;
    Alcotest.test_case "fs manifest ignores net" `Quick test_fs_manifest_ignores_net;
    Alcotest.test_case "declared net scopes per module" `Quick
      test_declared_net_scopes_per_module;
    Alcotest.test_case "format roundtrip" `Quick test_format_roundtrip;
    Alcotest.test_case "matcher agrees with the stdlib" `Slow test_matcher_agrees;
    Alcotest.test_case "method matcher agrees with the stdlib" `Slow
      test_method_matcher_agrees;
    Alcotest.test_case "path matcher agrees with the stdlib" `Slow
      test_path_matcher_agrees;
    Alcotest.test_case "URL parser agrees with Http.parse_url" `Slow
      test_url_parser_agrees;
  ]

(* ── Method scopes (Task 8) ─────────────────────────────────────────── *)

let test_methods_decl () =
  (match H.parse_decl (Some "a.com;methods=get,head") with
   | Ok d ->
     Alcotest.(check (option (list string))) "methods" (Some [ "get"; "head" ]) d.methods;
     Alcotest.(check bool) "no flag" false d.no_redirects
   | Error e -> Alcotest.fail e);
  (match H.parse_decl (Some "a.com;methods=post;no_redirects") with
   | Ok d ->
     Alcotest.(check (option (list string))) "methods" (Some [ "post" ]) d.methods;
     Alcotest.(check bool) "flag" true d.no_redirects
   | Error e -> Alcotest.fail e);
  (match H.parse_decl (Some "a.com") with
   | Ok d -> Alcotest.(check (option (list string))) "any method" None d.methods
   | Error e -> Alcotest.fail e);
  List.iter
    (fun s ->
       match H.parse_decl (Some s) with
       | Ok _ -> Alcotest.failf "%S should be rejected" s
       | Error _ -> ())
    [ "a.com;methods=trace"; "a.com;methods=gett"; "a.com;methods=";
      "a.com;methods=get;methods=post"; "a.com;no_redirects;no_redirects" ]

let test_permits_method () =
  let ds = decls [ "api.com;methods=get"; "api.com;methods=post"; "w.com" ] in
  let p h m = H.permits_method ds ~host:h ~port:443 ~meth:m in
  Alcotest.(check bool) "get" true (p "api.com" "get");
  Alcotest.(check bool) "post (second declaration)" true (p "api.com" "post");
  Alcotest.(check bool) "delete" false (p "api.com" "delete");
  Alcotest.(check bool) "unlisted methods on w.com" true (p "w.com" "delete");
  Alcotest.(check bool) "uncovered host" false (p "x.com" "get");
  Alcotest.(check bool) "module-wide get only" false
    (H.permits_method (decls [ ";methods=get" ]) ~host:"any.test" ~port:443 ~meth:"post");
  Alcotest.(check bool) "unscoped module" true
    (H.permits_method [] ~host:"any.test" ~port:443 ~meth:"post")

let test_permits_raw () =
  Alcotest.(check bool) "method-scoped host refuses raw" false
    (H.permits_raw (decls [ "api.com;methods=get" ]) ~host:"api.com" ~port:443);
  Alcotest.(check bool) "method-free declaration allows raw" true
    (H.permits_raw (decls [ "api.com;methods=get"; "api.com" ]) ~host:"api.com" ~port:443)

let test_spec_roundtrip_methods () =
  List.iter
    (fun l ->
       let ds = decls l in
       Alcotest.(check bool) (String.concat "|" l) true
         (H.decode_spec (H.encode_spec ds) = ds))
    [ [ "a.com;methods=get,head" ]; [ "a.com;methods=post;no_redirects"; ";methods=get" ] ]

let test_methods_syntax () =
  accepts "methods option" {|needs IO.NetConnect("api.example.com", methods(get, head))|};
  accepts "methods then no_redirects"
    {|needs IO.NetConnect("api.example.com", methods(post), no_redirects)|};
  accepts "no_redirects then methods"
    {|needs IO.NetConnect("api.example.com", no_redirects, methods(post))|};
  accepts "module-wide methods" {|needs IO.NetConnect(methods(get))|};
  rejects_with "unknown verb" ~expect:"trace" {|needs IO.NetConnect("a.com", methods(trace))|};
  rejects_with "methods twice" ~expect:"twice"
    {|needs IO.NetConnect("a.com", methods(get), methods(post))|};
  rejects_with "methods on a filesystem cap" ~expect:"no options"
    {|needs IO.FileRead("/etc", methods(get))|}

let test_methods_format_roundtrip () =
  let src =
    "mod F do\n  needs IO.NetConnect(\"a.com\", methods(get, head), no_redirects), IO.NetConnect(methods(post))\nend\n"
  in
  let out = March_format.Format.format_source ~filename:"f.march" src in
  List.iter
    (fun want ->
       match Str.search_forward (Str.regexp_string want) out 0 with
       | _ -> ()
       | exception Not_found -> Alcotest.failf "formatted output lacks %S:\n%s" want out)
    [ {|IO.NetConnect("a.com", methods(get, head), no_redirects)|};
      {|IO.NetConnect(methods(post))|} ]

(* ── Path prefixes (path-scopes plan, Task 1) ──────────────────────── *)

let test_path_pattern_parses () =
  let p = pat "api.x.test/v1/weather/" in
  Alcotest.(check string) "host" "api.x.test" p.host;
  Alcotest.(check (option (list string))) "path" (Some [ "v1"; "weather" ]) p.path;
  let q = pat "api.x.test:8443/v1/" in
  Alcotest.(check (option int)) "port kept" (Some 8443) q.port;
  Alcotest.(check (option (list string))) "path" (Some [ "v1" ]) q.path;
  Alcotest.(check (option (list string))) "host-only has no path" None (pat "api.x.test").path

let test_path_pattern_rejects () =
  List.iter
    (fun s ->
       match H.parse_pattern s with
       | Ok _ -> Alcotest.failf "pattern %S should be rejected" s
       | Error _ -> ())
    [ "a.test/v1/../x/"; "a.test/v1//x/"; "a.test/%2e/"; "a.test/v1?x"; "a.test/v1#x";
      "a.test/a\\b/"; "a.test/./x/" ]

let test_boundary_and_query () =
  let w p = H.path_within ~prefix:[ "v1"; "weather" ] p in
  List.iter (fun p -> Alcotest.(check bool) p true (w p))
    [ "/v1/weather"; "/v1/weather/"; "/v1/weather/today"; "/v1/weather?x=1" ];
  List.iter (fun p -> Alcotest.(check bool) p false (w p))
    [ "/v1/weatherman"; "/v1"; "/" ]

let test_refused_encodings () =
  List.iter (fun p -> Alcotest.(check bool) p false (H.path_ok p))
    [ "/v1/./x"; "/v1/../x"; "/v1//x"; "/v1/%2e%2e/x"; "/v1/%2E/x"; "/v1%2fx"; "/v1%2Fx";
      "/v1%5cx"; "/v1\\x" ];
  List.iter (fun p -> Alcotest.(check bool) p true (H.path_ok p))
    [ "/v1/weather/today"; "/v1/a%20b"; "/" ]

let test_two_prefixes () =
  let ds = decls [ "a.test/v1/x/"; "a.test/v2/" ] in
  let ok p = H.permits_request ds ~host:"a.test" ~port:443 ~meth:None ~path:(Some p) in
  Alcotest.(check bool) "v1/x/1" true (ok "/v1/x/1");
  Alcotest.(check bool) "v2/y" true (ok "/v2/y");
  Alcotest.(check bool) "v1/y" false (ok "/v1/y");
  Alcotest.(check bool) "unknown path under path scopes" false
    (H.permits_request ds ~host:"a.test" ~port:443 ~meth:None ~path:None);
  Alcotest.(check bool) "unknown path, host-level only" true
    (H.permits_host_ignoring_path ds ~host:"a.test" ~port:443 ~meth:None);
  Alcotest.(check bool) "bad path refused even if under the prefix" false
    (ok "/v2/../admin")

let test_raw_refused_under_path () =
  Alcotest.(check bool) "raw to a path-scoped host" false
    (H.permits_raw (decls [ "a.test/v1/" ]) ~host:"a.test" ~port:443)

let test_spec_roundtrip_paths () =
  List.iter
    (fun l ->
       let ds = decls l in
       Alcotest.(check bool) (String.concat "|" l) true (H.decode_spec (H.encode_spec ds) = ds))
    [ [ "a.test/v1/weather/" ]; [ "a.test:8443/v1/;methods=get;no_redirects"; "b.test" ] ]

let test_url_path_of_literal () =
  Alcotest.(check (option string)) "whole URL" (Some "/v1/w")
    (H.url_path_of_literal ~prefix:false "https://a.test/v1/w?q=1");
  Alcotest.(check (option string)) "whole URL, no path" (Some "/")
    (H.url_path_of_literal ~prefix:false "https://a.test");
  Alcotest.(check (option string)) "prefix" (Some "/v1/")
    (H.url_path_of_literal ~prefix:true "https://a.test/v1/");
  Alcotest.(check (option string)) "prefix cut at last slash" (Some "/v1/")
    (H.url_path_of_literal ~prefix:true "https://a.test/v1/wea")

let test_path_scope_declared () =
  accepts "path scope" {|needs IO.NetConnect("api.x.test/v1/weather/", methods(get))|};
  rejects_with "dot-dot path scope" ~expect:".."
    {|needs IO.NetConnect("api.x.test/v1/../admin/")|};
  (* The hint shows the path form, so the fix is obvious. *)
  rejects_with "hint names the path form" ~expect:"api.example.com/v1/"
    {|needs IO.NetConnect("api.x.test/v1/../admin/")|}

(* Review fixes (path scopes): a path is judged only when every byte is a
   plain path character; CR/LF/space would smuggle a second request. *)
let test_path_ok_allowlist () =
  List.iter (fun p -> Alcotest.(check bool) (String.escaped p) false (H.path_ok p))
    [ "/v1/x HTTP/1.1\r\nHost: h\r\n\r\nDELETE /admin"; "/v1/x y"; "/v1/x\000"; "/v1/x\r";
      "/v1/..;/admin"; "/v1/a;b"; "/v1/%252e%252e/x"; "/v1/x#/../../admin"; "/v1/x?y";
      "/v1/\xc3\xa9"; "/v1/%2"; "/v1/%zz"; "/v1/%00"; "/v1/%0d%0a" ];
  List.iter (fun p -> Alcotest.(check bool) p true (H.path_ok p))
    [ "/v1/a%20b"; "/v1/a:b@c"; "/v1/a,b"; "/v1/weather/today"; "/" ]

let test_literal_path_keeps_fragment () =
  (* As Http.parse_url does: the path runs to `?`, and a `#` stays in it. *)
  Alcotest.(check (option string)) "fragment kept" (Some "/v1/w#frag")
    (H.url_path_of_literal ~prefix:false "https://a.test/v1/w#frag");
  Alcotest.(check (option string)) "query cut" (Some "/v1/w")
    (H.url_path_of_literal ~prefix:false "https://a.test/v1/w?q=1#f")

let path_tests =
  [
    Alcotest.test_case "path_ok allowlist" `Quick test_path_ok_allowlist;
    Alcotest.test_case "literal path keeps fragment" `Quick test_literal_path_keeps_fragment;
    Alcotest.test_case "path scope declared" `Quick test_path_scope_declared;
    Alcotest.test_case "path pattern parses" `Quick test_path_pattern_parses;
    Alcotest.test_case "path pattern rejects" `Quick test_path_pattern_rejects;
    Alcotest.test_case "boundary and query" `Quick test_boundary_and_query;
    Alcotest.test_case "refused encodings" `Quick test_refused_encodings;
    Alcotest.test_case "two prefixes" `Quick test_two_prefixes;
    Alcotest.test_case "raw refused under path" `Quick test_raw_refused_under_path;
    Alcotest.test_case "spec roundtrip with paths" `Quick test_spec_roundtrip_paths;
    Alcotest.test_case "url path of literal" `Quick test_url_path_of_literal;
  ]

(* ── Several names and string-valued options (ocap p2b, Task 11) ────── *)

let needs_scope src =
  let m = Test_helpers.parse_module (Printf.sprintf "mod S do\n  %s\nend\n" src) in
  List.concat_map
    (function
      | March_ast.Ast.DNeeds (caps, _) -> List.map snd caps
      | _ -> [])
    m.March_ast.Ast.mod_decls

let test_parse_multi_name_scope () =
  Alcotest.(check (list (option string))) "two names"
    [ Some "a;name=b" ] (needs_scope {|needs IO.Mut("a", "b")|});
  Alcotest.(check (list (option string))) "three names then an option"
    [ Some "a;name=b;name=c;no_redirects" ]
    (needs_scope {|needs IO.Mut("a", "b", "c", no_redirects)|})

let test_parse_string_option_scope () =
  Alcotest.(check (list (option string))) "string-argument option alone"
    [ Some ";prefix=w." ] (needs_scope {|needs IO.Registry(prefix("w."))|});
  Alcotest.(check (list (option string))) "name and string-argument option"
    [ Some "logger;prefix=worker." ]
    (needs_scope {|needs IO.Registry("logger", prefix("worker."))|})

let test_parse_methods_scope_unchanged () =
  Alcotest.(check (list (option string))) "methods"
    [ Some "h;methods=get" ] (needs_scope {|needs IO.NetConnect("h", methods(get))|});
  Alcotest.(check (list (option string))) "methods list"
    [ Some "h;methods=get,post;no_redirects" ]
    (needs_scope {|needs IO.NetConnect("h", methods(get, post), no_redirects)|})

let test_scope_forms_format_roundtrip () =
  let src =
    "mod F do\n  needs IO.Mut(\"a\", \"b\"), IO.Registry(\"l\", prefix(\"w.\")), IO.Registry(prefix(\"x.\"))\nend\n"
  in
  let out = March_format.Format.format_source ~filename:"f.march" src in
  List.iter
    (fun want ->
       match Str.search_forward (Str.regexp_string want) out 0 with
       | _ -> ()
       | exception Not_found -> Alcotest.failf "formatted output lacks %S:\n%s" want out)
    [ {|IO.Mut("a", "b")|}; {|IO.Registry("l", prefix("w."))|}; {|IO.Registry(prefix("x."))|} ]

(* R16 (Task 12): the scope forms print back to themselves, escapes included,
   and a second format changes nothing. *)
let test_scope_forms_format_idempotent () =
  let src =
    "mod F do\n  needs IO.Mut(\"a\\\"q\", \"b\\\\s\"), IO.Registry(\"l\", prefix(\"w.\\\"\")), \
     IO.Registry(prefix(\"x.\")), IO.NetConnect(\"h\", methods(get, post), no_redirects)\nend\n"
  in
  let fmt = March_format.Format.format_source ~filename:"f.march" in
  let once = fmt src in
  Alcotest.(check string) "format is idempotent" once (fmt once);
  let scopes =
    List.concat_map
      (function
        | March_ast.Ast.DNeeds (caps, _) -> List.map snd caps
        | _ -> [])
      (Test_helpers.parse_module once).March_ast.Ast.mod_decls
  in
  Alcotest.(check (list (option string))) "scopes survive formatting"
    [ Some "a\"q;name=b\\s"; Some "l;prefix=w.\""; Some ";prefix=x.";
      Some "h;methods=get,post;no_redirects" ]
    scopes

let method_tests =
  path_tests @ [
    Alcotest.test_case "scope forms format idempotent" `Quick test_scope_forms_format_idempotent;
    Alcotest.test_case "parse multi-name scope" `Quick test_parse_multi_name_scope;
    Alcotest.test_case "parse string-option scope" `Quick test_parse_string_option_scope;
    Alcotest.test_case "parse methods scope unchanged" `Quick test_parse_methods_scope_unchanged;
    Alcotest.test_case "scope forms format roundtrip" `Quick test_scope_forms_format_roundtrip;
    Alcotest.test_case "methods syntax" `Quick test_methods_syntax;
    Alcotest.test_case "methods format roundtrip" `Quick test_methods_format_roundtrip;
    Alcotest.test_case "methods decl" `Quick test_methods_decl;
    Alcotest.test_case "permits method" `Quick test_permits_method;
    Alcotest.test_case "permits raw" `Quick test_permits_raw;
    Alcotest.test_case "spec roundtrip with methods" `Quick test_spec_roundtrip_methods;
  ]

let tests =
  method_tests @ decl_tests @ dest_tests @ [
    Alcotest.test_case "patterns rejected" `Quick test_parse_rejects;
    Alcotest.test_case "patterns accepted" `Quick test_parse_accepts;
    Alcotest.test_case "wildcard" `Quick test_wildcard;
    Alcotest.test_case "case and trailing dot" `Quick test_case_and_trailing_dot;
    Alcotest.test_case "ports" `Quick test_ports;
    Alcotest.test_case "default ports" `Quick test_default_ports;
    Alcotest.test_case "authority prefix" `Quick test_authority_prefix;
    Alcotest.test_case "confusing authority" `Quick
      test_whole_url_rejects_confusing_authority;
    Alcotest.test_case "no_redirects decl" `Quick test_no_redirects_decl;
    Alcotest.test_case "forbids redirects" `Quick test_forbids_redirects;
    Alcotest.test_case "spec roundtrip" `Quick test_spec_roundtrip;
    Alcotest.test_case "permits union" `Quick test_permits_union;
  ]
