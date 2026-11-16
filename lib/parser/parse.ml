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
           Some (Errors.fix (Errors.FDelete { start_line = p.Lexing.pos_lnum;
                                              end_line = p.Lexing.pos_lnum }))
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
         fix = (match fix with Some f -> Some (Errors.fix f) | None -> d.fix) })
  | _ -> d

(* ── Habits from other languages, read off the source text ─────────────────

   When the parser gets stuck, the token it stopped at and the text around it
   often say which habit from another language caused it.  Each pattern below
   replaces a generic "I got stuck here" (or another production's message)
   with what March wants instead, at the place the habit is, and with a fix
   when the edit is mechanical.  `--check` and `--check-json` re-check each
   fix before calling it machine-applicable (bin/fix_verify.ml), so a guess
   that does not parse is shown as one. *)

(* Positions of the brackets left open, and the string left open, at
   (line [stop_ln], column [stop_c]) of [src]: a scan that skips comments and
   string literals, including `${...}` interpolations inside strings. *)
type scan_ctx = Code | Str | Interp of int ref

let scan_open ~src ~stop_ln ~stop_c =
  let lines = src_lines src in
  let opens = ref [] in              (* (char, line, col), innermost first *)
  let str_start = ref None in
  let first_multiline = ref None in  (* the first string that spans lines *)
  let ctx = ref [ Code ] in
  (try
     Array.iteri (fun li text ->
         let ln = li + 1 in
         if ln > stop_ln then raise Exit;
         let n = String.length text in
         let i = ref 0 in
         let stop = if ln = stop_ln then min stop_c n else n in
         (try
            while !i < stop do
              let ch = text.[!i] in
              (match !ctx with
               | (Code | Interp _) :: _ ->
                 if ch = '-' && !i + 1 < n && text.[!i + 1] = '-' then raise Exit
                 else if ch = '"' then begin
                   ctx := Str :: !ctx; str_start := Some (ln, !i) end
                 else if ch = '(' || ch = '[' then opens := (ch, ln, !i) :: !opens
                 else if ch = ')' || ch = ']' then
                   (match !opens with _ :: rest -> opens := rest | [] -> ())
                 else if ch = '{' then
                   (match !ctx with Interp d :: _ -> incr d | _ -> ())
                 else if ch = '}' then
                   (match !ctx with
                    | Interp d :: rest -> if !d = 0 then ctx := rest else decr d
                    | _ -> ())
               | Str :: rest ->
                 if ch = '\\' then incr i
                 else if ch = '"' then begin
                   ctx := rest;
                   (match !str_start, !first_multiline with
                    | Some (sl, sc), None when sl < ln -> first_multiline := Some (sl, sc)
                    | _ -> ());
                   str_start := None end
                 else if ch = '$' && !i + 1 < n && text.[!i + 1] = '{' then begin
                   ctx := Interp (ref 0) :: !ctx; incr i end
               | [] -> ());
              incr i
            done
          with Exit -> ()))
       lines
   with Exit -> ());
  (!opens, (match !ctx with Str :: _ -> !str_start | _ -> None), !first_multiline)

let binary_operators =
  [ "++"; "+"; "-"; "*"; "/"; "%"; "&&"; "||"; "=="; "!="; "<="; ">="; "<"; ">"; "|>" ]

let syntax_patterns ~filename ~src ~generic (d : Errors.diagnostic) =
  let lines = src_lines src in
  let sp = d.Errors.span in
  let ln = sp.March_ast.Ast.start_line and c = sp.March_ast.Ast.start_col in
  let text = line_text lines ln in
  let n = String.length text in
  let at i = if i >= 0 && i < n then text.[i] else '\000' in
  let mk ?fix ?(notes = []) ?(span = sp) msg =
    Some { d with Errors.span; message = msg; notes; fix = Option.map Errors.fix fix } in
  let mkspan l c0 c1 = { March_ast.Ast.file = (if filename <> "" then filename else sp.March_ast.Ast.file);
                         start_line = l; start_col = c0; end_line = l; end_col = c1 } in
  let trimmed = String.trim text in
  let starts w = String.length trimmed >= String.length w
                 && String.sub trimmed 0 (String.length w) = w in
  (* The last non-blank character before the error, possibly on an earlier
     line: (line, col). *)
  let rec prev_char l i =
    if l < 1 then None
    else
      let t = line_text lines l in
      let i = min i (String.length t - 1) in
      let rec back i = if i >= 0 && (t.[i] = ' ' || t.[i] = '\t') then back (i - 1) else i in
      let j = back i in
      if j >= 0 then Some (l, j) else prev_char (l - 1) max_int in
  let word_at i =
    let rec e j = if j < n && (match text.[j] with 'a'..'z' | 'A'..'Z' | '_' -> true | _ -> false)
      then e (j + 1) else j in
    String.sub text i (e i - i) in
  if not generic && not (String.starts_with ~prefix:"I was expecting `do` to start the function body" d.message)
  then None
  (* `fn f(x : Int) -> Int do`: a return type after an arrow. *)
  else if at c = '-' && at (c + 1) = '>' then
    mk ~fix:(Errors.FReplace { span = mkspan ln c (c + 2); text = ":" })
      ~notes:[ "fn name(x : Int) : Int do\n    ...\nend" ]
      "A function's return type comes after a colon, `: Int`, not an arrow `-> Int`:"
  else if not generic then None
  (* Braces for a block: `fn f() {` / `if x > 0 {`. *)
  else if at c = '{' && String.trim (String.sub text (c + 1) (n - c - 1)) = "" then begin
    let ind = indent_of text in
    let close =
      let rec find k =
        if k > Array.length lines then None
        else
          let t = line_text lines k in
          if String.trim t = "}" && indent_of t = ind then Some (k, indent_of t)
          else find (k + 1) in
      find (ln + 1) in
    let open_edit = Errors.FReplace { span = mkspan ln c (c + 1); text = "do" } in
    let fix = match close with
      | Some (k, ci) ->
        Some (Errors.FMulti [ open_edit; Errors.FReplace { span = mkspan k ci (ci + 1); text = "end" } ])
      | None -> None in
    mk ?fix ~notes:[ "fn name(params) do\n    body\nend" ]
      "March blocks are written `do ... end`, not with braces:"
  end
  (* `type Color = | Red | Green`: a leading `|`. *)
  else if at c = '|' && starts "type " && (match prev_char ln (c - 1) with
      | Some (l, j) -> l = ln && at j = '=' | None -> false) then begin
    let rec skip j = if j < n && text.[j] = ' ' then skip (j + 1) else j in
    mk ~fix:(Errors.FReplace { span = mkspan ln c (skip (c + 1)); text = "" })
      ~notes:[ "type Color = Red | Green" ]
      "A type's variants are listed without a leading `|`:"
  end
  (* `f(x, )`, `[1, 2, ]`: a trailing comma. *)
  else if (at c = ')' || at c = ']') && (match prev_char ln (c - 1) with
      | Some (l, j) -> (line_text lines l).[j] = ',' | None -> false) then begin
    let (l, j) = Option.get (prev_char ln (c - 1)) in
    let fix =
      if l = ln then Errors.FReplace { span = mkspan ln j c; text = "" }
      else Errors.FReplace { span = mkspan l j (j + 1); text = "" } in
    mk ~fix ~span:(mkspan l j (j + 1))
      (Printf.sprintf "This `,` has nothing after it: the last %s is not followed by a comma."
         (if at c = ')' then "argument" else "item"))
  end
  (* `x +` with nothing after the operator. *)
  else if (match prev_char ln (c - 1) with
      | Some (l, j) ->
        let t = line_text lines l in
        List.exists (fun op ->
            let k = String.length op in
            j - k + 1 >= 0 && String.sub t (j - k + 1) k = op
            && (j - k < 0 || t.[j - k] = ' ')) binary_operators
      | None -> false) then begin
    let (l, j) = Option.get (prev_char ln (c - 1)) in
    let t = line_text lines l in
    let op = List.find (fun op ->
        let k = String.length op in
        j - k + 1 >= 0 && String.sub t (j - k + 1) k = op) binary_operators in
    let k = String.length op in
    mk ~span:(mkspan l (j - k + 1) (j + 1))
      ~notes:[ Printf.sprintf "Finish the expression after `%s`, or remove the `%s`." op op ]
      (Printf.sprintf "`%s` has nothing on its right: the expression stops here." op)
  end
  (* `def f()`, `function f()`: another language's function keyword. *)
  else if starts "def " || starts "defp " || starts "function " || starts "func " || starts "fun " then begin
    let w = word_at c in
    let repl = if w = "defp" then "pfn" else "fn" in
    if w = "" || not (List.mem w [ "def"; "defp"; "function"; "func"; "fun" ]) then None
    else
      mk ~fix:(Errors.FReplace { span = mkspan ln c (c + String.length w); text = repl })
        ~notes:[ "fn name(params) do\n    body\nend" ]
        (Printf.sprintf "Functions are declared with `fn` (`pfn` for a private one), not `%s`:" w)
  end
  else
    (* A bracket opened earlier and never closed: the parser only notices
       at the next `end` or declaration. *)
    match scan_open ~src ~stop_ln:ln ~stop_c:c with
    | ((ch, ol, oc) :: _, _, _) when ol < ln ->
      let ot = line_text lines ol in
      let closer = if ch = '(' then ")" else "]" in
      (* Close it at the end of its own line when the rest of that line
         closes everything it opens. *)
      let rest_balanced =
        let d = ref 0 and ok = ref true in
        String.iteri (fun i x -> if i > oc then
                         if x = '(' || x = '[' then incr d
                         else if x = ')' || x = ']' then (decr d; if !d < 0 then ok := false)) ot;
        !ok && !d = 0 in
      let e = String.length (String.trim ot) + indent_of ot in
      let fix = if rest_balanced then
          Some (Errors.FReplace { span = mkspan ol e e; text = closer }) else None in
      mk ?fix ~span:(mkspan ol oc (oc + 1))
        ~notes:[ Printf.sprintf "I only noticed at line %d." ln ]
        (Printf.sprintf "This `%c` is never closed." ch)
    | _ -> None

(* An unterminated string: the lexer reaches the end of the file inside it;
   point at where the string starts, and close it at the end of its line. *)
let unterminated_string ~filename ~src (d : Errors.diagnostic) =
  if d.Errors.message <> "Unterminated string literal" then d
  else
    let lines = src_lines src in
    (* A string may span lines, so one missing quote flips every later one:
       the first string that runs onto a later line is where it most likely
       went missing, before the one left open at the end. *)
    match scan_open ~src ~stop_ln:(Array.length lines + 1) ~stop_c:max_int with
    | (_, Some open_at, multi) ->
      let (ln, c) = Option.value multi ~default:open_at in
      let t = line_text lines ln in
      let file = if filename <> "" then filename else d.Errors.span.March_ast.Ast.file in
      let e = String.length t in
      { d with
        Errors.span = { March_ast.Ast.file; start_line = ln; start_col = c; end_line = ln; end_col = c + 1 };
        message = "This string is never closed: I reached the end of the file inside it.";
        notes = [ (if multi <> None && multi <> Some open_at then
                     "A string can span lines, so a missing `\"` makes the strings after it \
                      swap inside and out. This is the first one that runs past its line; \
                      close it where it should end."
                   else "Close it where it should end.") ];
        fix = Some (Errors.fix ~tier:Errors.Maybe_incorrect (Errors.FReplace {
            span = { March_ast.Ast.file; start_line = ln; start_col = e; end_line = ln; end_col = e };
            text = "\"" })) }
    | _ -> d

(* `let? x : T = e` / `let* x : T = e` (the parser stops at the `:`, [pos]):
   the fix deletes the annotation, from the `:` to the `=` that ends it on
   the same line. *)
let annotation_fix ~filename ~src ~msg (pos : Lexing.position) =
  if not (String.starts_with ~prefix:"A `let?` binding can't have a type annotation" msg
          || String.starts_with ~prefix:"A `let*` binding can't have a type annotation" msg)
  then None
  else
    let text = line_text (src_lines src) pos.Lexing.pos_lnum in
    let c = col pos in
    let n = String.length text in
    let rec find_eq i =
      if i >= n then None
      else if text.[i] = '='
           && (i + 1 >= n || (text.[i + 1] <> '=' && text.[i + 1] <> '>'))
           && (i = 0 || not (String.contains "=<>!" text.[i - 1]))
      then Some i
      else find_eq (i + 1) in
    match find_eq (c + 1) with
    | Some e when c < n && text.[c] = ':' ->
      let span = { (span_at ~filename pos 1) with March_ast.Ast.end_col = e } in
      Some (Errors.FReplace { span; text = (if c > 0 && text.[c - 1] = ' ' then "" else " ") })
    | _ -> None

let run ?(filename = "") ?(stuck = "I got stuck here:") entry src =
  let lexbuf = lexbuf_of_string ~filename src in
  let (lexer, state) = Token_filter.make_with_state Lexer.token in
  let refine ~generic (d : Errors.diagnostic) =
    let generic = generic || List.mem d.message generic_messages in
    match syntax_patterns ~filename ~src ~generic d with
    | Some d' -> d'
    | None -> refine_structural ~filename ~src ~generic (state ()) d in
  (* Clear any value a ParseError caught elsewhere (a [*_of_lexbuf] caller)
     may have left, so this parse's extras are its own. *)
  ignore (Errors.take_parse_error_extra ());
  match entry lexer lexbuf with
  | v -> Ok v
  | exception Errors.ParseError (msg, hint, pos) ->
    (* D4: the production's own code and fix, when it set them. *)
    let (code, fix) = Errors.take_parse_error_extra () in
    let fix = match fix with
      | Some _ -> fix
      | None -> annotation_fix ~filename ~src ~msg pos in
    let code = Option.value code ~default:code_parse_error in
    Error [ refine ~generic:false
              { (Errors.parse_error_diagnostic_at ~filename ?hint ~src ~msg pos)
                with code; fix = Errors.fix_opt fix } ]
  | exception Parser.Error ->
    Error [ refine ~generic:true
              { (Errors.parse_error_diagnostic ~filename ~msg:stuck lexbuf)
                with code = code_syntax_error } ]
  | exception Lexer.Lexer_error msg ->
    (* The lexer's sub-rules leave no usable lexeme; one caret where it
       stopped. *)
    Error [ unterminated_string ~filename ~src
              { (Errors.parse_error_diagnostic_at ~filename ~len:1 ~msg
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
              with code; notes = [ note ]; fix = Some (Errors.fix fix) } ]

let module_ ?filename ?stuck src    = run ?filename ?stuck Parser.module_ src
let repl_input ?filename ?stuck src = run ?filename ?stuck Parser.repl_input src
let expr ?filename ?stuck src       = run ?filename ?stuck Parser.expr_eof src
let repl_sequence ?filename ?stuck src =
  run ?filename ?stuck Parser.repl_sequence src
