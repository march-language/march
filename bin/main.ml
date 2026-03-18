(** March compiler entry point. *)

let dump_tir = ref false

(* ------------------------------------------------------------------ *)
(* REPL                                                                *)
(* ------------------------------------------------------------------ *)

let repl () =
  Printf.printf "March REPL — :quit to exit, :env to list bindings\n%!";
  let env = ref March_eval.Eval.base_env in
  let running = ref true in
  while !running do
    Printf.printf "march> %!";
    let line =
      try Some (input_line stdin)
      with End_of_file -> None
    in
    match line with
    | None -> running := false
    | Some ":quit" | Some ":q" -> running := false
    | Some ":env" ->
      List.iter (fun (k, _) -> Printf.printf "  %s\n" k) !env
    | Some src when String.trim src = "" -> ()
    | Some src ->
      let lexbuf = Lexing.from_string src in
      (match
         (try Some (March_parser.Parser.repl_input March_lexer.Lexer.token lexbuf)
          with March_parser.Parser.Error ->
            let pos = Lexing.lexeme_start_p lexbuf in
            Printf.eprintf "parse error at col %d\n%!"
              (pos.Lexing.pos_cnum - pos.Lexing.pos_bol);
            None)
       with
       | None -> ()
       | Some March_ast.Ast.ReplEOF -> ()
       | Some (March_ast.Ast.ReplDecl d) ->
         let d' = March_desugar.Desugar.desugar_decl d in
         (try
            env := March_eval.Eval.eval_decl !env d';
            (* Print the name(s) that were just bound *)
            (match d' with
             | March_ast.Ast.DFn (def, _) ->
               Printf.printf "val %s = <fn>\n%!" def.fn_name.txt
             | March_ast.Ast.DLet (b, _) ->
               (match b.bind_pat with
                | March_ast.Ast.PatVar n ->
                  let v = List.assoc n.txt !env in
                  Printf.printf "val %s = %s\n%!" n.txt
                    (March_eval.Eval.value_to_string v)
                | _ -> Printf.printf "val _ = ...\n%!")
             | _ -> ())
          with
          | March_eval.Eval.Eval_error msg ->
            Printf.eprintf "runtime error: %s\n%!" msg
          | March_eval.Eval.Match_failure msg ->
            Printf.eprintf "match failure: %s\n%!" msg)
       | Some (March_ast.Ast.ReplExpr e) ->
         let e' = March_desugar.Desugar.desugar_expr e in
         (try
            let v = March_eval.Eval.eval_expr !env e' in
            Printf.printf "= %s\n%!" (March_eval.Eval.value_to_string v)
          with
          | March_eval.Eval.Eval_error msg ->
            Printf.eprintf "runtime error: %s\n%!" msg
          | March_eval.Eval.Match_failure msg ->
            Printf.eprintf "match failure: %s\n%!" msg))
  done

(* ------------------------------------------------------------------ *)
(* File compiler                                                       *)
(* ------------------------------------------------------------------ *)

let compile filename =
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
  let (errors, type_map) = March_typecheck.Typecheck.check_module desugared in
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
        d.message;
      List.iter (fun note ->
          Printf.printf "note: %s\n" note
        ) d.notes
    ) diags;
  if March_errors.Errors.has_errors errors then exit 1
  else if !dump_tir then begin
    let tir = March_tir.Lower.lower_module ~type_map desugared in
    let tir = March_tir.Mono.monomorphize tir in
    let tir = March_tir.Defun.defunctionalize tir in
    let tir = March_tir.Perceus.perceus tir in
    List.iter (fun td ->
        Printf.printf "%s\n\n" (March_tir.Pp.string_of_type_def td)
      ) tir.tm_types;
    List.iter (fun fn ->
        Printf.printf "%s\n\n" (March_tir.Pp.string_of_fn_def fn)
      ) tir.tm_fns
  end
  else begin
    try March_eval.Eval.run_module desugared
    with
    | March_eval.Eval.Eval_error msg ->
      Printf.eprintf "%s: runtime error: %s\n" filename msg; exit 1
    | March_eval.Eval.Match_failure msg ->
      Printf.eprintf "%s: match failure: %s\n" filename msg; exit 1
  end

let () =
  let files = ref [] in
  let specs = [
    ("--dump-tir", Arg.Set dump_tir, " Print TIR instead of evaluating")
  ] in
  Arg.parse specs (fun f -> files := f :: !files) "Usage: march [options] [file.march]";
  match !files with
  | []  -> repl ()
  | [f] -> compile f
  | _   -> Printf.eprintf "Usage: march [options] [file.march]\n"; exit 1
