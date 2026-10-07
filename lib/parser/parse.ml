module Errors = March_errors.Errors

type 'a result_ = ('a, Errors.diagnostic list) result

let code_parse_error  = March_errors.Code.parse_error
let code_syntax_error = March_errors.Code.syntax_error
let code_lex_error    = March_errors.Code.lex_error

(* The one place a token filter is instantiated.  Its state lives in the
   closure, so every parse gets a fresh one. *)
let tokens () = Token_filter.make Lexer.token

let lexbuf_of_string ?(filename = "") src =
  let lexbuf = Lexing.from_string src in
  if filename <> "" then
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  lexbuf

let module_of_lexbuf lexbuf     = Parser.module_ (tokens ()) lexbuf
let repl_input_of_lexbuf lexbuf = Parser.repl_input (tokens ()) lexbuf
let expr_of_lexbuf lexbuf       = Parser.expr_eof (tokens ()) lexbuf
let ty_of_lexbuf lexbuf         = Parser.ty_eof (tokens ()) lexbuf
let repl_sequence_of_lexbuf lexbuf = Parser.repl_sequence (tokens ()) lexbuf

let run ?(filename = "") ?(stuck = "I got stuck here:") entry src =
  let lexbuf = lexbuf_of_string ~filename src in
  match entry lexbuf with
  | v -> Ok v
  | exception Errors.ParseError (msg, hint, pos) ->
    Error [ { (Errors.parse_error_diagnostic_at ~filename ?hint ~src ~msg pos)
              with code = code_parse_error } ]
  | exception Parser.Error ->
    Error [ { (Errors.parse_error_diagnostic ~filename ~msg:stuck lexbuf)
              with code = code_syntax_error } ]
  | exception Lexer.Lexer_error msg ->
    (* The lexer's sub-rules leave no usable lexeme; one caret where it
       stopped. *)
    Error [ { (Errors.parse_error_diagnostic_at ~filename ~len:1 ~msg
                 (Lexing.lexeme_start_p lexbuf))
              with code = code_lex_error } ]

let module_ ?filename ?stuck src    = run ?filename ?stuck module_of_lexbuf src
let repl_input ?filename ?stuck src = run ?filename ?stuck repl_input_of_lexbuf src
let expr ?filename ?stuck src       = run ?filename ?stuck expr_of_lexbuf src
let repl_sequence ?filename ?stuck src =
  run ?filename ?stuck repl_sequence_of_lexbuf src
