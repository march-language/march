(* The lexer's source is lexer.mll, next to this file.  It is built inside
   the march_parser library (lib/parser/dune has the reason) and re-exported
   here, so `March_lexer.Lexer.token` and `March_lexer.Lexer.Lexer_error` are
   the very same values as `March_parser.Lexer`'s.

   To parse March source, call [March_parser.Parse] rather than wiring this
   lexer to the parser by hand. *)
include March_parser.Lexer
