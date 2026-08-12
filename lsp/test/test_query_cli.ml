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

(* Extract every `"character":N` that follows a `"start"` key, in order. *)
let start_characters json =
  let ls = String.length json in
  let rec find_from i needle =
    let ln = String.length needle in
    if i + ln > ls then None
    else if String.sub json i ln = needle then Some i
    else find_from (i + 1) needle
  in
  let rec go i acc =
    match find_from i "\"start\"" with
    | None -> List.rev acc
    | Some s ->
      (match find_from s "\"character\":" with
       | None -> List.rev acc
       | Some c ->
         let j = ref (c + String.length "\"character\":") in
         let b = Buffer.create 4 in
         while !j < ls && json.[!j] >= '0' && json.[!j] <= '9' do
           Buffer.add_char b json.[!j]; incr j
         done;
         let v = try Some (int_of_string (Buffer.contents b)) with _ -> None in
         go !j (match v with Some v -> v :: acc | None -> acc))
  in
  go 0 []

(* A line with leading multi-byte chars shifts byte columns past UTF-16
   columns. The diagnostic on `true` (a Bool/Int mismatch) must report the
   UTF-16 column, proving Query.diagnostics remaps byte->UTF-16. Each `é` is
   2 bytes but 1 UTF-16 unit; three of them put byte col 3 ahead of UTF-16. *)
let test_cli_diagnostics_utf16_columns () =
  let src = "mod M do\n  fn f() : Int do \"\xc3\xa9\xc3\xa9\xc3\xa9\" ++ true end\nend\n" in
  let out = run ["query"; "diagnostics"; "t.march"] ~src in
  Alcotest.(check bool) "has diagnostics" true (has_sub out "\"diagnostics\"");
  (* Two diagnostics land on line 2:

       #1 return-type mismatch, spanning the whole `"..." ++ true` expression
          from the OPENING quote -> byte col 18. Nothing multi-byte precedes
          it, so its UTF-16 col is also 18: it cannot witness remapping.
       #2 the `Bool` operand, starting at `true` -> byte col 30. The three
          multi-byte chars DO precede it (2 bytes / 1 UTF-16 unit each), so
          its UTF-16 col is 27.

     #2 is therefore the one that proves Query.diagnostics remaps byte->UTF-16:
     a raw byte column would report 30.

     This assertion used to read 22 off diagnostic #1, which only worked
     because a string literal's span started at its CLOSING quote (byte 25 ->
     UTF-16 22). That was a compiler bug; now that spans cover the whole
     literal, #1 begins before the multi-byte characters and distinguishes
     nothing. *)
  match start_characters out with
  | first :: second :: _ ->
    Alcotest.(check int)
      "diagnostic #1 starts at the opening quote (byte 18 = UTF-16 18)" 18 first;
    Alcotest.(check int)
      "diagnostic #2 start char is the UTF-16 column (27), not byte col 30"
      27 second
  | _ -> Alcotest.fail "expected two diagnostics with start characters"

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
