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
  (* 1-based: line 2 is the fn body; col 6 is on the `f` identifier. *)
  let out = run ["query"; "hover"; "t.march"; "--line"; "2"; "--col"; "6"] ~src in
  Alcotest.(check bool) "json has a type field" true (has_sub out "\"type\"")

let test_cli_type_json () =
  let src = "mod M do\n  fn f() : Int do 41 end\nend\n" in
  (* 1-based position on `f`; the dedicated `type` feature returns just a type. *)
  let out = run ["query"; "type"; "t.march"; "--line"; "2"; "--col"; "6"] ~src in
  Alcotest.(check bool) "json has a type field" true (has_sub out "\"type\"")

let test_cli_symbols_json () =
  let src = "mod M do\n  fn f() : Int do 41 end\n  fn g() : Int do 7 end\nend\n" in
  let out = run ["query"; "symbols"; "t.march"] ~src in
  Alcotest.(check bool) "json has a symbols array" true (has_sub out "\"symbols\"");
  Alcotest.(check bool) "lists function f" true (has_sub out "\"f\"");
  Alcotest.(check bool) "lists function g" true (has_sub out "\"g\"");
  Alcotest.(check bool) "reports a kind" true (has_sub out "\"kind\"")

(* Extract the first `"character":N` integer that appears AFTER the first
   `"start"` key in [json]. Returns None if absent. *)
let first_start_character json =
  match
    (let ls = String.length json in
     let rec find_from i needle =
       let ln = String.length needle in
       if i + ln > ls then None
       else if String.sub json i ln = needle then Some i
       else find_from (i + 1) needle
     in
     match find_from 0 "\"start\"" with
     | None -> None
     | Some s ->
       match find_from s "\"character\":" with
       | None -> None
       | Some c ->
         let j = ref (c + String.length "\"character\":") in
         let b = Buffer.create 4 in
         while !j < ls && json.[!j] >= '0' && json.[!j] <= '9' do
           Buffer.add_char b json.[!j]; incr j
         done;
         (try Some (int_of_string (Buffer.contents b)) with _ -> None))
  with x -> x

(* A line with leading multi-byte chars shifts byte columns past UTF-16
   columns. The diagnostic on `true` (a Bool/Int mismatch) must report the
   UTF-16 column, proving Query.diagnostics remaps byte->UTF-16. Each `é` is
   2 bytes but 1 UTF-16 unit; three of them put byte col 3 ahead of UTF-16. *)
let test_cli_diagnostics_utf16_columns () =
  let src = "mod M do\n  fn f() : Int do \"\xc3\xa9\xc3\xa9\xc3\xa9\" ++ true end\nend\n" in
  let out = run ["query"; "diagnostics"; "t.march"] ~src in
  Alcotest.(check bool) "has diagnostics" true (has_sub out "\"diagnostics\"");
  (* Line: `  fn f() : Int do "ééé" ++ true end`
     The first diagnostic (return-type mismatch) spans `"ééé" ++ true`, starting
     at the opening quote. The three `é` precede it but each is 2 bytes / 1
     UTF-16 unit, so the byte start col is 25 while the UTF-16 start col is 22.
     Asserting 22 proves Query.diagnostics remapped byte->UTF-16 (a raw byte
     column would be 25). *)
  (match first_start_character out with
   | None -> Alcotest.fail "expected a diagnostic with a start character"
   | Some col ->
     Alcotest.(check int)
       "first diagnostic start char is the UTF-16 column (22), not byte col 25"
       22 col)

let test_cli_unknown_query_is_error () =
  let out = run ["query"; "bogus"; "t.march"] ~src:"mod M do\nend\n" in
  Alcotest.(check bool) "unknown query yields an error object"
    true (has_sub out "\"error\"")

let test_cli_format () =
  (* An under-indented, single-line body gets reindented; formatting is stable. *)
  let messy = "mod M do\nfn f() : Int do 1 end\nend\n" in
  let out = run ["query"; "format"; "t.march"] ~src:messy in
  Alcotest.(check bool) "formatting reindents the source"
    true (out <> messy && has_sub out "  fn f");
  let out2 = run ["query"; "format"; "t.march"] ~src:out in
  Alcotest.(check string) "formatting is idempotent" out out2

let () =
  Alcotest.run "query_cli"
    [ "cli",
      [ Alcotest.test_case "diagnostics" `Quick test_cli_diagnostics_json;
        Alcotest.test_case "hover" `Quick test_cli_hover_json;
        Alcotest.test_case "type" `Quick test_cli_type_json;
        Alcotest.test_case "symbols" `Quick test_cli_symbols_json;
        Alcotest.test_case "diagnostics UTF-16 columns" `Quick test_cli_diagnostics_utf16_columns;
        Alcotest.test_case "unknown query" `Quick test_cli_unknown_query_is_error;
        Alcotest.test_case "format" `Quick test_cli_format ] ]
