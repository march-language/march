(** March lexer — ocamllex specification. *)
{
open March_parser.Parser

exception Lexer_error of string

(** Brace depth inside a string interpolation expression `${ ... }`.
    0 means we are NOT inside an interpolation.  When `${` is seen in a
    string literal, depth is set to 1; each `{` increments it; `}` that
    would bring it below 1 closes the interpolation. *)
let interp_depth = ref 0
(* Whether the current interpolation is inside a triple-quoted string. *)
let interp_triple = ref false

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
      ("protocol", PROTOCOL);
      ("loop", LOOP);
      ("true", BOOL true);
      ("false", BOOL false);
      ("linear", LINEAR);
      ("affine", AFFINE);
      ("interface", INTERFACE);
      ("impl", IMPL);
      ("sig", SIG);
      ("extern", EXTERN);
      ("as", AS);
      ("use", USE);
      ("needs", NEEDS);
      ("dbg", DBG);
      ("doc", DOC);
      ("supervise", SUPERVISE);
      ("strategy", STRATEGY);
      ("max_restarts", MAX_RESTARTS);
      ("within", WITHIN);
      ("one_for_one", ONE_FOR_ONE);
      ("one_for_all", ONE_FOR_ALL);
      ("rest_for_one", REST_FOR_ONE);
      ("requires", REQUIRES);
      ("import", IMPORT);
      ("alias", ALIAS);
      ("only", ONLY);
      ("except", EXCEPT);
      ("derive", DERIVE);
      ("for", FOR);
      ("in", IN);
      ("opaque", OPAQUE);
      ("pfn", PFN);
      ("ptype", PTYPE);
      ("app", APP);
      ("on_start", ON_START);
      ("on_stop",  ON_STOP);
      ("choose", CHOOSE);
      ("by",     BY);
      ("offer",  OFFER);
      ("test",      TEST);
      ("describe",  DESCRIBE);
      ("assert",    ASSERT);
      ("setup",     SETUP);
      ("setup_all", SETUP_ALL);
    ]
}

let whitespace = [' ' '\t']+
let newline = '\r' | '\n' | "\r\n"
let digit = ['0'-'9']
let alpha = ['a'-'z' 'A'-'Z' '_']
let ident = alpha (alpha | digit | '\'')*
let atom_name = ['a'-'z'] (alpha | digit)*
let hex_digit = ['0'-'9' 'a'-'f' 'A'-'F']

rule token = parse
  | whitespace    { token lexbuf }
  | newline       { Lexing.new_line lexbuf; NL }
  | "--"          { line_comment lexbuf }
  | "{-"          { block_comment 0 lexbuf }
  | digit+ '.' digit+ as f { FLOAT (float_of_string f) }
  | digit+ as n   { INT (int_of_string n) }
  | "\"\"\""      { read_triple_string (Buffer.create 64) lexbuf }
  | '"'           { read_string (Buffer.create 16) lexbuf }
  | ':' (atom_name as a) { ATOM a }
  | '('           { LPAREN }
  | ')'           { RPAREN }
  | '{'           { if !interp_depth > 0 then incr interp_depth; LBRACE }
  | '}'           {
      if !interp_depth > 0 then begin
        decr interp_depth;
        if !interp_depth = 0 then
          (* Closing brace of interpolation — resume reading the string *)
          if !interp_triple then
            read_triple_string_interp (Buffer.create 64) lexbuf
          else
            read_string_interp (Buffer.create 16) lexbuf
        else
          RBRACE
      end else
        RBRACE
    }
  | '['           { LBRACKET }
  | ']'           { RBRACKET }
  | '@'           { AT }
  | "->"          { ARROW }
  | "<-"          { GETS }
  | "|>"          { PIPE_ARROW }
  | "\\\\"        { DSLASH }
  | '='           { EQUALS }
  | ':'           { COLON }
  | ','           { COMMA }
  | '|'           { PIPE }
  | '.'           { DOT }
  | "++"          { PLUSPLUS }
  | "+."          { PLUSDOT }
  | "-."          { MINUSDOT }
  | "*."          { STARDOT }
  | "/."          { SLASHDOT }
  | '+'           { PLUS }
  | '-'           { MINUS }
  | '*'           { STAR }
  | '/'           { SLASH }
  | "%{"          { RECORD_LBRACE }
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
  | '~' (['A'-'Z'] as c) { SIGIL_PREFIX (String.make 1 c) }
  | '~' (['a'-'z'] ['a'-'z' '0'-'9' '_']* as name) { SIGIL_PREFIX name }
  | ident as id   {
      match Hashtbl.find_opt keyword_table id with
      | Some tok -> tok
      | None ->
        if id.[0] >= 'A' && id.[0] <= 'Z'
        then UPPER_IDENT id
        else LOWER_IDENT id
    }
  | eof           { EOF }
  | _ as c        { raise (Lexer_error (Printf.sprintf "Unexpected character: %c" c)) }

and line_comment = parse
  | newline       { Lexing.new_line lexbuf; NL }
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
  | "${"          {
      (* Begin a string interpolation: emit INTERP_START carrying the prefix *)
      interp_depth := 1;
      interp_triple := false;
      INTERP_START (Buffer.contents buf)
    }
  | "\\n"         { Buffer.add_char buf '\n'; read_string buf lexbuf }
  | "\\t"         { Buffer.add_char buf '\t'; read_string buf lexbuf }
  | "\\r"         { Buffer.add_char buf '\r'; read_string buf lexbuf }
  | "\\b"         { Buffer.add_char buf '\b'; read_string buf lexbuf }
  | "\\f"         { Buffer.add_char buf '\012'; read_string buf lexbuf }
  | "\\0"         { Buffer.add_char buf '\000'; read_string buf lexbuf }
  | "\\\\"        { Buffer.add_char buf '\\'; read_string buf lexbuf }
  | "\\\""        { Buffer.add_char buf '"'; read_string buf lexbuf }
  | "\\$"         { Buffer.add_char buf '$'; read_string buf lexbuf }
  | "\\x" (hex_digit hex_digit as hex)
                  { Buffer.add_char buf (Char.chr (int_of_string ("0x" ^ hex)));
                    read_string buf lexbuf }
  | '\\' (_ as c) { raise (Lexer_error (Printf.sprintf "Invalid escape sequence: \\%c" c)) }
  | eof           { raise (Lexer_error "Unterminated string literal") }
  | _ as c        { Buffer.add_char buf c; read_string buf lexbuf }

(** Resume reading a string literal after the closing `}` of an interpolation. *)
(** Triple-quoted string: """..."""  — interpolation and newlines preserved. *)
and read_triple_string buf = parse
  | "\"\"\""      { STRING (Buffer.contents buf) }
  | "${"          {
      interp_depth := 1;
      interp_triple := true;
      INTERP_START (Buffer.contents buf)
    }
  | "\\$"         { Buffer.add_char buf '$'; read_triple_string buf lexbuf }
  | newline       { Lexing.new_line lexbuf; Buffer.add_char buf '\n'; read_triple_string buf lexbuf }
  | eof           { raise (Lexer_error "Unterminated triple-quoted string") }
  | _ as c        { Buffer.add_char buf c; read_triple_string buf lexbuf }

(** Resume reading a triple-quoted string after the closing `}` of an interpolation. *)
and read_triple_string_interp buf = parse
  | "\"\"\""      { INTERP_END (Buffer.contents buf) }
  | "${"          {
      interp_depth := 1;
      interp_triple := true;
      INTERP_MID (Buffer.contents buf)
    }
  | "\\$"         { Buffer.add_char buf '$'; read_triple_string_interp buf lexbuf }
  | newline       { Lexing.new_line lexbuf; Buffer.add_char buf '\n'; read_triple_string_interp buf lexbuf }
  | eof           { raise (Lexer_error "Unterminated triple-quoted string interpolation") }
  | _ as c        { Buffer.add_char buf c; read_triple_string_interp buf lexbuf }

and read_string_interp buf = parse
  | '"'           { INTERP_END (Buffer.contents buf) }
  | "${"          {
      (* Another interpolation segment *)
      interp_depth := 1;
      interp_triple := false;
      INTERP_MID (Buffer.contents buf)
    }
  | "\\n"         { Buffer.add_char buf '\n'; read_string_interp buf lexbuf }
  | "\\t"         { Buffer.add_char buf '\t'; read_string_interp buf lexbuf }
  | "\\r"         { Buffer.add_char buf '\r'; read_string_interp buf lexbuf }
  | "\\b"         { Buffer.add_char buf '\b'; read_string_interp buf lexbuf }
  | "\\f"         { Buffer.add_char buf '\012'; read_string_interp buf lexbuf }
  | "\\0"         { Buffer.add_char buf '\000'; read_string_interp buf lexbuf }
  | "\\\\"        { Buffer.add_char buf '\\'; read_string_interp buf lexbuf }
  | "\\\""        { Buffer.add_char buf '"'; read_string_interp buf lexbuf }
  | "\\$"         { Buffer.add_char buf '$'; read_string_interp buf lexbuf }
  | "\\x" (hex_digit hex_digit as hex)
                  { Buffer.add_char buf (Char.chr (int_of_string ("0x" ^ hex)));
                    read_string_interp buf lexbuf }
  | '\\' (_ as c) { raise (Lexer_error (Printf.sprintf "Invalid escape sequence: \\%c" c)) }
  | eof           { raise (Lexer_error "Unterminated string interpolation") }
  | _ as c        { Buffer.add_char buf c; read_string_interp buf lexbuf }
