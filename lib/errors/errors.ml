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
    { severity = Error; span; message; labels = []; notes = [] }

let warning ctx ~span message =
  report ctx
    { severity = Warning; span; message; labels = []; notes = [] }

let hint ctx ~span message =
  report ctx
    { severity = Hint; span; message; labels = []; notes = [] }

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
  (* Optional hint block *)
  let hint_block = match hint with
    | Some h -> Printf.sprintf "\n    %s" h
    | None   -> ""
  in
  String.concat "\n"
    [ header; ""; msg; ""; gutter ^ src_line; pad ^ underline; hint_block ]
