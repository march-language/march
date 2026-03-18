(** March lexer — ocamllex specification. *)
{
open March_parser.Parser

exception Lexer_error of string

let keyword_table = Hashtbl.create 32
let () =
  List.iter
    (fun (kw, tok) -> Hashtbl.add keyword_table kw tok)
    [
      ("fn", FN);
      ("let", LET);
      ("do", DO);
      ("end", END);
      ("if", IF);
      ("then", THEN);
      ("else", ELSE);
      ("match", MATCH);
      ("with", WITH);
      ("when", WHEN);
      ("type", TYPE);
      ("mod", MOD);
      ("actor", ACTOR);
      ("on", ON);
      ("send", SEND);
      ("spawn", SPAWN);
      ("state", STATE);
      ("init", INIT);
      ("respond", RESPOND);
      ("protocol", PROTOCOL);
      ("loop", LOOP);
      ("true", BOOL true);
      ("false", BOOL false);
      ("linear", LINEAR);
      ("affine", AFFINE);
      ("pub", PUB);
      ("interface", INTERFACE);
      ("impl", IMPL);
      ("sig", SIG);
      ("extern", EXTERN);
      ("unsafe", UNSAFE);
      ("as", AS);
    ]
}

let whitespace = [' ' '\t']+
let newline = '\r' | '\n' | "\r\n"
let digit = ['0'-'9']
let alpha = ['a'-'z' 'A'-'Z' '_']
let ident = alpha (alpha | digit | '\'')*
let atom_name = ['a'-'z'] (alpha | digit)*

rule token = parse
  | whitespace    { token lexbuf }
  | newline       { Lexing.new_line lexbuf; token lexbuf }
  | "--"          { line_comment lexbuf }
  | "{-"          { block_comment 0 lexbuf }
  | digit+ '.' digit+ as f { FLOAT (float_of_string f) }
  | digit+ as n   { INT (int_of_string n) }
  | '"'           { read_string (Buffer.create 16) lexbuf }
  | ':' (atom_name as a) { ATOM a }
  | '('           { LPAREN }
  | ')'           { RPAREN }
  | '{'           { LBRACE }
  | '}'           { RBRACE }
  | '['           { LBRACKET }
  | ']'           { RBRACKET }
  | "->"          { ARROW }
  | "|>"          { PIPE_ARROW }
  | '='           { EQUALS }
  | ':'           { COLON }
  | ','           { COMMA }
  | '|'           { PIPE }
  | '.'           { DOT }
  | "++"          { PLUSPLUS }
  | '+'           { PLUS }
  | '-'           { MINUS }
  | '*'           { STAR }
  | '/'           { SLASH }
  | '%'           { PERCENT }
  | '<'           { LT }
  | '>'           { GT }
  | "=="          { EQEQ }
  | "!="          { NEQ }
  | "<="          { LEQ }
  | ">="          { GEQ }
  | "&&"          { AND }
  | "||"          { OR }
  | '!'           { BANG }
  | '_'           { UNDERSCORE }
  | '?'           { QUESTION }
  | ident as id   {
      match Hashtbl.find_opt keyword_table id with
      | Some tok -> tok
      | None ->
        if Char.uppercase_ascii id.[0] = id.[0]
        then UPPER_IDENT id
        else LOWER_IDENT id
    }
  | eof           { EOF }
  | _ as c        { raise (Lexer_error (Printf.sprintf "Unexpected character: %c" c)) }

and line_comment = parse
  | newline       { Lexing.new_line lexbuf; token lexbuf }
  | eof           { EOF }
  | _             { line_comment lexbuf }

and block_comment depth = parse
  | "{-"          { block_comment (depth + 1) lexbuf }
  | "-}"          { if depth = 0 then token lexbuf else block_comment (depth - 1) lexbuf }
  | newline       { Lexing.new_line lexbuf; block_comment depth lexbuf }
  | eof           { raise (Lexer_error "Unterminated block comment") }
  | _             { block_comment depth lexbuf }

and read_string buf = parse
  | '"'           { STRING (Buffer.contents buf) }
  | "\\n"         { Buffer.add_char buf '\n'; read_string buf lexbuf }
  | "\\t"         { Buffer.add_char buf '\t'; read_string buf lexbuf }
  | "\\\\"        { Buffer.add_char buf '\\'; read_string buf lexbuf }
  | "\\\""        { Buffer.add_char buf '"'; read_string buf lexbuf }
  | eof           { raise (Lexer_error "Unterminated string literal") }
  | _ as c        { Buffer.add_char buf c; read_string buf lexbuf }
