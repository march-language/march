open Notty

let attr_keyword = A.(st bold ++ fg magenta)
let attr_type    = A.(fg cyan)
let attr_string  = A.(fg green)
let attr_number  = A.(fg yellow)
let attr_atom    = A.(fg blue)
let attr_op      = A.(st bold)
let attr_comment = A.(fg (rgb_888 ~r:105 ~g:121 ~b:137))
let attr_default = A.empty

(** Find the byte position of the first [--] comment marker not inside a
    double-quoted string.  Handles [\\] escapes.  Returns [None] if no
    comment is present on this line. *)
let find_comment_start src =
  let n = String.length src in
  let i = ref 0 in
  let in_string = ref false in
  let found = ref None in
  while !i < n && !found = None do
    if !in_string then begin
      if src.[!i] = '\\' && !i + 1 < n then
        i := !i + 2   (* skip escaped char *)
      else begin
        if src.[!i] = '"' then in_string := false;
        incr i
      end
    end else begin
      if src.[!i] = '"' then begin
        in_string := true; incr i
      end else if src.[!i] = '-' && !i + 1 < n && src.[!i + 1] = '-' then
        found := Some !i
      else
        incr i
    end
  done;
  !found

let attr_of_token tok =
  let open March_parser.Parser in
  match tok with
  | FN | LET | DO | END | IF | THEN | ELSE | MATCH | WITH | WHEN
  | TYPE | MOD | ACTOR | ON | SEND | SPAWN | STATE | INIT
  | PROTOCOL | LOOP | LINEAR | AFFINE | INTERFACE | IMPL | SIG
  | EXTERN | AS | USE | BOOL _ -> attr_keyword
  | INT _ | FLOAT _ -> attr_number
  | STRING _ | INTERP_START _ | INTERP_MID _ | INTERP_END _ -> attr_string
  | ATOM _ -> attr_atom
  | UPPER_IDENT _ -> attr_type
  | PLUS | MINUS | STAR | SLASH | PERCENT
  | PLUSDOT | MINUSDOT | STARDOT | SLASHDOT
  | PLUSPLUS | PIPE_ARROW | ARROW
  | EQUALS | LT | GT | EQEQ | NEQ | LEQ | GEQ
  | AND | OR | BANG -> attr_op
  | _ -> attr_default

(** Render a string that contains no control characters as an image. *)
let render_plain attr s =
  if s = "" then I.empty
  else I.string attr s

(** Split [s] on '\n' and build an image, composing lines vertically. *)
let render_with_newlines attr s =
  let lines = String.split_on_char '\n' s in
  let imgs = List.map (render_plain attr) lines in
  (* join with vertical composition, inserting an empty row per newline *)
  match imgs with
  | [] -> I.empty
  | first :: rest ->
    List.fold_left (fun acc img -> I.(acc <-> img)) first rest

let highlight_tokens src =
  if src = "" then I.empty
  else
    let lexbuf = Lexing.from_string src in
    let src_len = String.length src in
    let images = ref [] in
    let pos = ref 0 in
    let running = ref true in
    while !running do
      let tok_start = lexbuf.Lexing.lex_curr_p.Lexing.pos_cnum in
      (match
        (try
          let tok = March_lexer.Lexer.token lexbuf in
          let tok_end = lexbuf.Lexing.lex_curr_p.Lexing.pos_cnum in
          Some (tok, tok_start, tok_end)
        with _ -> None)
      with
      | None ->
        (* Lex error: emit remainder in default color and stop *)
        if !pos < src_len then begin
          let rest = String.sub src !pos (src_len - !pos) in
          images := render_with_newlines attr_default rest :: !images
        end;
        running := false
      | Some (March_parser.Parser.EOF, _, _) ->
        running := false
      | Some (tok, start, stop) ->
        (* Emit gap (whitespace/newlines) between last pos and token start *)
        if start > !pos then begin
          let gap = String.sub src !pos (start - !pos) in
          images := render_with_newlines attr_default gap :: !images
        end;
        (* Emit the token text *)
        let len = stop - start in
        if len > 0 then begin
          let lexeme = String.sub src start len in
          let attr = attr_of_token tok in
          images := render_with_newlines attr lexeme :: !images
        end;
        pos := stop)
    done;
    I.hcat (List.rev !images)

let highlight src =
  if src = "" then I.empty
  else
    match find_comment_start src with
    | Some pos ->
      let code_part    = String.sub src 0 pos in
      let comment_part = String.sub src pos (String.length src - pos) in
      I.(highlight_tokens code_part <|> string attr_comment comment_part)
    | None ->
      highlight_tokens src
