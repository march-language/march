exception ParseError of string * string option * Lexing.position
(** ParseError (message, hint, position) *)

(** March error reporting.

    Errors carry provenance (source spans) and are designed
    to produce clear, non-cascading diagnostics with
    expected-vs-found framing. *)

module Code = Code

type severity = Error | Warning | Hint

type fix_kind =
  | FInsert of { after_line : int; text : string }
  (** Insert [text] as a new line immediately after line [after_line] (1-indexed).
      [text] must NOT include a trailing newline; the applier adds one. *)
  | FDelete of { start_line : int; end_line : int }
  (** Delete full source lines [start_line]..[end_line] inclusive (1-indexed). *)
  | FReplace of { span : March_ast.Ast.span; text : string }
  (** Replace the text covered by [span] with [text] in-place. *)

type diagnostic = {
  severity : severity;
  span : March_ast.Ast.span;
  message : string;
  labels : label list;     (** Additional labeled source spans *)
  notes : string list;      (** Extra context / suggestions *)
  code : string;           (** Machine-readable code from {!Code}, e.g. [Code.unused_binding].
                               Required: every diagnostic has one. *)
  fix : fix_kind option;   (** Mechanically-determined fix, if one exists *)
}

and label = {
  lbl_span : March_ast.Ast.span;
  lbl_message : string;
}

(** Accumulator for diagnostics — allows error recovery. *)
type ctx = { mutable diagnostics : diagnostic list }

(** What a grammar `error` production knows beyond [ParseError]'s
    (message, hint, position): its own code and a mechanical fix (D4,
    specs/plans/diagnostics-and-triage-plan.md §8). [ParseError] is matched
    as a 3-tuple at ~40 sites, so the extra fields ride a side channel:
    the grammar's [error_raise] sets this right before raising, every
    time (to [None, None] when it has nothing to add), and [Parse.run]
    reads and clears it when it catches the exception. A direct [raise
    ParseError] that bypasses [error_raise] would leave a stale value, so
    parser.mly has none. *)
let parse_error_extra : (string option * fix_kind option) ref = ref (None, None)

let take_parse_error_extra () =
  let v = !parse_error_extra in
  parse_error_extra := (None, None);
  v

let create () = { diagnostics = [] }

(* Some diagnostics get re-derived at every use of a declaration whose own
   definition is broken (e.g. instantiating a constructor re-resolves its
   stored surface argument types on each use, needed for fresh per-use type
   variables) — a name that fails to resolve there gets reported once per
   instantiation instead of once.  A diagnostic identical in severity, span,
   AND message can only be the same fact re-derived, never two independent
   issues that coincide byte-for-byte at the same source location, so
   suppress an exact repeat rather than showing the user the same error
   three times. *)
let report ctx diag =
  let is_dup (d : diagnostic) =
    d.severity = diag.severity && d.span = diag.span && d.message = diag.message
  in
  if not (List.exists is_dup ctx.diagnostics) then
    ctx.diagnostics <- diag :: ctx.diagnostics

let error ctx ~code ~span message =
  report ctx
    { severity = Error; span; message; labels = []; notes = []; code; fix = None }

let warning ctx ~code ~span message =
  report ctx
    { severity = Warning; span; message; labels = []; notes = []; code; fix = None }

let hint ctx ~code ~span message =
  report ctx
    { severity = Hint; span; message; labels = []; notes = []; code; fix = None }

(* Kept as an alias of [warning] now that every helper takes [~code]. *)
let warning_with_code = warning

let error_with_fix ctx ~code ~span ~fix message =
  report ctx
    { severity = Error; span; message; labels = []; notes = []; code; fix = Some fix }

let warning_with_fix ctx ~code ~span ~fix message =
  report ctx
    { severity = Warning; span; message; labels = []; notes = []; code; fix = Some fix }

let warning_with_code_and_fix = warning_with_fix

let use_color : bool ref = ref false

let ansi_reset        = "\027[0m"
let ansi_bold         = "\027[1m"
let ansi_dim          = "\027[2m"
let ansi_cyan         = "\027[36m"
let ansi_magenta      = "\027[35m"
let ansi_bold_magenta = "\027[1;35m"

let sev_bold_code  = function Error -> "\027[1;31m" | Warning -> "\027[1;33m" | Hint -> "\027[1;34m"
let sev_plain_code = function Error -> "\027[31m"   | Warning -> "\027[33m"   | Hint -> "\027[34m"

(** Wrap [s] in an ANSI [code]…reset pair when colour is on. *)
let paint code s =
  if !use_color then code ^ s ^ ansi_reset else s

(** Colour backtick-quoted spans within [s].
    Each matched `` `…` `` is wrapped in [inner_code]; [parent_code] is
    restored afterwards so surrounding styling is not lost. *)
let colorize_backticks ~parent_code ~inner_code s =
  if not !use_color then s
  else begin
    let parts = String.split_on_char '`' s in
    let n = List.length parts in
    List.mapi (fun i part ->
      if i mod 2 = 1 && i + 1 < n then
        inner_code ^ "`" ^ part ^ "`" ^ ansi_reset ^ parent_code
      else part
    ) parts |> String.concat ""
  end

(** Bold primary message with bold-magenta backtick terms. *)
let fmt_message s =
  paint ansi_bold
    (colorize_backticks ~parent_code:ansi_bold ~inner_code:ansi_bold_magenta s)

(** Dim note with plain-magenta backtick terms. *)
let fmt_note s =
  paint ansi_dim
    (colorize_backticks ~parent_code:ansi_dim ~inner_code:ansi_magenta s)

(* ─────────────────────────────────────────────────────────────────────── *)

let has_errors ctx =
  List.exists (fun d -> d.severity = Error) ctx.diagnostics

let has_diagnostics ctx = ctx.diagnostics <> []

(** A mark for [error_since]: the diagnostics reported so far. *)
let mark ctx = ctx.diagnostics

(** Whether an error was reported after [mark] was taken.  [report] only
    prepends, so the diagnostics since the mark are the prefix of the list
    ending at the (physically) marked list. *)
let error_since ctx mark =
  let rec go = function
    | l when l == mark -> false
    | [] -> false
    | d :: rest -> d.severity = Error || go rest
  in
  go ctx.diagnostics

let has_hints ctx =
  List.exists (fun d -> d.severity = Hint) ctx.diagnostics

let sorted ctx =
  (* [stable_sort] plus a total tiebreaker so diagnostics that SHARE a span
     (e.g. a Cap-narrowing HINT emitted at the same span as another
     diagnostic) render in a deterministic order run-to-run. Without a
     deterministic tiebreaker a non-stable sort could reorder equal-span
     diagnostics, producing display nondeterminism. *)
  let sev_rank = function Error -> 0 | Warning -> 1 | Hint -> 2 in
  List.stable_sort
    (fun a b ->
      let c = compare a.span.start_line b.span.start_line in
      if c <> 0 then c
      else
        let c = compare a.span.start_col b.span.start_col in
        if c <> 0 then c
        else
          let c = compare (sev_rank a.severity) (sev_rank b.severity) in
          if c <> 0 then c else compare a.message b.message)
    ctx.diagnostics

(** Render a diagnostic with source context.
    Shows the relevant source line with a caret underline pointing at the span.

    Format (Elm-inspired):
      -- ERROR ---------- filename
      <blank>
      message
      <blank>
      N | source line
        | ^^^^^^^^^^^^
      [notes]
*)
(* ── Codes in rendered output ────────────────────────────────────────

   Every rendered diagnostic ends its headline (the message's first line)
   with ` [slug]`. It is APPENDED to the line, never inserted, so a test or a
   corpus `EXPECT-ERROR` that greps for a fragment of the headline still
   matches. The first time a run renders a code that has a
   `march --explain` page, the diagnostic also says so; later diagnostics
   with the same code don't repeat it. *)

let explain_hints_shown : (string, unit) Hashtbl.t = Hashtbl.create 8


let headline_with_code (d : diagnostic) =
  let suffix = " [" ^ Code.slug_of d.code ^ "]" in
  match String.index_opt d.message '\n' with
  | None -> d.message ^ suffix
  | Some i ->
    String.sub d.message 0 i ^ suffix
    ^ String.sub d.message i (String.length d.message - i)

let explain_hint (d : diagnostic) =
  let slug = Code.slug_of d.code in
  if not (Explain.has_page slug)
     || Hashtbl.mem explain_hints_shown slug then ""
  else begin
    Hashtbl.replace explain_hints_shown slug ();
    "\n" ^ fmt_note (Printf.sprintf "    run `march --explain %s`" slug)
  end

let render_diagnostic ~src ?(filename = "") (d : diagnostic) : string =
  let sev_str = match d.severity with
    | Error   -> "ERROR"
    | Warning -> "WARNING"
    | Hint    -> "HINT"
  in
  let line  = d.span.March_ast.Ast.start_line in
  let col   = d.span.March_ast.Ast.start_col in
  let eline = d.span.March_ast.Ast.end_line in
  let ecol  = d.span.March_ast.Ast.end_col in
  (* Header bar *)
  let loc_str = if filename = "" then "" else " " ^ filename in
  let dashes  = String.make (max 2 (48 - String.length loc_str)) '-' in
  let header =
    if not !use_color then "-- " ^ sev_str ^ " " ^ dashes ^ loc_str
    else
      paint ansi_dim "--" ^ " " ^
      paint (sev_bold_code d.severity) sev_str ^
      paint ansi_dim (" " ^ dashes) ^
      paint ansi_cyan loc_str
  in
  (* Notes block — each note gets 4-space indent on every line *)
  let notes_block =
    if d.notes = [] then ""
    else
      "\n" ^ String.concat "\n"
        (List.map (fun n ->
           let colored = fmt_note n in
           let note_lines = String.split_on_char '\n' colored in
           String.concat "\n" (List.map (fun l -> "    " ^ l) note_lines)
         ) d.notes)
  in
  (* When no span info, just show the header and message. *)
  if line <= 0 || src = "" then
    String.concat "\n" [ header; ""; fmt_message (headline_with_code d); notes_block ]
    ^ explain_hint d
  else begin
    (* Extract the source line(s) *)
    let src_lines = String.split_on_char '\n' src in
    let get_line n = try List.nth src_lines (n - 1) with _ -> "" in
    (* Gutter: "N | " — left-pad line number to consistent width *)
    let max_line_no = if eline > line then eline else line in
    let gutter_width = String.length (string_of_int max_line_no) + 3 in (* "N | " *)
    let gutter n =
      let ns = string_of_int n in
      let pad_n = String.make (gutter_width - String.length ns - 3) ' ' in
      pad_n ^ ns ^ " | "
    in
    let pad = String.make gutter_width ' ' in
    (* Build underline: ^^^^^ under the span *)
    let src_line = get_line line in
    let underline =
      let start = col in
      (* If single-line span, underline to end_col; else to end of line *)
      let stop = if eline = line && ecol > col then ecol else String.length src_line in
      let len  = max 1 (stop - start) in
      String.make start ' ' ^ String.make len '^'
    in
    let label_blocks =
      List.filter_map (fun (lbl : label) ->
        let ll  = lbl.lbl_span.March_ast.Ast.start_line in
        let lc  = lbl.lbl_span.March_ast.Ast.start_col in
        let ell = lbl.lbl_span.March_ast.Ast.end_line in
        let elc = lbl.lbl_span.March_ast.Ast.end_col in
        if ll <= 0 || lbl.lbl_span = d.span then None
        else begin
          let lbl_src = get_line ll in
          let max_lno = max ll ell in
          let lw = String.length (string_of_int max_lno) + 3 in
          let lg n =
            let ns = string_of_int n in
            String.make (lw - String.length ns - 3) ' ' ^ ns ^ " | "
          in
          let lp = String.make lw ' ' in
          let lu =
            let stop = if ell = ll && elc > lc then elc else String.length lbl_src in
            String.make lc ' ' ^ String.make (max 1 (stop - lc)) '^'
          in
          Some (Printf.sprintf "\n    %s:\n\n%s%s\n%s%s"
            (paint ansi_dim lbl.lbl_message)
            (paint ansi_dim (lg ll)) lbl_src lp
            (paint ansi_dim lu))
        end
      ) d.labels
    in
    String.concat "\n"
      ([ header; ""; fmt_message (headline_with_code d); "";
         paint ansi_dim (gutter line) ^ src_line;
         pad ^ paint (sev_plain_code d.severity) underline;
         notes_block ]
       @ label_blocks)
    ^ explain_hint d
  end

let parse_error_diagnostic ?(filename = "") ?hint ?(code = Code.syntax_error) ~msg lexbuf =
  let pos     = Lexing.lexeme_start_p lexbuf in
  let line    = pos.Lexing.pos_lnum in
  let col     = pos.Lexing.pos_cnum - pos.Lexing.pos_bol in
  let tok     = Lexing.lexeme lexbuf in
  let tok_len = max 1 (String.length tok) in
  let span    = { March_ast.Ast.file = filename;
                  start_line = line; start_col = col;
                  end_line = line; end_col = col + tok_len } in
  let notes   = match hint with None -> [] | Some h -> [h] in
  { severity = Error; span; message = msg; labels = []; notes; code; fix = None }

let render_parse_error ~src ?(filename = "") ?hint ~msg lexbuf =
  render_diagnostic ~src ~filename (parse_error_diagnostic ~filename ?hint ~msg lexbuf)

(** Width of the token starting at ([line], [col]) in [src], for sizing a
    caret under a position that carries no lexeme: an identifier/keyword/number
    run, else one character.  [line] is 1-based, [col] 0-based (the
    [Lexing.position] convention).  Located by line/column rather than
    [pos_cnum], because some [ParseError] positions are rebuilt from spans and
    carry no absolute offset. *)
let token_len_at ~src ~line ~col =
  let n = String.length src in
  let rec line_start l i =
    if l <= 1 then Some i
    else match String.index_from_opt src i '\n' with
      | Some j -> line_start (l - 1) (j + 1)
      | None -> None
  in
  match line_start line 0 with
  | None -> 1
  | Some bol ->
    let i = bol + col in
    let is_word c =
      (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
      || (c >= '0' && c <= '9') || c = '_' in
    if i < 0 || i >= n || not (is_word src.[i]) then 1
    else begin
      let j = ref i in
      while !j < n && is_word src.[!j] do incr j done;
      !j - i
    end

(** Diagnostic for a [ParseError (msg, hint, pos)]: the span starts at [pos],
    the position the grammar's error production chose.  Use this, not the
    lexbuf form above, whenever the exception carries a position: the lexbuf
    only knows menhir's lookahead token, which is the token AFTER the one the
    message is about.  [src], when given, sizes the caret to the token at
    [pos]; [len] overrides it. *)
let parse_error_diagnostic_at ?(filename = "") ?hint ?src ?len
    ?(code = Code.parse_error) ~msg
    (pos : Lexing.position) =
  let line = pos.Lexing.pos_lnum in
  let col  = pos.Lexing.pos_cnum - pos.Lexing.pos_bol in
  let len  = match len, src with
    | Some l, _ -> max 1 l
    | None, Some src -> token_len_at ~src ~line ~col
    | None, None -> 1 in
  let file = if filename <> "" then filename else pos.Lexing.pos_fname in
  let span = { March_ast.Ast.file;
               start_line = line; start_col = col;
               end_line = line; end_col = col + len } in
  let notes = match hint with None -> [] | Some h -> [h] in
  { severity = Error; span; message = msg; labels = []; notes; code; fix = None }

let render_parse_error_at ~src ?(filename = "") ?hint ~msg pos =
  render_diagnostic ~src ~filename
    (parse_error_diagnostic_at ~filename ?hint ~src ~msg pos)

(* ── JSON output (--check-json) ───────────────────────────────────────── *)

let json_string s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (function
    | '"'  -> Buffer.add_string b "\\\""
    | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n"
    | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t"
    | c    -> Buffer.add_char b c
  ) s;
  Buffer.add_char b '"';
  Buffer.contents b

(** One NDJSON object per diagnostic.  [related] (default true) adds the
    [labels] (secondary spans, each with its message) and [notes] arrays;
    [--emit-core-ast] passes [~related:false] to keep its versioned document
    byte-stable. *)
let render_diagnostic_json ?(related = true) (d : diagnostic) : string =
  let sev = match d.severity with Error -> "error" | Warning -> "warning" | Hint -> "hint" in
  let sp  = d.span in
  let file    = json_string sp.March_ast.Ast.file in
  let msg     = json_string d.message in
  let code    = json_string d.code in
  let fix_json = match d.fix with
    | None -> "null"
    | Some (FInsert { after_line; text }) ->
      Printf.sprintf {|{"kind":"insert","after_line":%d,"text":%s}|}
        after_line (json_string text)
    | Some (FDelete { start_line; end_line }) ->
      Printf.sprintf {|{"kind":"delete","start_line":%d,"end_line":%d}|}
        start_line end_line
    | Some (FReplace { span = rs; text }) ->
      Printf.sprintf {|{"kind":"replace","start_line":%d,"start_col":%d,"end_line":%d,"end_col":%d,"text":%s}|}
        rs.March_ast.Ast.start_line rs.March_ast.Ast.start_col
        rs.March_ast.Ast.end_line   rs.March_ast.Ast.end_col
        (json_string text)
  in
  let related_json =
    if not related then ""
    else
      let label (l : label) =
        let ls = l.lbl_span in
        Printf.sprintf
          {|{"file":%s,"start_line":%d,"start_col":%d,"end_line":%d,"end_col":%d,"message":%s}|}
          (json_string ls.March_ast.Ast.file)
          ls.March_ast.Ast.start_line ls.March_ast.Ast.start_col
          ls.March_ast.Ast.end_line   ls.March_ast.Ast.end_col
          (json_string l.lbl_message)
      in
      Printf.sprintf {|,"labels":[%s],"notes":[%s]|}
        (String.concat "," (List.map label d.labels))
        (String.concat "," (List.map json_string d.notes))
  in
  Printf.sprintf
    {|{"severity":%s,"file":%s,"start_line":%d,"start_col":%d,"end_line":%d,"end_col":%d,"message":%s,"code":%s,"fix":%s%s}|}
    (json_string sev) file
    sp.March_ast.Ast.start_line sp.March_ast.Ast.start_col
    sp.March_ast.Ast.end_line   sp.March_ast.Ast.end_col
    msg code fix_json related_json
