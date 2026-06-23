exception ParseError of string * string option * Lexing.position
(** ParseError (message, hint, position) *)

(** March error reporting.

    Errors carry provenance (source spans) and are designed
    to produce clear, non-cascading diagnostics with
    expected-vs-found framing. *)

type severity = Error | Warning | Hint

type diagnostic = {
  severity : severity;
  span : March_ast.Ast.span;
  message : string;
  labels : label list;     (** Additional labeled source spans *)
  notes : string list;      (** Extra context / suggestions *)
  code : string option;    (** Machine-readable error/warning code, e.g. "unused_binding" *)
}

and label = {
  lbl_span : March_ast.Ast.span;
  lbl_message : string;
}

(** Accumulator for diagnostics — allows error recovery. *)
type ctx = { mutable diagnostics : diagnostic list }

let create () = { diagnostics = [] }

let report ctx diag = ctx.diagnostics <- diag :: ctx.diagnostics

let error ctx ~span message =
  report ctx
    { severity = Error; span; message; labels = []; notes = []; code = None }

let warning ctx ~span message =
  report ctx
    { severity = Warning; span; message; labels = []; notes = []; code = None }

let hint ctx ~span message =
  report ctx
    { severity = Hint; span; message; labels = []; notes = []; code = None }

let warning_with_code ctx ~span ~code message =
  report ctx
    { severity = Warning; span; message; labels = []; notes = []; code = Some code }

(* ── ANSI colour ──────────────────────────────────────────────────────── *)

(** Set to [true] at startup when stderr is a TTY (and NO_COLOR is absent).
    Callers (bin/main.ml) are responsible for setting this before any output. *)
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

let has_hints ctx =
  List.exists (fun d -> d.severity = Hint) ctx.diagnostics

let sorted ctx =
  List.sort
    (fun a b ->
      let c = compare a.span.start_line b.span.start_line in
      if c <> 0 then c else compare a.span.start_col b.span.start_col)
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
    String.concat "\n" [ header; ""; fmt_message d.message; notes_block ]
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
      ([ header; ""; fmt_message d.message; "";
         paint ansi_dim (gutter line) ^ src_line;
         pad ^ paint (sev_plain_code d.severity) underline;
         notes_block ]
       @ label_blocks)
  end

let parse_error_diagnostic ?(filename = "") ?hint ~msg lexbuf =
  let pos     = Lexing.lexeme_start_p lexbuf in
  let line    = pos.Lexing.pos_lnum in
  let col     = pos.Lexing.pos_cnum - pos.Lexing.pos_bol in
  let tok     = Lexing.lexeme lexbuf in
  let tok_len = max 1 (String.length tok) in
  let span    = { March_ast.Ast.file = filename;
                  start_line = line; start_col = col;
                  end_line = line; end_col = col + tok_len } in
  let notes   = match hint with None -> [] | Some h -> [h] in
  { severity = Error; span; message = msg; labels = []; notes; code = None }

let render_parse_error ~src ?(filename = "") ?hint ~msg lexbuf =
  render_diagnostic ~src ~filename (parse_error_diagnostic ~filename ?hint ~msg lexbuf)
