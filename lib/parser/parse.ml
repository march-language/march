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

(* ── D1: point a structural error at the construct that is missing its `end`

   When a parse fails with the lookahead at a declaration keyword or the end
   of the input, the grammar gave up AFTER the mistake: a missing `end`
   leaves an `if`/`fn`/`match` open, and the parser only notices when the next
   `fn` (or EOF) cannot continue it. [Token_filter.make_with_state] tracked
   the open constructs; this picks the culprit and overrides the diagnostic's
   SPAN and FIX only. A message a grammar error production chose is kept (it
   names the construct); the generic "I got stuck here" is replaced.

   The culprit, in order of preference:
   0. a declaration keyword (`fn`, `type`, ...) on a later line at or left of
      an open construct's indentation: those constructs each need an `end`
      before that line (a `fn` written while the previous one is still open).
   1. an opener that an `end` closed although that `end` sits on a later line
      and LEFT of the opener's line indentation: that `end` belongs to an outer
      block, so the opener was one `end` short (the `else if … end` chain is
      the classic case). The fix inserts `end` just before that line, at the
      opener's indentation. When both 0 and 1 apply, whichever comes first in
      the file wins: the later one is the consequence.
   2. otherwise the innermost construct still open. The fix inserts one `end`
      per construct that must close before the lookahead: all of them at EOF,
      everything above the innermost `mod` at a declaration keyword.
   A lookahead `end` with nothing open is reported as closing nothing. *)

let is_decl_keyword = Token_filter.is_declaration_keyword

(* Error-production messages that name no construct; treated like menhir's
   own "I got stuck here" (replaced, not kept). *)
let generic_messages = [ "Parse error in declaration" ]

let token_word = function
  | Parser.FN -> "fn" | Parser.PFN -> "pfn" | Parser.MOD -> "mod"
  | Parser.TYPE -> "type" | Parser.PTYPE -> "ptype" | Parser.ACTOR -> "actor"
  | Parser.APP -> "app" | Parser.IMPL -> "impl" | Parser.INTERFACE -> "interface"
  | Parser.PROTOCOL -> "protocol" | Parser.EXTERN -> "extern" | Parser.SIG -> "sig"
  | Parser.TEST -> "test" | Parser.DESCRIBE -> "describe" | Parser.NEEDS -> "needs"
  | Parser.DERIVE -> "derive" | Parser.SATISFY -> "satisfy" | _ -> "this token"

let src_lines src = Array.of_list (String.split_on_char '\n' src)

let line_text lines n = if n >= 1 && n <= Array.length lines then lines.(n - 1) else ""

let indent_of s =
  let n = String.length s in
  let rec go i = if i < n && (s.[i] = ' ' || s.[i] = '\t') then go (i + 1) else i in
  go 0

let col (p : Lexing.position) = p.Lexing.pos_cnum - p.Lexing.pos_bol

let span_at ~filename (p : Lexing.position) len =
  let file = if filename <> "" then filename else p.Lexing.pos_fname in
  { March_ast.Ast.file; start_line = p.Lexing.pos_lnum; start_col = col p;
    end_line = p.Lexing.pos_lnum; end_col = col p + len }

let chain_note =
  "`else if` is a nested `if` in the else position, so each `if` needs its \
   own `end`: a two-branch chain ends `end end`, a three-branch chain \
   `end end end`."

let refine_structural ~filename ~src ~generic (st : Token_filter.open_state)
    (d : Errors.diagnostic) : Errors.diagnostic =
  let lines = src_lines src in
  let open Token_filter in
  match st.last_tok with
  | Some Parser.END when st.openers = [] && st.stray_end <> None ->
    let p = Option.get st.stray_end in
    let only_end = String.trim (line_text lines p.Lexing.pos_lnum) = "end" in
    { d with
      span = span_at ~filename p 3;
      message =
        (if generic then "This `end` closes nothing: every block before it is \
                          already closed."
         else d.message);
      fix =
        (if only_end then
           Some (Errors.FDelete { start_line = p.Lexing.pos_lnum;
                                  end_line = p.Lexing.pos_lnum })
         else d.fix) }
  | Some la when (la = Parser.EOF || is_decl_keyword la) ->
    let where =
      if la = Parser.EOF then "the end of the file"
      else Printf.sprintf "`%s` on line %d" (token_word la) st.last_pos.Lexing.pos_lnum
    in
    (* Insert before line [n]: after the last non-blank line above it, so the
       new `end` sits against the block it closes, not after a blank gap. *)
    let before_line n =
      let rec back k = if k >= 1 && String.trim (line_text lines k) = "" then back (k - 1) else k in
      back (n - 1)
    in
    let indent_at (p : Lexing.position) = indent_of (line_text lines p.Lexing.pos_lnum) in
    let ends_for os = String.concat "\n"
        (List.map (fun o -> String.make (indent_at o.op_pos) ' ' ^ "end") os) in
    (* 1. A declaration keyword written at or left of an open construct's
          indentation, on a later line, closes that construct in the
          writer's mind: those constructs are each one `end` short, right
          before the keyword's line. *)
    let dedented =
      List.find_map (fun ((p : Lexing.position), open_) ->
          let short =
            List.filter (fun o ->
                o.op_pos.Lexing.pos_lnum < p.Lexing.pos_lnum
                && o.op_kw <> "mod"
                && col p <= indent_at o.op_pos)
              open_
          in
          if short = [] then None else Some (p, short))
        st.decls
    in
    (* 2. An `end` on a later line and LEFT of its opener's indentation
          belongs to an outer block: the opener was one `end` short. *)
    let short_closed =
      List.find_opt (fun (o, (e : Lexing.position)) ->
          e.Lexing.pos_lnum > o.op_pos.Lexing.pos_lnum
          && col e < indent_at o.op_pos)
        st.closed
    in
    (* Both kinds of evidence present: the one that appears first in the file
       is the mistake; the later one is its consequence. *)
    let dedented, short_closed =
      match dedented, short_closed with
      | Some ((p : Lexing.position), _), Some (_, (e : Lexing.position))
        when e.Lexing.pos_lnum < p.Lexing.pos_lnum -> (None, short_closed)
      | Some _, Some _ -> (dedented, None)
      | _ -> (dedented, short_closed)
    in
    let culprit, fix =
      match dedented, short_closed, st.openers with
      | Some (p, (inner :: _ as short)), _, _ ->
        (Some inner,
         Some (Errors.FInsert { after_line = before_line p.Lexing.pos_lnum; text = ends_for short }))
      | _, Some (o, e), _ ->
        (Some o,
         Some (Errors.FInsert { after_line = before_line e.Lexing.pos_lnum; text = ends_for [ o ] }))
      | _, None, [] -> (None, None)
      | _, None, (inner :: _ as open_) ->
        (* 3. Which constructs must close before the lookahead. *)
        let to_close =
          if la = Parser.EOF then open_
          else
            (* a declaration keyword is legal directly inside a `mod`
               (or at top level): close everything above the innermost one *)
            let rec upto acc = function
              | [] -> List.rev acc
              | o :: _ when o.op_kw = "mod" -> List.rev acc
              | o :: rest -> upto (o :: acc) rest
            in
            upto [] open_
        in
        let after_line =
          if la = Parser.EOF then
            let n = Array.length lines in
            if n > 0 && String.trim lines.(n - 1) = "" then n - 1 else n
          else before_line st.last_pos.Lexing.pos_lnum
        in
        (* Several open: the innermost is the likeliest to be one `end`
           short (an `end` the user did write closed the one above it). *)
        (Some inner,
         if to_close = [] then None
         else Some (Errors.FInsert { after_line; text = ends_for to_close }))
    in
    (match culprit with
     | None -> d
     | Some o ->
       let message =
         if not generic then d.message
         else match short_closed with
           | Some (_, e) ->
             Printf.sprintf "This `%s` (line %d) needs its own `end`: the `end` \
                             on line %d belongs to an outer block."
               o.op_kw o.op_pos.Lexing.pos_lnum e.Lexing.pos_lnum
           | None ->
             Printf.sprintf "This `%s` (line %d) has no matching `end`."
               o.op_kw o.op_pos.Lexing.pos_lnum
       in
       let noticed = Printf.sprintf "I only noticed at %s." where in
       let chain = if o.op_kw = "if" && o.op_else_if then [ chain_note ] else [] in
       { d with
         span = span_at ~filename o.op_pos (String.length o.op_kw);
         message;
         notes = d.notes @ (noticed :: chain);
         fix = (match fix with Some _ -> fix | None -> d.fix) })
  | _ -> d

let run ?(filename = "") ?(stuck = "I got stuck here:") entry src =
  let lexbuf = lexbuf_of_string ~filename src in
  let (lexer, state) = Token_filter.make_with_state Lexer.token in
  let refine ~generic (d : Errors.diagnostic) =
    let generic = generic || List.mem d.message generic_messages in
    refine_structural ~filename ~src ~generic (state ()) d in
  (* Clear any value a ParseError caught elsewhere (a [*_of_lexbuf] caller)
     may have left, so this parse's extras are its own. *)
  ignore (Errors.take_parse_error_extra ());
  match entry lexer lexbuf with
  | v -> Ok v
  | exception Errors.ParseError (msg, hint, pos) ->
    (* D4: the production's own code and fix, when it set them. *)
    let (code, fix) = Errors.take_parse_error_extra () in
    let code = Option.value code ~default:code_parse_error in
    Error [ refine ~generic:false
              { (Errors.parse_error_diagnostic_at ~filename ?hint ~src ~msg pos)
                with code; fix } ]
  | exception Parser.Error ->
    Error [ refine ~generic:true
              { (Errors.parse_error_diagnostic ~filename ~msg:stuck lexbuf)
                with code = code_syntax_error } ]
  | exception Lexer.Lexer_error msg ->
    (* The lexer's sub-rules leave no usable lexeme; one caret where it
       stopped. *)
    Error [ { (Errors.parse_error_diagnostic_at ~filename ~len:1 ~msg
                 (Lexing.lexeme_start_p lexbuf))
              with code = code_lex_error } ]
  | exception Lexer.Lexer_error_fix { msg; code; note; replace } ->
    (* A one-character lexeme the lexer knows how to repair (`;`). The fix
       covers the lexeme and the blanks after it: a trailing one is deleted,
       one between two expressions becomes a line break at the current
       indentation, so the applied program reads as if written that way. *)
    let p = Lexing.lexeme_start_p lexbuf in
    let lines = src_lines src in
    let text = line_text lines p.Lexing.pos_lnum in
    let c = col p in
    let rec skip i = if i < String.length text && (text.[i] = ' ' || text.[i] = '\t') then skip (i + 1) else i in
    let e = skip (c + 1) in
    let trailing = e >= String.length text in
    let fix =
      let span = { (span_at ~filename p 1) with March_ast.Ast.end_col = e } in
      Errors.FReplace
        { span;
          text = (if trailing then "" else if replace = "\n"
                  then "\n" ^ String.make (indent_of text) ' ' else replace) }
    in
    Error [ { (Errors.parse_error_diagnostic_at ~filename ~len:1 ~msg p)
              with code; notes = [ note ]; fix = Some fix } ]

let module_ ?filename ?stuck src    = run ?filename ?stuck Parser.module_ src
let repl_input ?filename ?stuck src = run ?filename ?stuck Parser.repl_input src
let expr ?filename ?stuck src       = run ?filename ?stuck Parser.expr_eof src
let repl_sequence ?filename ?stuck src =
  run ?filename ?stuck Parser.repl_sequence src
