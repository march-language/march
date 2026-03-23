(** Position and span utilities for the March LSP.

    March spans:  start_line is 1-indexed, start_col/end_col are 0-indexed.
    LSP positions: line and character are both 0-indexed. *)

module Lsp = Linol_lsp.Lsp
open March_ast.Ast

(** Convert a March span to an LSP Range. *)
let span_to_lsp_range (sp : span) : Lsp.Types.Range.t =
  let open Lsp.Types in
  Range.create
    ~start:(Position.create ~line:(sp.start_line - 1) ~character:sp.start_col)
    ~end_:(Position.create ~line:(sp.end_line - 1) ~character:sp.end_col)

(** True if the span covers the given 0-indexed LSP line+character. *)
let span_contains (sp : span) ~line ~character : bool =
  let sl = sp.start_line - 1 and sc = sp.start_col in
  let el = sp.end_line   - 1 and ec = sp.end_col  in
  if line < sl || line > el then false
  else if line = sl && line = el then character >= sc && character < ec
  else if line = sl then character >= sc
  else if line = el then character < ec
  else true

(** Rough "size" of a span in characters — used to find the most specific
    (smallest) span that contains a cursor position. *)
let span_size (sp : span) : int =
  if sp.start_line = sp.end_line then
    sp.end_col - sp.start_col
  else
    (sp.end_line - sp.start_line) * 1000 + sp.end_col

(** True if [inner] is strictly smaller than [outer]. *)
let span_smaller (inner : span) (outer : span) : bool =
  span_size inner < span_size outer

(** Convert an LSP Position to a 0-indexed (line, char) pair. *)
let lsp_pos_to_pair (pos : Lsp.Types.Position.t) : int * int =
  (pos.Lsp.Types.Position.line, pos.Lsp.Types.Position.character)

(** Create an LSP Position value. *)
let create ~line ~character : Lsp.Types.Position.t =
  Lsp.Types.Position.create ~line ~character
