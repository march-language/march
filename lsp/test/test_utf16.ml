module U = March_lsp_lib.Utf16

(* "let x = 1\nlet é = 2\n😀 after" — é is 2 UTF-8 bytes / 1 UTF-16 unit;
   😀 is 4 UTF-8 bytes / 2 UTF-16 units (surrogate pair). *)
let src = "let x = 1\nlet \xc3\xa9 = 2\n\xf0\x9f\x98\x80 after"

let test_line_index () =
  let d = U.build src in
  (* line 0 starts at byte 0; line 1 starts after the first '\n' (byte 10). *)
  Alcotest.(check int) "line0 start" 0 (U.line_start d 0);
  Alcotest.(check int) "line1 start" 10 (U.line_start d 1)

let test_utf16_after_2byte_char () =
  let d = U.build src in
  (* On line 1, "let é = 2": the '=' is at UTF-16 column 6 (l,e,t,space,é,space)
     but byte column 7 (é occupies 2 bytes). Conversion must reconcile them. *)
  let byte_col = U.lsp_char_to_byte_col d ~line:1 ~utf16_char:6 in
  Alcotest.(check int) "utf16 6 -> byte 7" 7 byte_col;
  let utf16 = U.byte_col_to_lsp_char d ~line:1 ~byte_col:7 in
  Alcotest.(check int) "byte 7 -> utf16 6" 6 utf16

let test_astral_char_two_units () =
  let d = U.build src in
  (* On line 2, "😀 after": the space after 😀 is UTF-16 column 2 (surrogate
     pair = 2 units) but byte column 4. *)
  let byte_col = U.lsp_char_to_byte_col d ~line:2 ~utf16_char:2 in
  Alcotest.(check int) "astral utf16 2 -> byte 4" 4 byte_col

let test_ascii_identity () =
  let d = U.build src in
  Alcotest.(check int) "ascii utf16==byte" 4
    (U.lsp_char_to_byte_col d ~line:0 ~utf16_char:4)

(* Outbound: a byte-column range (as produced internally) is remapped to
   UTF-16 at the boundary. On line 1 "let é = 2", the '=' is at byte col 7
   but UTF-16 col 6 (é is 2 bytes / 1 unit). *)
let test_remap_range_to_utf16 () =
  let open Linol_lsp.Lsp.Types in
  let d = U.build src in
  let r = Range.create
    ~start:(Position.create ~line:1 ~character:7)
    ~end_:(Position.create ~line:1 ~character:8) in
  let r2 = March_lsp_lib.Position.remap_range d r in
  Alcotest.(check int) "start byte 7 -> utf16 6" 6 r2.start.character;
  Alcotest.(check int) "end byte 8 -> utf16 7" 7 r2.end_.character

let () =
  Alcotest.run "utf16"
    [ "conv",
      [ Alcotest.test_case "line index" `Quick test_line_index;
        Alcotest.test_case "2-byte char" `Quick test_utf16_after_2byte_char;
        Alcotest.test_case "astral char" `Quick test_astral_char_two_units;
        Alcotest.test_case "ascii identity" `Quick test_ascii_identity;
        Alcotest.test_case "remap range outbound" `Quick test_remap_range_to_utf16 ] ]
