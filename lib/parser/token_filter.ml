(** Contextual newline filter for the March parser.

    The lexer emits [NL] for every newline. This filter sits between
    the lexer and the parser, passing [NL] tokens through only when
    inside a [match ... do ... end] body at the outermost nesting
    level. Everywhere else, [NL] tokens are silently consumed.

    Inside match bodies:
    - NL after ARROW is suppressed (arm body continuation, including
      multiple NLs from comment lines between -> and the body)
    - When in an arm body, NL is suppressed unless the next non-NL
      tokens form a new pattern->... arm (detected via lookahead)
    - NL immediately before END is suppressed
    This gives the parser a clean stream: [DO NL branch NL branch END]. *)

type context = Match | Block | Paren

(* Per-match state for tracking whether we're inside an arm body *)
type match_state = {
  mutable ms_suppress_nl : bool;  (* suppress NLs after ARROW *)
  mutable ms_in_arm_body : bool;  (* inside arm body (past first token after ARROW) *)
}

(* A token together with the lexbuf positions it was lexed at.
   Saved so that when a token is re-queued after lookahead, the
   parser sees the correct source location rather than the position
   the lexbuf has advanced to. *)
type tok_with_pos = {
  tok     : Parser.token;
  start_p : Lexing.position;
  curr_p  : Lexing.position;
}

let make (base_lexer : Lexing.lexbuf -> Parser.token) : Lexing.lexbuf -> Parser.token =
  let stack : context Stack.t = Stack.create () in
  let pending_match_depths : int Stack.t = Stack.create () in
  let paren_depth = ref 0 in
  (* Buffer stores tokens with their original lexbuf positions so
     that re-queued tokens restore the correct span information. *)
  let buffer : tok_with_pos Queue.t = Queue.create () in
  (* Stack of match states, one per nested match level *)
  let match_states : match_state Stack.t = Stack.create () in

  let in_match () =
    not (Stack.is_empty stack) && Stack.top stack = Match
  in

  let cur_ms () =
    if Stack.is_empty match_states then None
    else Some (Stack.top match_states)
  in

  (* Read the next token, restoring lexbuf positions if the token
     comes from the lookahead buffer. *)
  let raw lexbuf =
    if not (Queue.is_empty buffer) then begin
      let { tok; start_p; curr_p } = Queue.pop buffer in
      lexbuf.Lexing.lex_start_p <- start_p;
      lexbuf.Lexing.lex_curr_p  <- curr_p;
      tok
    end else
      base_lexer lexbuf
  in

  (* Push a token back into the buffer, saving the current lexbuf
     positions so they can be restored when the token is dequeued. *)
  let push_buf tok lexbuf =
    Queue.push {
      tok;
      start_p = lexbuf.Lexing.lex_start_p;
      curr_p  = lexbuf.Lexing.lex_curr_p;
    } buffer
  in

  (* Check if a token could start a match arm pattern *)
  let is_pattern_start tok =
    match tok with
    | Parser.UPPER_IDENT _ | Parser.LOWER_IDENT _
    | Parser.UNDERSCORE | Parser.INT _ | Parser.STRING _
    | Parser.BOOL _
    | Parser.LPAREN | Parser.LBRACKET | Parser.MINUS
    | Parser.ATOM _ -> true
    | _ -> false
  in

  (* Scan ahead to determine if the upcoming tokens form a new arm
     (pattern ... ARROW) or are a continuation of the current arm body.

     first_tok is the first token already consumed from the stream.
     Strategy: process first_tok then read more tokens until we see
     either ARROW at depth=0 or NL at depth=0.
     If ARROW -> new arm. If NL -> body continuation.
     Also bail on tokens that can't appear in patterns at depth=0. *)
  let lookahead_is_new_arm first_tok lexbuf =
    let buffered_tokens : tok_with_pos Queue.t = Queue.create () in
    (* first_tok was just returned by raw lexbuf, so current positions are its *)
    Queue.push {
      tok     = first_tok;
      start_p = lexbuf.Lexing.lex_start_p;
      curr_p  = lexbuf.Lexing.lex_curr_p;
    } buffered_tokens;
    let depth = ref 0 in
    let result = ref false in
    let done_ = ref false in

    let process tok =
      match tok with
      | Parser.ARROW when !depth = 0 ->
        result := true;
        done_ := true
      | Parser.NL when !depth = 0 ->
        result := false;
        done_ := true
      | Parser.EOF ->
        result := false;
        done_ := true
      | Parser.END when !depth = 0 ->
        result := false;
        done_ := true
      | Parser.LPAREN | Parser.LBRACKET | Parser.LBRACE | Parser.RECORD_LBRACE ->
        incr depth
      | Parser.RPAREN | Parser.RBRACKET | Parser.RBRACE ->
        if !depth > 0 then decr depth
        else begin
          result := false;
          done_ := true
        end
      | Parser.EQUALS | Parser.PLUS | Parser.STAR | Parser.SLASH
      | Parser.PERCENT | Parser.PIPE_ARROW | Parser.DO | Parser.LET | Parser.IF
      | Parser.MATCH | Parser.FN | Parser.PFN | Parser.ASSERT
      | Parser.LEQ | Parser.GEQ | Parser.EQEQ | Parser.NEQ
      | Parser.AND | Parser.OR | Parser.PLUSPLUS
        when !depth = 0 ->
        result := false;
        done_ := true
      | _ -> ()
    in

    (* Process the first token *)
    process first_tok;

    (* Continue reading if not done — save positions for each new token *)
    while not !done_ do
      let tok = base_lexer lexbuf in
      Queue.push {
        tok;
        start_p = lexbuf.Lexing.lex_start_p;
        curr_p  = lexbuf.Lexing.lex_curr_p;
      } buffered_tokens;
      process tok
    done;
    (* Put all buffered tokens back into the global buffer *)
    Queue.transfer buffered_tokens buffer;
    !result
  in

  (* If suppress_nl is active and we see a non-NL token, transition to in_arm_body.
     Must be called before token-specific dispatch for tokens that have
     their own handlers (DO, MATCH, LPAREN, etc.) *)
  let check_arm_body_transition tok =
    match tok with
    | Parser.NL -> ()  (* NL is handled separately *)
    | _ ->
      (match cur_ms () with
       | Some ms when ms.ms_suppress_nl ->
         ms.ms_suppress_nl <- false;
         ms.ms_in_arm_body <- true
       | _ -> ())
  in

  let rec next lexbuf =
    let tok = raw lexbuf in
    dispatch tok lexbuf

  and dispatch tok lexbuf =
    check_arm_body_transition tok;
    match tok with
    | Parser.MATCH ->
      Stack.push !paren_depth pending_match_depths;
      tok

    (* CHOOSE BY chooser: ... END has END without DO — peek ahead
       for BY to distinguish from Chan.choose(...) expressions. *)
    | Parser.CHOOSE ->
      let next_tok = raw lexbuf in
      (match next_tok with
       | Parser.BY ->
         (* Protocol choose block — push Match so NL works as branch separator *)
         Stack.push Match stack;
         Stack.push { ms_suppress_nl = false; ms_in_arm_body = false } match_states;
         push_buf Parser.BY lexbuf;
         tok
       | other ->
         push_buf other lexbuf;
         tok)

    | Parser.DO ->
      if not (Stack.is_empty pending_match_depths)
         && Stack.top pending_match_depths = !paren_depth
      then begin
        ignore (Stack.pop pending_match_depths);
        Stack.push Match stack;
        Stack.push { ms_suppress_nl = false; ms_in_arm_body = false } match_states
      end else
        Stack.push Block stack;
      tok

    | Parser.END ->
      if not (Stack.is_empty stack) then begin
        let ctx = Stack.pop stack in
        if ctx = Match && not (Stack.is_empty match_states) then
          ignore (Stack.pop match_states)
      end;
      tok

    | Parser.LPAREN | Parser.LBRACKET | Parser.LBRACE | Parser.RECORD_LBRACE ->
      incr paren_depth;
      Stack.push Paren stack;
      tok

    | Parser.RPAREN | Parser.RBRACKET | Parser.RBRACE ->
      decr paren_depth;
      if not (Stack.is_empty stack) then ignore (Stack.pop stack);
      tok

    | Parser.ARROW when in_match () ->
      (* After -> in a match body, suppress all NLs until a real token *)
      (match cur_ms () with
       | Some ms ->
         ms.ms_suppress_nl <- true;
         ms.ms_in_arm_body <- false
       | None -> ());
      tok

    | Parser.NL ->
      if in_match () then begin
        match cur_ms () with
        | Some ms when ms.ms_suppress_nl ->
          (* Still eating NLs after ARROW — skip *)
          next lexbuf
        | Some ms when ms.ms_in_arm_body ->
          (* Inside an arm body: peek ahead to decide if this NL
             separates arms or continues the current arm body. *)
          let rec skip_nls lexbuf =
            let t = raw lexbuf in
            match t with
            | Parser.NL -> skip_nls lexbuf
            | other -> other
          in
          let after = skip_nls lexbuf in
          (match after with
          | Parser.END ->
            (* NL before END — suppress, dispatch END *)
            ms.ms_in_arm_body <- false;
            dispatch after lexbuf
          | Parser.PIPE ->
            (* Explicit pipe arm separator — emit NL as arm boundary *)
            push_buf after lexbuf;
            ms.ms_in_arm_body <- false;
            Parser.NL
          | tok_after when is_pattern_start tok_after ->
            (* Could be a new arm or a body continuation.
               Use lookahead: pass tok_after as the first token, then
               scan for ARROW vs NL *)
            if lookahead_is_new_arm tok_after lexbuf then begin
              (* New arm — emit NL as arm separator *)
              ms.ms_in_arm_body <- false;
              Parser.NL
            end else begin
              (* Body continuation — suppress NL *)
              next lexbuf
            end
          | other ->
            (* Not a pattern start — body continuation, suppress NL *)
            push_buf other lexbuf;
            next lexbuf)
        | _ ->
          (* Not in arm body (before first arm or no match state).
             Collapse NLs and peek for END. *)
          let rec skip_nls lexbuf =
            let t = raw lexbuf in
            match t with
            | Parser.NL -> skip_nls lexbuf
            | other -> other
          in
          let after = skip_nls lexbuf in
          (match after with
          | Parser.END ->
            dispatch after lexbuf
          | other ->
            push_buf other lexbuf;
            Parser.NL)
      end else
        next lexbuf  (* outside match body — swallow *)

    | _ ->
      tok
  in
  next
