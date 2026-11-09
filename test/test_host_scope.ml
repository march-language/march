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
    [ "https://a.com"; "a.com/x"; "u@a.com"; "a..com"; "*"; "a.*.com";
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

let tests =
  [
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
