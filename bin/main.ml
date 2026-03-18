(** March compiler entry point. *)

let dump_tir = ref false

(* ------------------------------------------------------------------ *)
(* Multi-line REPL input                                              *)
(* ------------------------------------------------------------------ *)

(** Count exact whole-word occurrences of [tok] in [buf].
    Splits on non-identifier characters so "done" does not count as "do". *)
let count_token tok buf =
  let words = Str.split (Str.regexp "[^a-zA-Z0-9_']") buf in
  List.length (List.filter (( = ) tok) words)

(** Net depth of open do/end blocks in [buf].
    Positive means we are inside an unclosed block.
    Known limitation: `do` or `end` inside string literals are miscounted;
    use a blank line to force-submit in that case. *)
let do_end_depth buf =
  count_token "do" buf - count_token "end" buf

(** Last non-blank line in [buf], trimmed. *)
let last_non_blank_line buf =
  let lines = String.split_on_char '\n' buf in
  match List.rev (List.filter (fun l -> String.trim l <> "") lines) with
  | []    -> ""
  | l :: _ -> String.trim l

(** True if the last non-blank line ends with the token "with". *)
let ends_with_with buf =
  let l = last_non_blank_line buf in
  let words = String.split_on_char ' ' (String.trim l) in
  match List.rev words with
  | "with" :: _ -> true
  | _            -> false

(** True if the last non-blank line starts with '|' (match arm continuation). *)
let starts_with_pipe buf =
  let l = last_non_blank_line buf in
  String.length l > 0 && l.[0] = '|'

(** Read one complete REPL input, possibly spanning multiple lines.
    Returns [None] on EOF with empty buffer (exit signal),
    [Some src] when the input is judged complete. *)
let read_repl_input () =
  let buf        = Buffer.create 64 in
  let first_line = ref true in
  let result     = ref None in
  while !result = None do
    Printf.printf "%s%!" (if !first_line then "march> " else "     | ");
    first_line := false;
    (match (try Some (input_line stdin) with End_of_file -> None) with
     | None ->
       (* EOF *)
       let s = Buffer.contents buf in
       result := Some (if s = "" then None else Some s)
     | Some line ->
       if Buffer.length buf > 0 then Buffer.add_char buf '\n';
       Buffer.add_string buf line;
       let contents = Buffer.contents buf in
       if String.trim line = "" then
         (* Blank line: force submit (escape hatch) *)
         result := Some (Some contents)
       else if do_end_depth contents > 0 then
         ()   (* still inside an open block — keep accumulating *)
       else if ends_with_with contents then
         ()   (* match expression continues — keep accumulating *)
       else if starts_with_pipe contents then
         ()   (* match arm — keep accumulating *)
       else
         result := Some (Some contents))
  done;
  match !result with
  | Some r -> r
  | None   -> assert false

(* ------------------------------------------------------------------ *)
(* REPL                                                                *)
(* ------------------------------------------------------------------ *)

(** Print a diagnostic in REPL style (no file/line prefix — interactive context). *)
let print_repl_diag (d : March_errors.Errors.diagnostic) =
  let sev = match d.severity with
    | March_errors.Errors.Error   -> "error"
    | March_errors.Errors.Warning -> "warning"
    | March_errors.Errors.Hint    -> "hint"
  in
  Printf.eprintf "%s: %s\n%!" sev d.message;
  List.iter (fun note ->
      Printf.eprintf "note: %s\n%!" note
    ) d.notes

let repl () =
  Printf.printf "March REPL — :quit to exit, :env to list bindings\n%!";
  let env = ref March_eval.Eval.base_env in
  let type_map = Hashtbl.create 64 in
  (* base_env (typecheck.ml) pre-populates built-in types, ctors,
     and vars (Int, String, Bool, println, etc.) — unlike bare make_env. *)
  let tc_env = ref
    (March_typecheck.Typecheck.base_env
       (March_errors.Errors.create ()) type_map) in
  let running = ref true in
  while !running do
    (try
       (match read_repl_input () with
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
             let input_ctx = March_errors.Errors.create () in
             let input_tc  = { !tc_env with errors = input_ctx } in
             let new_tc    = March_typecheck.Typecheck.check_decl input_tc d' in
             List.iter print_repl_diag (March_errors.Errors.sorted input_ctx);
             if not (March_errors.Errors.has_errors input_ctx) then begin
               tc_env := { new_tc with errors = March_errors.Errors.create () };
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
             end
           | Some (March_ast.Ast.ReplExpr e) ->
             let e' = March_desugar.Desugar.desugar_expr e in
             let input_ctx = March_errors.Errors.create () in
             let input_tc  = { !tc_env with errors = input_ctx } in
             let inferred  = March_typecheck.Typecheck.infer_expr input_tc e' in
             let ty_str    = March_typecheck.Typecheck.pp_ty
               (March_typecheck.Typecheck.repr inferred) in
             List.iter print_repl_diag (March_errors.Errors.sorted input_ctx);
             if March_errors.Errors.has_errors input_ctx then
               Printf.eprintf "note: inferred type was %s\n%!" ty_str
             else begin
               (try
                  let v = March_eval.Eval.eval_expr !env e' in
                  Printf.printf "= %s\n%!" (March_eval.Eval.value_to_string v)
                with
                | March_eval.Eval.Eval_error msg ->
                  Printf.eprintf "runtime error: %s\n%!" msg
                | March_eval.Eval.Match_failure msg ->
                  Printf.eprintf "match failure: %s\n%!" msg)
             end))
     with
     | March_lexer.Lexer.Lexer_error msg ->
       Printf.eprintf "lexer error: %s\n%!" msg
     | March_eval.Eval.Eval_error msg ->
       Printf.eprintf "runtime error: %s\n%!" msg
     | March_eval.Eval.Match_failure msg ->
       Printf.eprintf "match failure: %s\n%!" msg
     | exn ->
       Printf.eprintf "internal error: %s\n%!" (Printexc.to_string exn))
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
