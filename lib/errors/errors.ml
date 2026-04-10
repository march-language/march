exception ParseError of string * string option * Lexing.position
(** ParseError (message, hint, position) *)

(** March error reporting.

    Errors carry provenance (source spans) and are designed
    to produce clear, non-cascading diagnostics with
    expected-vs-found framing. *)

type severity = Error | Warning | Hint [@@deriving show]

type diagnostic = {
  severity : severity;
  span : March_ast.Ast.span;
  message : string;
  labels : label list;     (** Additional labeled source spans *)
  notes : string list;      (** Extra context / suggestions *)
  code : string option;    (** Machine-readable error/warning code, e.g. "unused_binding" *)
}
[@@deriving show]

and label = {
  lbl_span : March_ast.Ast.span;
  lbl_message : string;
}
[@@deriving show]

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
  let header  = "-- " ^ sev_str ^ " " ^ dashes ^ loc_str in
  (* Notes block — each note gets 4-space indent on every line *)
  let notes_block =
    if d.notes = [] then ""
    else
      "\n" ^ String.concat "\n"
        (List.map (fun n ->
           let note_lines = String.split_on_char '\n' n in
           String.concat "\n" (List.map (fun l -> "    " ^ l) note_lines)
         ) d.notes)
  in
  (* When no span info, just show the header and message. *)
  if line <= 0 || src = "" then
    String.concat "\n" [ header; ""; d.message; notes_block ]
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
    String.concat "\n"
      [ header; ""; d.message; ""; gutter line ^ src_line; pad ^ underline; notes_block ]
  end

let render_parse_error ~src ?(filename = "") ?hint ~msg lexbuf =
  let pos  = Lexing.lexeme_start_p lexbuf in
  let line = pos.Lexing.pos_lnum in
  let col  = pos.Lexing.pos_cnum - pos.Lexing.pos_bol in
  let tok  = Lexing.lexeme lexbuf in
  (* Extract the source line being reported *)
  let src_line =
    let lines = String.split_on_char '\n' src in
    (try List.nth lines (line - 1) with _ -> "")
  in
  (* Underline the offending token (at least one ^ wide) *)
  let tok_len   = max 1 (String.length tok) in
  let underline = String.make col ' ' ^ String.make tok_len '^' in
  (* Header bar *)
  let loc_str = if filename = "" then "" else " " ^ filename in
  let dashes  = String.make (max 2 (48 - String.length loc_str)) '-' in
  let header  = "-- PARSE ERROR " ^ dashes ^ loc_str in
  (* Gutter  "N | " *)
  let gutter = Printf.sprintf "%d | " line in
  let pad    = String.make (String.length gutter) ' ' in
  (* Optional hint block — each line gets 4-space indent *)
  let hint_block = match hint with
    | Some h ->
      let lines = String.split_on_char '\n' h in
      "\n" ^ String.concat "\n" (List.map (fun l -> "    " ^ l) lines)
    | None -> ""
  in
  String.concat "\n"
    [ header; ""; msg; ""; gutter ^ src_line; pad ^ underline; hint_block ]
