(* Drive the CLI logic directly (no process spawn), asserting on emitted JSON. *)

let has_sub s sub =
  let ls = String.length s and lsub = String.length sub in
  let rec go i = i + lsub <= ls && (String.sub s i lsub = sub || go (i + 1)) in
  go 0

let run args ~src =
  March_lsp_lib.Query_cli.run_to_string args ~src_override:(Some src)

let test_cli_diagnostics_json () =
  (* 'true' where Int is declared -> a type error -> a diagnostic. *)
  let src = "mod M do\n  fn f() : Int do true end\nend\n" in
  let out = run ["query"; "diagnostics"; "t.march"] ~src in
  Alcotest.(check bool) "json has diagnostics array"
    true (has_sub out "\"diagnostics\"");
  Alcotest.(check bool) "json reports a non-empty message"
    true (has_sub out "\"message\"")

let test_cli_hover_json () =
  let src = "mod M do\n  fn f() : Int do 41 end\nend\n" in
  let out = run ["query"; "hover"; "t.march"; "--line"; "1"; "--col"; "5"] ~src in
  Alcotest.(check bool) "json has a type field" true (has_sub out "\"type\"")

let test_cli_unknown_query_is_error () =
  let out = run ["query"; "bogus"; "t.march"] ~src:"mod M do\nend\n" in
  Alcotest.(check bool) "unknown query yields an error object"
    true (has_sub out "\"error\"")

let () =
  Alcotest.run "query_cli"
    [ "cli",
      [ Alcotest.test_case "diagnostics" `Quick test_cli_diagnostics_json;
        Alcotest.test_case "hover" `Quick test_cli_hover_json;
        Alcotest.test_case "unknown query" `Quick test_cli_unknown_query_is_error ] ]
