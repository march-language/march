(* Host scopes, end to end through `march --compile`
   (lib/tir/net_scope.ml; specs/2026-11-09-host-scoped-network-capabilities-design.md).

   The check runs on the compile path only, like the capability ceiling, so
   every case here compiles a whole program.  Each fixture is one file with
   nested modules: `A` is the host-scoped module under test, `C` an unscoped
   helper, and the entry module holds the grant. *)

let compiler_exe =
  Filename.concat (Filename.dirname Sys.executable_name) "../bin/main.exe"

let run_compiler ?(flags = "--compile") src_text =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf "compiler not found at %s" compiler_exe;
  let src = Filename.temp_file "net_scope" ".march" in
  let oc = open_out src in
  output_string oc src_text;
  close_out oc;
  let out = Filename.temp_file "net_scope" ".out" in
  let bin = Filename.temp_file "net_scope" ".bin" in
  let rc =
    Sys.command
      (Printf.sprintf "%s %s -o %s %s > %s 2>&1 </dev/null"
         (Filename.quote compiler_exe) flags (Filename.quote bin)
         (Filename.quote src) (Filename.quote out))
  in
  let ic = open_in out in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  List.iter (fun f -> try Sys.remove f with Sys_error _ -> ()) [ src; out; bin ];
  (rc, s)

let contains s sub =
  match Str.search_forward (Str.regexp_string sub) s 0 with
  | _ -> true
  | exception Not_found -> false

let accepts name src =
  let rc, out = run_compiler src in
  if rc <> 0 then Alcotest.failf "%s should compile but did not:\n%s" name out

let rejects name ~code ?(mentions = []) src =
  let rc, out = run_compiler src in
  if rc = 0 then Alcotest.failf "%s should be rejected but compiled" name;
  List.iter
    (fun want ->
       if not (contains out want) then
         Alcotest.failf "%s: expected %S in the output:\n%s" name want out)
    (("[" ^ code ^ "]") :: mentions)

(* A program: [a_needs] and [a_body] make module A, [extra] adds modules,
   [main_call] is what main prints. *)
let program ?(a_needs = {|needs IO.NetConnect("example.com")|}) ?(extra = "")
    ?(main_call = "A.go(\"q\")") a_body =
  Printf.sprintf
    {|mod Main do
  needs IO.NetConnect, IO.Console

  mod A do
    %s
%s
  end
%s
  fn main(_n : Cap(IO.NetConnect), _c : Cap(IO.Console)) do
    println(%s)
  end
end
|}
    a_needs a_body extra main_call

let simple_get url =
  Printf.sprintf
    {|match HttpTransport.simple_get(%s) do
        Ok(_) -> "ok"
        Err(_) -> "err"
      end|}
    url

let fn_go body =
  Printf.sprintf "    fn go(p : String) : String do\n      %s\n    end" body

let test_own_host_ok () =
  accepts "literal own host" (program (fn_go (simple_get {|"https://example.com/x"|})))

let test_other_host_rejected () =
  rejects "literal other host" ~code:"cap_host_scope" ~mentions:[ "foo.com" ]
    (program (fn_go (simple_get {|"https://foo.com/x"|})))

let test_param_unproven () =
  rejects "URL from a parameter" ~code:"cap_host_unproven"
    (program (fn_go (simple_get "p")))

let test_prefix_needs_slash () =
  rejects "prefix without slash" ~code:"cap_host_unproven"
    (program (fn_go (simple_get {|"https://example.com" ++ p|})));
  accepts "prefix with slash" (program (fn_go (simple_get {|"https://example.com/" ++ p|})));
  accepts "let-bound prefix"
    (program
       (fn_go
          ("let base = \"https://example.com/\"\n      " ^ simple_get "base ++ p")))

let test_query_prefix_unproven () =
  rejects "prefix ending at ?" ~code:"cap_host_unproven"
    (program (fn_go (simple_get {|"https://example.com?" ++ p|})))

let test_handle_unproven () =
  rejects "fd operation" ~code:"cap_host_unproven"
    (program
       (fn_go
          {|match tcp_send_all(3, p) do
        Ok(_) -> "ok"
        Err(_) -> "err"
      end|}))

let test_tls_connect_unproven () =
  rejects "tls_connect with an SNI name" ~code:"cap_host_unproven"
    (program
       (fn_go
          {|match tls_connect(3, 4, "example.com") do
        Ok(_) -> "ok"
        Err(_) -> "err"
      end|}))

let c_module body =
  Printf.sprintf "\n  mod C do\n    needs IO.NetConnect\n%s\n  end\n" body

let test_through_unannotated_unproven () =
  rejects "through an unannotated helper" ~code:"cap_host_unproven"
    ~mentions:[ "C.fetch" ]
    (program
       ~extra:(c_module ("    fn fetch(url : String) : String do\n      " ^ simple_get "url" ^ "\n    end"))
       (fn_go {|C.fetch("https://example.com/x")|}))

let annotated_fetch =
  c_module
    ("    @[net_dest(url)]\n    fn fetch(url : String) : String do\n      "
    ^ simple_get "url" ^ "\n    end")

let test_through_annotated () =
  accepts "annotated helper, own host"
    (program ~extra:annotated_fetch (fn_go {|C.fetch("https://example.com/x")|}));
  rejects "annotated helper, other host" ~code:"cap_host_scope" ~mentions:[ "foo.com" ]
    (program ~extra:annotated_fetch (fn_go {|C.fetch("https://foo.com/x")|}))

let test_lying_annotation_rejected () =
  rejects "annotation whose body rewrites the URL" ~code:"cap_host_annotation"
    (program
       ~extra:
         (c_module
            ("    @[net_dest(url)]\n    fn fetch(url : String) : String do\n      "
            ^ simple_get {|"https://foo.com/" ++ url|} ^ "\n    end"))
       (fn_go {|C.fetch("https://example.com/x")|}))

let test_fixed_callee_checked () =
  rejects "fixed-destination helper outside the scope" ~code:"cap_host_scope"
    ~mentions:[ "foo.com" ]
    (program
       ~extra:(c_module ("    fn ping() : String do\n      " ^ simple_get {|"https://foo.com/ping"|} ^ "\n    end"))
       (fn_go "C.ping()"))

let test_unused_import_is_free () =
  accepts "scoped module that never calls the network helper"
    (program
       ~extra:(c_module ("    fn fetch(url : String) : String do\n      " ^ simple_get "url" ^ "\n    end\n    fn pure(x : Int) : Int do x + 1 end"))
       (fn_go {|int_to_string(C.pure(1))|}))

let test_lambda_in_scoped_module () =
  rejects "lambda written in A, run by a stdlib callback" ~code:"cap_host_scope"
    ~mentions:[ "foo.com" ]
    (program
       (fn_go
          ("let f = fn u -> " ^ simple_get {|"https://foo.com/x"|} ^ "\n      int_to_string(List.length(List.map([p], f)))")))

let test_closure_from_unscoped_main_ok () =
  accepts "closure built in unscoped main, called in A"
    (program
       ~main_call:{|A.run(fn path -> match HttpTransport.simple_get("https://anything.test" ++ path) do
      Ok(_) -> "ok"
      Err(_) -> "err"
    end)|}
       "    fn run(fetch : String -> String) : String do\n      fetch(\"/x\")\n    end")

let test_unscoped_module_unchecked () =
  accepts "unscoped module, URL from a parameter"
    (program ~a_needs:"needs IO.NetConnect" (fn_go (simple_get "p")))

let test_no_redirects_literal_rejected () =
  rejects "with_redirects in a no_redirects module" ~code:"cap_host_scope"
    ~mentions:[ "no_redirects" ]
    (program
       ~a_needs:{|needs IO.NetConnect("example.com", no_redirects)|}
       (fn_go
          {|let c = HttpClient.with_redirects(HttpClient.new_client(), 5)
      match HttpClient.get(c, "https://example.com/x") do
        Ok(_) -> "ok"
        Err(_) -> "err"
      end|}))

let test_two_modules_two_hosts () =
  let two a_url b_url =
    Printf.sprintf
      {|mod Main do
  needs IO.NetConnect, IO.Console
  mod A do
    needs IO.NetConnect("example.com")
    fn go() : String do
      %s
    end
  end
  mod B do
    needs IO.NetConnect("foo.com")
    fn go() : String do
      %s
    end
  end
  fn main(_n : Cap(IO.NetConnect), _c : Cap(IO.Console)) do
    println(A.go() ++ B.go())
  end
end
|}
      (simple_get a_url) (simple_get b_url)
  in
  accepts "each reaches its own host"
    (two {|"https://example.com/"|} {|"https://foo.com/"|});
  rejects "A reaches B's host" ~code:"cap_host_scope" ~mentions:[ "foo.com" ]
    (two {|"https://foo.com/"|} {|"https://foo.com/"|});
  rejects "B reaches A's host" ~code:"cap_host_scope" ~mentions:[ "example.com" ]
    (two {|"https://example.com/"|} {|"https://example.com/"|})

(* ── The rewrite and the diagnostic (Task 6) ───────────────────────── *)

let client_get_program a_needs =
  program ~a_needs
    (fn_go
       {|match HttpClient.get(HttpClient.new_client(), "https://example.com/" ++ p) do
        Ok(_) -> "ok"
        Err(_) -> "err"
      end|})

let test_rewrite_targets_twin () =
  let rc, out =
    run_compiler ~flags:"--dump-tir" (client_get_program {|needs IO.NetConnect("example.com")|})
  in
  if rc <> 0 then Alcotest.failf "dump-tir failed:\n%s" out;
  if not (contains out "HttpClient.get_scoped") then
    Alcotest.failf "scoped call not rewritten to the twin:\n%s"
      (String.sub out 0 (min 2000 (String.length out)));
  if not (contains out {|"example.com"|}) then
    Alcotest.fail "the scope literal is not passed to the twin"

let test_unscoped_not_rewritten () =
  let rc, out = run_compiler ~flags:"--dump-tir" (client_get_program "needs IO.NetConnect") in
  if rc <> 0 then Alcotest.failf "dump-tir failed:\n%s" out;
  (* A.go is inlined by the time --dump-tir prints, so look for what the
     rewrite adds: the module's scope as an exact string literal.  The
     program's own URL literal is "https://example.com/", never this. *)
  if contains out {|"example.com"|} then
    Alcotest.fail "an unscoped module's call was given a scope"

let test_diagnostic_shape () =
  let rc, out =
    run_compiler
      (program
         (fn_go
            ("let a = " ^ simple_get {|"https://foo.com/x"|} ^ "\n      "
            ^ simple_get "p")))
  in
  if rc = 0 then Alcotest.fail "should be rejected";
  let count sub =
    let re = Str.regexp_string sub in
    let rec go i n =
      match Str.search_forward re out i with
      | j -> go (j + 1) (n + 1)
      | exception Not_found -> n
    in
    go 0 0
  in
  Alcotest.(check int) "one diagnostic block for the module" 1 (count "-- CAPABILITY --");
  List.iter
    (fun want -> if not (contains out want) then Alcotest.failf "missing %S:\n%s" want out)
    [ "[cap_host_scope]"; "foo.com"; "Also in module `A`"; "cap_host_unproven" ]

let tests =
  [
    Alcotest.test_case "rewrite targets the twin" `Slow test_rewrite_targets_twin;
    Alcotest.test_case "unscoped not rewritten" `Slow test_unscoped_not_rewritten;
    Alcotest.test_case "diagnostic shape" `Slow test_diagnostic_shape;
    Alcotest.test_case "own host ok" `Slow test_own_host_ok;
    Alcotest.test_case "other host rejected" `Slow test_other_host_rejected;
    Alcotest.test_case "parameter unproven" `Slow test_param_unproven;
    Alcotest.test_case "prefix needs a slash" `Slow test_prefix_needs_slash;
    Alcotest.test_case "query prefix unproven" `Slow test_query_prefix_unproven;
    Alcotest.test_case "handle unproven" `Slow test_handle_unproven;
    Alcotest.test_case "tls_connect unproven" `Slow test_tls_connect_unproven;
    Alcotest.test_case "through unannotated unproven" `Slow test_through_unannotated_unproven;
    Alcotest.test_case "through annotated" `Slow test_through_annotated;
    Alcotest.test_case "lying annotation rejected" `Slow test_lying_annotation_rejected;
    Alcotest.test_case "fixed callee checked" `Slow test_fixed_callee_checked;
    Alcotest.test_case "unused import is free" `Slow test_unused_import_is_free;
    Alcotest.test_case "lambda in scoped module" `Slow test_lambda_in_scoped_module;
    Alcotest.test_case "closure from unscoped main ok" `Slow test_closure_from_unscoped_main_ok;
    Alcotest.test_case "unscoped module unchecked" `Slow test_unscoped_module_unchecked;
    Alcotest.test_case "no_redirects literal rejected" `Slow test_no_redirects_literal_rejected;
    Alcotest.test_case "two modules, two hosts" `Slow test_two_modules_two_hosts;
  ]
