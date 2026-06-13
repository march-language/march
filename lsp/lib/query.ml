(** Transport-agnostic query facade over [Analysis].

    Positions are UTF-16 (editor) columns; conversion to byte columns happens
    in the [Analysis.query_*] wrappers, so neither the LSP server nor the CLI
    touches encoding. Both drive the same code path through this module. *)

module Lsp = Linol_lsp.Lsp

type hover_result = {
  h_type : string option;
  h_doc  : string option;
  h_perf : string option;
}

(* (start_line, start_char, end_line, end_char), all UTF-16. *)
type location = { loc_uri : string; loc_range : int * int * int * int }

let hover (a : Analysis.t) ~line ~utf16_char : hover_result =
  { h_type = Analysis.query_type_at a ~line ~utf16_char;
    h_doc  = Analysis.query_doc_name_at a ~line ~utf16_char;
    h_perf = Analysis.query_perf_insight_at a ~line ~utf16_char }

let location_of (l : Lsp.Types.Location.t) : location =
  let r = l.Lsp.Types.Location.range in
  { loc_uri = Lsp.Types.DocumentUri.to_string l.Lsp.Types.Location.uri;
    loc_range =
      (r.Lsp.Types.Range.start.Lsp.Types.Position.line,
       r.Lsp.Types.Range.start.Lsp.Types.Position.character,
       r.Lsp.Types.Range.end_.Lsp.Types.Position.line,
       r.Lsp.Types.Range.end_.Lsp.Types.Position.character) }

let definition (a : Analysis.t) ~line ~utf16_char : location option =
  Option.map location_of (Analysis.query_definition_at a ~line ~utf16_char)

let references (a : Analysis.t) ~include_declaration ~line ~utf16_char : location list =
  Analysis.query_references_at a ~include_declaration ~line ~utf16_char
  |> List.map location_of

let diagnostics (a : Analysis.t) : Lsp.Types.Diagnostic.t list =
  a.Analysis.diagnostics

let completions (a : Analysis.t) ~line ~utf16_char : Lsp.Types.CompletionItem.t list =
  Analysis.query_completions_at a ~line ~utf16_char
