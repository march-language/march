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

(* [With] marks the block opened by a monadic `with pat <- e do ... end`.
   It behaves like [Block] inside the body (newlines swallowed), but its
   [else] arms are match-style: at the [else] keyword the context is promoted
   to [Match] so newlines separate the arms (see the ELSE handler). *)
type context = Match | Block | Paren | With

(* Per-match state for tracking whether we're inside an arm body *)
type match_state = {
  mutable ms_suppress_nl : bool;  (* suppress NLs after ARROW *)
  mutable ms_in_arm_body : bool;  (* inside arm body (past first token after ARROW) *)
  ms_is_cond : bool;              (* cond form (`match do ... end`, no scrutinee):
                                     arm "patterns" are full boolean expressions,
                                     so the new-arm lookahead must not bail on the
                                     operators those expressions legitimately use *)
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
  (* Contextual test-DSL keywords. `test`/`describe` are keywords only when
     immediately followed by a STRING (`test "name" do` / `describe "name" do`),
     and `setup`/`setup_all` only when followed by DO. Everywhere else they are
     ordinary identifiers, so they can be function names, parameters and calls
     (March calls always use parens, so a STRING can never follow an identifier
     here except in the DSL). We demote them before the rest of the filter runs,
     using a one-token lookahead that preserves lexbuf positions so spans stay
     correct. *)
  let base_lexer =
    let orig = base_lexer in
    let pending : (Parser.token * Lexing.position * Lexing.position) option ref =
      ref None in
    fun lexbuf ->
      let (tok, sp, cp) =
        match !pending with
        | Some saved -> pending := None; saved
        | None ->
          let t = orig lexbuf in
          (t, lexbuf.Lexing.lex_start_p, lexbuf.Lexing.lex_curr_p)
      in
      let restore () =
        lexbuf.Lexing.lex_start_p <- sp;
        lexbuf.Lexing.lex_curr_p <- cp
      in
      let demote ident ~keep_when =
        let nxt = orig lexbuf in
        pending := Some (nxt, lexbuf.Lexing.lex_start_p, lexbuf.Lexing.lex_curr_p);
        restore ();
        if keep_when nxt then tok else Parser.LOWER_IDENT ident
      in
      let after_string = function Parser.STRING _ -> true | _ -> false in
      let after_do = function Parser.DO -> true | _ -> false in
      match tok with
      | Parser.TEST      -> demote "test"      ~keep_when:after_string
      | Parser.DESCRIBE  -> demote "describe"  ~keep_when:after_string
      | Parser.SETUP     -> demote "setup"     ~keep_when:after_do
      | Parser.SETUP_ALL -> demote "setup_all" ~keep_when:after_do
      | _ -> restore (); tok
  in
  let stack : context Stack.t = Stack.create () in
  let pending_match_depths : int Stack.t = Stack.create () in
  (* Parallel to pending_match_depths: whether each pending MATCH is a cond
     form (`match do`, no scrutinee). Pushed at MATCH, popped by the matching
     DO in lockstep with pending_match_depths so they stay aligned. *)
  let pending_match_conds : bool Stack.t = Stack.create () in
  (* Paren-depths at which a monadic `with` is awaiting its opening [DO], so
     that [DO] pushes a [With] context rather than a plain [Block]. Recorded on
     the [<-] (GETS) token, which appears only in with-bindings. *)
  let pending_with_depths : int Stack.t = Stack.create () in
  let paren_depth = ref 0 in
  (* Buffer stores tokens with their original lexbuf positions so
     that re-queued tokens restore the correct span information. *)
  let buffer : tok_with_pos Queue.t = Queue.create () in
  (* Stack of match states, one per nested match level *)
  let match_states : match_state Stack.t = Stack.create () in

  (* Curried-call juxtaposition guard (grammar §7.3).
     March functions are uncurried, so `f(1)(2)` is not a chained call; the
     old parser silently split it into two statements and DISCARDED `(2)`.
     We reject it as a newline-sensitive parse error instead, while still
     accepting an IIFE `(fn x -> x)(5)` (the `)` closes a GROUP, not a call)
     and a two-line `f(1)⏎(g(2))` (the newline signals two statements).

     [paren_kinds] classifies each emitted [LPAREN]: [true] = a CALL's arg
     list (the preceding significant token is value-ending), [false] = a
     grouping/tuple/lambda paren. Popped on the matching [RPAREN].
     [last_closed_call] records whether the most-recently-closed paren was a
     call, so the guard can tell `f(1)(` (reject) from `(expr)(` (allow).
     [prev_significant] is the last non-NL token emitted to the parser;
     [saw_nl_since_significant] is set whenever an NL passes through the
     stream (even one that is later swallowed) and cleared on any non-NL
     token — this is the ONLY place the newline survives, since the parser
     never sees these NLs. *)
  let paren_kinds : bool Stack.t = Stack.create () in
  let last_closed_call = ref false in
  let prev_significant : Parser.token option ref = ref None in
  let saw_nl_since_significant = ref false in
  let is_value_ending = function
    | Parser.LOWER_IDENT _ | Parser.UPPER_IDENT _
    | Parser.RPAREN | Parser.RBRACKET -> true
    | _ -> false
  in

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

  (* Check if a token could start a match arm pattern.

     Kept in sync with the grammar's `pattern` / `simple_pattern` rules
     (parser.mly): `pattern` accepts qualified_upper (UPPER_IDENT), ATOM,
     and simple_pattern; `simple_pattern` accepts UNDERSCORE,
     soft_lower_name (LOWER_IDENT plus the soft keywords below), INT,
     MINUS INT, FLOAT, MINUS FLOAT, STRING, BOOL, LPAREN, and LBRACKET.
     There is no CHAR token in this grammar. *)
  let is_pattern_start tok =
    match tok with
    | Parser.UPPER_IDENT _ | Parser.LOWER_IDENT _
    | Parser.UNDERSCORE | Parser.INT _ | Parser.FLOAT _ | Parser.STRING _
    | Parser.BOOL _
    | Parser.LPAREN | Parser.LBRACKET | Parser.MINUS
    | Parser.ATOM _
    (* soft_lower_name keywords also usable as a var-pattern binder *)
    | Parser.STATE | Parser.INIT | Parser.LOOP | Parser.ON
    | Parser.PROTOCOL | Parser.APP | Parser.AS | Parser.WITH
    | Parser.WHEN | Parser.USE | Parser.IN | Parser.FOR
    | Parser.TAG -> true
    | _ -> false
  in

  (* Scan ahead to determine if the upcoming tokens form a new arm
     (pattern ... ARROW) or are a continuation of the current arm body.

     first_tok is the first token already consumed from the stream.
     Strategy: process first_tok then read more tokens until we see
     either ARROW at depth=0 or NL at depth=0.
     If ARROW -> new arm. If NL -> body continuation.
     Also bail on tokens that can't appear in patterns at depth=0.

     [is_cond] is true when the enclosing match is the cond form
     (`match do BoolExpr -> body end`), where the thing before `->` is a full
     boolean expression rather than a plain pattern. In that mode — and, for a
     scrutinee match, once a WHEN token has been seen (we are now scanning the
     guard expression of `Pattern when GuardExpr -> body`) — the binary
     operators below are legitimate parts of the expression, NOT a signal that
     this is a body continuation, so we must keep scanning toward the ARROW
     instead of bailing. The structural bail-outs (EQUALS/DO/LET/IF/MATCH/FN/
     PFN/ASSERT) stay unconditional: those only ever appear in a body
     continuation, and they guard against a spurious depth-0 ARROW from a
     nested lambda/construct being mistaken for an arm separator. *)
  let lookahead_is_new_arm ~is_cond first_tok lexbuf =
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
    (* Set once a depth-0 WHEN is seen: everything after it up to the ARROW is
       guard-expression territory, so suppress the operator bail-out just like
       cond mode does. *)
    let seen_when = ref false in

    let process tok =
      (* Binary operators are only a bail-out signal outside boolean-expression
         territory (i.e. not a cond arm and not past a guard's WHEN). *)
      let suppress_operators = is_cond || !seen_when in
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
      | Parser.LPAREN | Parser.LBRACKET | Parser.LBRACE ->
        incr depth
      | Parser.RPAREN | Parser.RBRACKET | Parser.RBRACE ->
        if !depth > 0 then decr depth
        else begin
          result := false;
          done_ := true
        end
      | Parser.WHEN when !depth = 0 ->
        (* Entering a match arm's guard expression. *)
        seen_when := true
      | Parser.EQUALS | Parser.DO | Parser.LET | Parser.IF
      | Parser.MATCH | Parser.FN | Parser.PFN | Parser.ASSERT
        when !depth = 0 ->
        result := false;
        done_ := true
      | Parser.PLUS | Parser.STAR | Parser.SLASH | Parser.PERCENT
      | Parser.PIPE_ARROW | Parser.LEQ | Parser.GEQ | Parser.EQEQ
      | Parser.NEQ | Parser.AND | Parser.OR | Parser.PLUSPLUS
        when !depth = 0 && not suppress_operators ->
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
    (* Record every newline that passes through the emit stream — even ones
       swallowed below — so the LPAREN guard in [emit] can tell `f(1)(2)`
       (reject) from `f(1)⏎(g(2))` (two statements, allow). *)
    (match tok with Parser.NL -> saw_nl_since_significant := true | _ -> ());
    check_arm_body_transition tok;
    match tok with
    | Parser.MATCH ->
      Stack.push !paren_depth pending_match_depths;
      (* Cond form iff DO immediately follows the `match` keyword (`match do`,
         no scrutinee). Peek exactly one token and re-queue it so dispatch
         proceeds unchanged — re-queuing whatever we saw (including an NL)
         leaves the downstream NL handling byte-for-byte as before. The
         idiomatic cond form always writes `match do` on one line, so no NL
         ever sits between the keyword and DO here. *)
      let peeked = raw lexbuf in
      Stack.push (peeked = Parser.DO) pending_match_conds;
      push_buf peeked lexbuf;
      tok

    (* `<-` (GETS) appears only in monadic with-bindings. Record the with's
       paren-depth so the following [DO] opens a [With] block whose [else]
       arms are newline-separated. Multiple bindings of one `with` share a
       paren-depth; dedup them to a single pending entry so exactly one [DO]
       consumes it. *)
    | Parser.GETS ->
      if Stack.is_empty pending_with_depths
         || Stack.top pending_with_depths <> !paren_depth
      then Stack.push !paren_depth pending_with_depths;
      tok

    (* CHOOSE BY chooser: ... END has END without DO — peek ahead
       for BY to distinguish from Chan.choose(...) expressions. *)
    | Parser.CHOOSE ->
      let next_tok = raw lexbuf in
      (match next_tok with
       | Parser.BY ->
         (* Protocol choose block — push Match so NL works as branch separator *)
         Stack.push Match stack;
         Stack.push { ms_suppress_nl = false; ms_in_arm_body = false; ms_is_cond = false } match_states;
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
        (* pending_match_conds is pushed for every MATCH and popped here in
           lockstep, so it is non-empty whenever pending_match_depths matched. *)
        let is_cond =
          if Stack.is_empty pending_match_conds then false
          else Stack.pop pending_match_conds
        in
        Stack.push Match stack;
        Stack.push { ms_suppress_nl = false; ms_in_arm_body = false; ms_is_cond = is_cond } match_states
      end
      else if not (Stack.is_empty pending_with_depths)
         && Stack.top pending_with_depths = !paren_depth
      then begin
        (* This is a monadic `with`'s DO. The body is block-style (like a
           plain Block); the ELSE handler promotes it to Match for the arms. *)
        ignore (Stack.pop pending_with_depths);
        Stack.push With stack
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

    | Parser.LPAREN | Parser.LBRACKET | Parser.LBRACE ->
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

    | Parser.ELSE
      when (not (Stack.is_empty stack)) && Stack.top stack = With ->
      (* Entering the else-arms of a monadic `with`. Promote the With block to
         a Match context so newlines separate the arms exactly like a `match`
         body; the single matching END pops this Match context. The arms are
         ordinary pattern arms (not the cond form), so ms_is_cond = false. *)
      ignore (Stack.pop stack);
      Stack.push Match stack;
      Stack.push { ms_suppress_nl = false; ms_in_arm_body = false; ms_is_cond = false } match_states;
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
            if lookahead_is_new_arm ~is_cond:ms.ms_is_cond tok_after lexbuf then begin
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

  (* Single outermost boundary for the curried-call guard. [next] produces the
     token actually handed to the parser; here — and ONLY here, so swallowed
     NLs and lookahead re-queues can never double-count — we maintain the
     paren-kind stack, remember the previous significant token, and reject a
     [LPAREN] that immediately follows a call's closing [RPAREN] with no
     intervening newline. *)
  let emit lexbuf =
    let tok = next lexbuf in
    (match tok with
     | Parser.LPAREN ->
       (* Guard: `<call>)( ...` on one line is a curried-call juxtaposition. *)
       if !prev_significant = Some Parser.RPAREN
          && not !saw_nl_since_significant
          && !last_closed_call
       then
         raise (March_errors.Errors.ParseError
           ("`f(...)(...)` is not a chained call — March functions are not \
             curried.",
            Some "Write `f(a, b)` for a multi-argument call, or put the second \
                  call on its own line if you meant two separate statements.",
            lexbuf.Lexing.lex_start_p));
       (* Classify this paren: a CALL's arg list iff the preceding significant
          token is value-ending (`f(`/`Con(`/`g()(`/`xs[i](`), else a group.
          [prev_significant] still holds the token before this LPAREN — it is
          not updated until the bottom of [emit]. *)
       let is_call =
         match !prev_significant with
         | Some t -> is_value_ending t
         | None -> false
       in
       Stack.push is_call paren_kinds
     | Parser.RPAREN ->
       last_closed_call :=
         (if Stack.is_empty paren_kinds then false else Stack.pop paren_kinds)
     | _ -> ());
    (match tok with
     | Parser.NL -> ()  (* keep saw_nl set; prev_significant unchanged *)
     | _ ->
       prev_significant := Some tok;
       saw_nl_since_significant := false);
    tok
  in
  emit
