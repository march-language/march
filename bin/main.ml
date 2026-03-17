(** March compiler entry point. *)

let () =
  match Sys.argv with
  | [| _ |] ->
    Printf.eprintf "Usage: march <file.march>\n";
    exit 1
  | [| _; filename |] ->
    let src =
      try
        let ic = open_in filename in
        let n = in_channel_length ic in
        let buf = Bytes.create n in
        really_input ic buf 0 n;
        close_in ic;
        Bytes.to_string buf
      with Sys_error msg ->
        Printf.eprintf "march: %s\n" msg;
        exit 1
    in
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
    (* Parse *)
    let module_ast =
      try March_parser.Parser.module_ March_lexer.Lexer.token lexbuf
      with March_parser.Parser.Error ->
        let pos = Lexing.lexeme_start_p lexbuf in
        Printf.eprintf "%s:%d:%d: parse error\n"
          pos.Lexing.pos_fname
          pos.Lexing.pos_lnum
          (pos.Lexing.pos_cnum - pos.Lexing.pos_bol);
        exit 1
    in
    (* Desugar *)
    let desugared = March_desugar.Desugar.desugar_module module_ast in
    (* Typecheck *)
    let errors = March_typecheck.Typecheck.check_module desugared in
    (* Print diagnostics sorted by position *)
    let diags = March_errors.Errors.sorted errors in
    List.iter (fun (d : March_errors.Errors.diagnostic) ->
        let sev = match d.severity with
          | March_errors.Errors.Error   -> "error"
          | March_errors.Errors.Warning -> "warning"
          | March_errors.Errors.Hint    -> "hint"
        in
        Printf.printf "%s:%d:%d: %s: %s\n"
          d.span.March_ast.Ast.file
          d.span.March_ast.Ast.start_line
          d.span.March_ast.Ast.start_col
          sev
          d.message
      ) diags;
    if March_errors.Errors.has_errors errors then exit 1
    else begin
      try March_eval.Eval.run_module desugared
      with
      | March_eval.Eval.Eval_error msg ->
        Printf.eprintf "%s: runtime error: %s\n" filename msg; exit 1
      | March_eval.Eval.Match_failure msg ->
        Printf.eprintf "%s: match failure: %s\n" filename msg; exit 1
    end
  | _ ->
    Printf.eprintf "Usage: march <file.march>\n";
    exit 1
