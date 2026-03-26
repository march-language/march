(** Contextual newline filter for the March parser.

    The lexer emits [NL] for every newline. This filter sits between
    the lexer and the parser, passing [NL] tokens through only when
    inside a [match ... do ... end] body at the outermost nesting
    level. Everywhere else, [NL] tokens are silently consumed.

    Inside match bodies:
    - NL after ARROW is suppressed (arm body continuation, including
      multiple NLs from comment lines between -> and the body)
    - Consecutive NLs are collapsed to a single NL
    - NL immediately before END is suppressed
    This gives the parser a clean stream: [DO NL branch NL branch END]. *)

type context = Match | Block | Paren

let make (base_lexer : Lexing.lexbuf -> Parser.token) : Lexing.lexbuf -> Parser.token =
  let stack : context Stack.t = Stack.create () in
  let pending_match_depths : int Stack.t = Stack.create () in
  let paren_depth = ref 0 in
  let buffered : Parser.token option ref = ref None in
  (* After ARROW in a match body, suppress ALL NLs until a real token. *)
  let suppress_nl = ref false in

  let in_match () =
    not (Stack.is_empty stack) && Stack.top stack = Match
  in

  let raw lexbuf =
    match !buffered with
    | Some tok -> buffered := None; tok
    | None -> base_lexer lexbuf
  in

  let rec next lexbuf =
    let tok = raw lexbuf in
    dispatch tok lexbuf

  and dispatch tok lexbuf =
    match tok with
    | Parser.MATCH ->
      suppress_nl := false;
      Stack.push !paren_depth pending_match_depths;
      tok

    (* CHOOSE BY chooser: ... END has END without DO — peek ahead
       for BY to distinguish from Chan.choose(...) expressions. *)
    | Parser.CHOOSE ->
      suppress_nl := false;
      let next_tok = raw lexbuf in
      (match next_tok with
       | Parser.BY ->
         (* Protocol choose block — push Block for its END *)
         Stack.push Block stack;
         buffered := Some Parser.BY;
         tok
       | other ->
         buffered := Some other;
         tok)

    | Parser.DO ->
      suppress_nl := false;
      if not (Stack.is_empty pending_match_depths)
         && Stack.top pending_match_depths = !paren_depth
      then begin
        ignore (Stack.pop pending_match_depths);
        Stack.push Match stack
      end else
        Stack.push Block stack;
      tok

    | Parser.END ->
      suppress_nl := false;
      if not (Stack.is_empty stack) then ignore (Stack.pop stack);
      tok

    | Parser.LPAREN | Parser.LBRACKET | Parser.LBRACE ->
      suppress_nl := false;
      incr paren_depth;
      Stack.push Paren stack;
      tok

    | Parser.RPAREN | Parser.RBRACKET | Parser.RBRACE ->
      suppress_nl := false;
      decr paren_depth;
      if not (Stack.is_empty stack) then ignore (Stack.pop stack);
      tok

    | Parser.ARROW when in_match () ->
      (* After -> in a match body, suppress all NLs until a real token *)
      suppress_nl := true;
      tok

    | Parser.NL ->
      if in_match () then begin
        if !suppress_nl then
          (* Still eating NLs after ARROW — skip *)
          next lexbuf
        else begin
          (* Collapse consecutive NLs and peek ahead.
             If the next real token is END, suppress the NL. *)
          let rec skip_nls lexbuf =
            let t = raw lexbuf in
            match t with
            | Parser.NL -> skip_nls lexbuf
            | other -> other
          in
          let after = skip_nls lexbuf in
          match after with
          | Parser.END ->
            dispatch after lexbuf
          | other ->
            buffered := Some other;
            Parser.NL
        end
      end else
        next lexbuf  (* outside match body — swallow *)

    | _ ->
      suppress_nl := false;
      tok
  in
  next
