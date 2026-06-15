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
  (* [a.diagnostics] carry byte-column ranges; remap to UTF-16 to honour this
     module's "positions are UTF-16" contract (the server does the same in
     [on_req_diagnostic]). *)
  List.map (Position.remap_diagnostic a.Analysis.doc) a.Analysis.diagnostics

let completions (a : Analysis.t) ~line ~utf16_char : Lsp.Types.CompletionItem.t list =
  Analysis.query_completions_at a ~line ~utf16_char

(* Just the inferred type at a position (the hover [h_type] component, exposed
   on its own so the CLI's [type] feature need not reach into [Analysis]). *)
let type_at (a : Analysis.t) ~line ~utf16_char : string option =
  Analysis.query_type_at a ~line ~utf16_char

(* (name, kind, range) for every top-level symbol in the file, where [kind] is
   a short tag ("function" | "type" | "constructor" | "interface") and [range]
   is UTF-16 (start_line, start_char, end_line, end_char). *)
type symbol = { sym_name : string; sym_kind : string; sym_range : int * int * int * int }

let symbols (a : Analysis.t) : symbol list =
  match Analysis.document_symbols a with
  | `DocumentSymbol syms ->
    (* [document_symbols] ranges are byte columns; remap to UTF-16 (the server
       does this via [Pos.remap_document_symbol] in [on_req_symbol]) so the
       module's "positions are UTF-16" contract holds. *)
    let syms = List.map (Position.remap_document_symbol a.Analysis.doc) syms in
    List.map (fun (s : Lsp.Types.DocumentSymbol.t) ->
        let r = s.Lsp.Types.DocumentSymbol.range in
        let kind =
          match s.Lsp.Types.DocumentSymbol.kind with
          | Lsp.Types.SymbolKind.Class -> "type"
          | Lsp.Types.SymbolKind.EnumMember -> "constructor"
          | Lsp.Types.SymbolKind.Interface -> "interface"
          | _ -> "function"
        in
        { sym_name = s.Lsp.Types.DocumentSymbol.name;
          sym_kind = kind;
          sym_range =
            (r.Lsp.Types.Range.start.Lsp.Types.Position.line,
             r.Lsp.Types.Range.start.Lsp.Types.Position.character,
             r.Lsp.Types.Range.end_.Lsp.Types.Position.line,
             r.Lsp.Types.Range.end_.Lsp.Types.Position.character) }) syms
  | `SymbolInformation _ -> []
