let () =
  let check path =
    let src =
      let ic = open_in path in
      let n  = in_channel_length ic in
      let buf = Bytes.create n in
      really_input ic buf 0 n;
      close_in ic;
      Bytes.to_string buf
    in
    let formatted = March_format.Format.format_source ~filename:path src in
    let lexbuf = Lexing.from_string formatted in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = "<formatted>" };
    (try
       ignore (March_parser.Parser.module_ March_lexer.Lexer.token lexbuf);
       Printf.printf "%s: PARSES OK\n%!" path
     with March_parser.Parser.Error ->
       let pos = lexbuf.Lexing.lex_curr_p in
       Printf.printf "%s: PARSE ERROR at line %d col %d\n%!" path
         pos.Lexing.pos_lnum (pos.Lexing.pos_cnum - pos.Lexing.pos_bol);
       let lines = String.split_on_char '\n' formatted in
       let line_n = pos.Lexing.pos_lnum in
       List.iteri (fun i l ->
         if i >= line_n - 3 && i <= line_n + 2 then
           Printf.printf "%4d: %s\n" (i+1) l
       ) lines)
  in
  List.iter check [
    "stdlib/string.march";
    "stdlib/prelude.march";
  ]
