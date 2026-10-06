(** The one parse entry point.

    Everything that turns March source text into an AST goes through here.
    This module owns the lexer -> {!Token_filter} -> {!Parser} pipeline (one
    filter instance per parse) and the conversion of the three ways a parse
    can fail into a {!March_errors.Errors.diagnostic}:

    - [Errors.ParseError (msg, hint, pos)], raised by the grammar's `error`
      productions, the token filter and the lexer's literal checks. The span
      starts at [pos], the position the production chose; the hint becomes a
      note. Code {!code_parse_error}.
    - [Parser.Error], menhir's own failure, which carries no position. The
      span is the lookahead token. Code {!code_syntax_error}.
    - [Lexer.Lexer_error msg]. The span is where the lexer stopped. Code
      {!code_lex_error}.

    Nothing outside this module should call [Token_filter.make], or match on
    [Parser.Error] / [Lexer.Lexer_error]. *)

type 'a result_ = ('a, March_errors.Errors.diagnostic list) result

val code_parse_error  : string
val code_syntax_error : string
val code_lex_error    : string

(** {1 Source text in, AST or diagnostics out}

    [filename] goes into every span (and so into each diagnostic's
    [span.file]); it defaults to [""]. [stuck] is the message used for
    [Parser.Error]; it defaults to ["I got stuck here:"]. Never raises on a
    syntax error. *)

val module_    : ?filename:string -> ?stuck:string -> string -> March_ast.Ast.module_ result_
val repl_input : ?filename:string -> ?stuck:string -> string -> March_ast.Ast.repl_input result_
val expr       : ?filename:string -> ?stuck:string -> string -> March_ast.Ast.expr result_
val repl_sequence : ?filename:string -> ?stuck:string -> string -> March_ast.Ast.repl_input list result_

(** {1 Raising forms}

    The same pipeline over a caller-owned lexbuf, letting the parser's
    exception escape unchanged. For callers that treat every failure alike
    ([with _ -> None]) and for tests that assert on the raw exception. Code
    that reports a syntax error to a person should use the result forms. *)

val module_of_lexbuf     : Lexing.lexbuf -> March_ast.Ast.module_
val repl_input_of_lexbuf : Lexing.lexbuf -> March_ast.Ast.repl_input
val expr_of_lexbuf       : Lexing.lexbuf -> March_ast.Ast.expr
val ty_of_lexbuf         : Lexing.lexbuf -> March_ast.Ast.ty
val repl_sequence_of_lexbuf : Lexing.lexbuf -> March_ast.Ast.repl_input list

(** A lexbuf over [src] whose positions carry [filename]. *)
val lexbuf_of_string : ?filename:string -> string -> Lexing.lexbuf

(** A fresh filtered token stream (the parser's view of the tokens). Only for
    tests of the token filter itself. *)
val tokens : unit -> Lexing.lexbuf -> Parser.token
