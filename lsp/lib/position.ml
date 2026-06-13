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

(* ---------------------------------------------------------------------- *)
(* Outbound remap: byte-column ranges (as produced internally) -> UTF-16.  *)
(* Applied at the transport boundary so every Range/Location/TextEdit/      *)
(* Diagnostic the client receives uses correct UTF-16 character columns.    *)
(* ---------------------------------------------------------------------- *)

let remap_pos (d : Utf16.doc) (p : Lsp.Types.Position.t) : Lsp.Types.Position.t =
  Lsp.Types.Position.create
    ~line:p.Lsp.Types.Position.line
    ~character:(Utf16.byte_col_to_lsp_char d
                  ~line:p.Lsp.Types.Position.line
                  ~byte_col:p.Lsp.Types.Position.character)

let remap_range (d : Utf16.doc) (r : Lsp.Types.Range.t) : Lsp.Types.Range.t =
  Lsp.Types.Range.create
    ~start:(remap_pos d r.Lsp.Types.Range.start)
    ~end_:(remap_pos d r.Lsp.Types.Range.end_)

let remap_location (d : Utf16.doc) (l : Lsp.Types.Location.t) : Lsp.Types.Location.t =
  { l with Lsp.Types.Location.range = remap_range d l.Lsp.Types.Location.range }

let remap_text_edit (d : Utf16.doc) (e : Lsp.Types.TextEdit.t) : Lsp.Types.TextEdit.t =
  { e with Lsp.Types.TextEdit.range = remap_range d e.Lsp.Types.TextEdit.range }

let remap_diagnostic (d : Utf16.doc) (dg : Lsp.Types.Diagnostic.t) : Lsp.Types.Diagnostic.t =
  { dg with Lsp.Types.Diagnostic.range = remap_range d dg.Lsp.Types.Diagnostic.range }

let remap_inlay_hint (d : Utf16.doc) (h : Lsp.Types.InlayHint.t) : Lsp.Types.InlayHint.t =
  { h with Lsp.Types.InlayHint.position = remap_pos d h.Lsp.Types.InlayHint.position }

let rec remap_document_symbol (d : Utf16.doc) (s : Lsp.Types.DocumentSymbol.t)
  : Lsp.Types.DocumentSymbol.t =
  { s with
    Lsp.Types.DocumentSymbol.range = remap_range d s.Lsp.Types.DocumentSymbol.range;
    Lsp.Types.DocumentSymbol.selectionRange =
      remap_range d s.Lsp.Types.DocumentSymbol.selectionRange;
    Lsp.Types.DocumentSymbol.children =
      Option.map (List.map (remap_document_symbol d))
        s.Lsp.Types.DocumentSymbol.children }

let remap_workspace_edit (d : Utf16.doc) (we : Lsp.Types.WorkspaceEdit.t)
  : Lsp.Types.WorkspaceEdit.t =
  match we.Lsp.Types.WorkspaceEdit.changes with
  | None -> we
  | Some chs ->
    { we with Lsp.Types.WorkspaceEdit.changes =
        Some (List.map
                (fun (uri, edits) -> (uri, List.map (remap_text_edit d) edits))
                chs) }

let remap_code_action (d : Utf16.doc) (ca : Lsp.Types.CodeAction.t)
  : Lsp.Types.CodeAction.t =
  { ca with Lsp.Types.CodeAction.edit =
      Option.map (remap_workspace_edit d) ca.Lsp.Types.CodeAction.edit }
